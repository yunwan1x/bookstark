package services

import (
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"golang.org/x/crypto/ssh"

	"bookstark/models"
)

type TerminalMessage struct {
	Type string `json:"type"`
	Data string `json:"data,omitempty"`
	Cols int    `json:"cols,omitempty"`
	Rows int    `json:"rows,omitempty"`
}

type TerminalOptions struct {
	IdleTimeout      time.Duration
	DockerContainer  string
	DefaultShell     string
	WorkingDirectory string
}

const (
	terminalWebSocketPingInterval = 25 * time.Second
	terminalWebSocketPongWait     = 60 * time.Second
	terminalWebSocketWriteWait    = 10 * time.Second
	terminalSSHKeepaliveInterval  = 30 * time.Second
	terminalSSHKeepaliveTimeout   = 10 * time.Second
)

type terminalWSWriter struct {
	ws *websocket.Conn
	mu sync.Mutex
}

func (w *terminalWSWriter) WriteJSON(v any) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	_ = w.ws.SetWriteDeadline(time.Now().Add(terminalWebSocketWriteWait))
	return w.ws.WriteJSON(v)
}

func (w *terminalWSWriter) WritePing() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.ws.WriteControl(websocket.PingMessage, nil, time.Now().Add(terminalWebSocketWriteWait))
}

func BridgeSSHTerminal(ws *websocket.Conn, host *models.AssetSSHHost, credential string, opts TerminalOptions) {
	_ = bridgeSSHTerminal(ws, host, credential, opts)
}

func bridgeSSHTerminal(ws *websocket.Conn, host *models.AssetSSHHost, credential string, opts TerminalOptions) error {
	writer := &terminalWSWriter{ws: ws}
	configureTerminalWebSocket(ws)
	auth, err := sshAuth(host.AuthType, credential)
	if err != nil {
		_ = writer.WriteJSON(TerminalMessage{Type: "error", Data: err.Error()})
		return err
	}
	config := &ssh.ClientConfig{
		User:            host.Username,
		Auth:            []ssh.AuthMethod{auth},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}
	client, err := ssh.Dial("tcp", net.JoinHostPort(host.Host, fmt.Sprintf("%d", host.Port)), config)
	if err != nil {
		safeErr := sanitizeSSHError(err)
		_ = writer.WriteJSON(TerminalMessage{Type: "error", Data: safeErr.Error()})
		return safeErr
	}
	defer client.Close()
	keepaliveStop := make(chan struct{})
	keepaliveErrors := make(chan error, 1)
	go runSSHKeepalive(client, terminalSSHKeepaliveInterval, keepaliveStop, keepaliveErrors)
	defer close(keepaliveStop)

	session, err := client.NewSession()
	if err != nil {
		_ = writer.WriteJSON(TerminalMessage{Type: "error", Data: "创建 SSH 会话失败"})
		return err
	}
	defer session.Close()

	stdin, err := session.StdinPipe()
	if err != nil {
		return err
	}
	stdout, err := session.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := session.StderrPipe()
	if err != nil {
		return err
	}
	if err := session.RequestPty("xterm", 32, 120, ssh.TerminalModes{}); err != nil {
		return err
	}
	command := shellCommand(opts)
	if err := session.Start(command); err != nil {
		return err
	}
	_ = writer.WriteJSON(TerminalMessage{Type: "ready", Data: "connected"})

	done := make(chan struct{})
	var doneOnce sync.Once
	go copyTerminalOutput(writer, stdout, done, &doneOnce)
	go copyTerminalOutput(writer, stderr, done, &doneOnce)
	go func() {
		_ = session.Wait()
		doneOnce.Do(func() { close(done) })
	}()

	idle := opts.IdleTimeout
	if idle <= 0 {
		idle = 30 * time.Minute
	}
	timer := time.NewTimer(idle)
	defer timer.Stop()
	webSocketPingTicker := time.NewTicker(terminalWebSocketPingInterval)
	defer webSocketPingTicker.Stop()

	reads := make(chan terminalReadResult)
	readStop := make(chan struct{})
	defer close(readStop)
	go readTerminalMessages(ws, reads, readStop)

	for {
		select {
		case <-done:
			_ = writer.WriteJSON(TerminalMessage{Type: "closed", Data: "session closed"})
			return nil
		case <-timer.C:
			_ = writer.WriteJSON(TerminalMessage{Type: "closed", Data: "idle timeout"})
			return nil
		case <-webSocketPingTicker.C:
			if err := writer.WritePing(); err != nil {
				return nil
			}
		case err := <-keepaliveErrors:
			_ = writer.WriteJSON(TerminalMessage{Type: "closed", Data: "SSH connection lost"})
			return err
		case result := <-reads:
			if result.err != nil {
				return nil
			}
			resetTimer(timer, idle)
			if result.msg.Type == "close" {
				return nil
			}
			if result.msg.Type == "input" {
				_, _ = io.WriteString(stdin, result.msg.Data)
			}
			if result.msg.Type == "resize" && result.msg.Cols > 0 && result.msg.Rows > 0 {
				_ = session.WindowChange(result.msg.Rows, result.msg.Cols)
			}
		}
	}
}

type terminalReadResult struct {
	msg TerminalMessage
	err error
}

func readTerminalMessages(ws *websocket.Conn, reads chan<- terminalReadResult, stop <-chan struct{}) {
	for {
		var msg TerminalMessage
		err := ws.ReadJSON(&msg)
		select {
		case reads <- terminalReadResult{msg: msg, err: err}:
		case <-stop:
			return
		}
		if err != nil {
			return
		}
	}
}

func configureTerminalWebSocket(ws *websocket.Conn) {
	_ = ws.SetReadDeadline(time.Now().Add(terminalWebSocketPongWait))
	ws.SetPongHandler(func(string) error {
		return ws.SetReadDeadline(time.Now().Add(terminalWebSocketPongWait))
	})
}

type sshKeepaliveSender interface {
	SendRequest(name string, wantReply bool, payload []byte) (bool, []byte, error)
}

func runSSHKeepalive(client sshKeepaliveSender, interval time.Duration, stop <-chan struct{}, errCh chan<- error) {
	if interval <= 0 {
		interval = terminalSSHKeepaliveInterval
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			if err := sendSSHKeepalive(client, terminalSSHKeepaliveTimeout); err != nil {
				select {
				case errCh <- err:
				default:
				}
				return
			}
		}
	}
}

func sendSSHKeepalive(client sshKeepaliveSender, timeout time.Duration) error {
	if timeout <= 0 {
		timeout = terminalSSHKeepaliveTimeout
	}
	result := make(chan error, 1)
	go func() {
		_, _, err := client.SendRequest("keepalive@openssh.com", true, nil)
		result <- err
	}()
	select {
	case err := <-result:
		return err
	case <-time.After(timeout):
		return fmt.Errorf("SSH keepalive timeout")
	}
}

func shellCommand(opts TerminalOptions) string {
	if opts.DockerContainer != "" {
		shell := opts.DefaultShell
		if shell == "" {
			shell = "/bin/sh"
		}
		return fmt.Sprintf("docker exec -it -- %s %s", terminalShellQuote(opts.DockerContainer), terminalShellQuote(shell))
	}
	if strings.TrimSpace(opts.DefaultShell) != "" {
		shell := strings.TrimSpace(opts.DefaultShell)
		if strings.TrimSpace(opts.WorkingDirectory) != "" {
			return fmt.Sprintf("cd -- %s && exec %s", terminalShellQuote(strings.TrimSpace(opts.WorkingDirectory)), shell)
		}
		return shell
	}
	if strings.TrimSpace(opts.WorkingDirectory) != "" {
		return fmt.Sprintf("cd -- %s && exec /bin/sh", terminalShellQuote(strings.TrimSpace(opts.WorkingDirectory)))
	}
	return "/bin/sh"
}

func copyTerminalOutput(writer *terminalWSWriter, r io.Reader, done chan<- struct{}, doneOnce *sync.Once) {
	buf := make([]byte, 4096)
	for {
		n, err := r.Read(buf)
		if n > 0 {
			_ = writer.WriteJSON(TerminalMessage{Type: "output", Data: string(buf[:n])})
		}
		if err != nil {
			doneOnce.Do(func() { close(done) })
			return
		}
	}
}

func resetTimer(timer *time.Timer, d time.Duration) {
	if !timer.Stop() {
		select {
		case <-timer.C:
		default:
		}
	}
	timer.Reset(d)
}

func terminalShellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
