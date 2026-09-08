package services

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestTerminalMessageJSON(t *testing.T) {
	msg := TerminalMessage{Type: "input", Data: "uptime\n"}
	b, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	var decoded TerminalMessage
	if err := json.Unmarshal(b, &decoded); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	if decoded.Type != "input" || decoded.Data != "uptime\n" {
		t.Fatalf("decoded = %#v", decoded)
	}
}

func TestTerminalShellCommand(t *testing.T) {
	if got := shellCommand(TerminalOptions{}); got != "/bin/sh" {
		t.Fatalf("shellCommand(default) = %q, want /bin/sh", got)
	}
	if got := shellCommand(TerminalOptions{DefaultShell: "/bin/bash"}); got != "/bin/bash" {
		t.Fatalf("shellCommand(shell) = %q, want /bin/bash", got)
	}
	if got := shellCommand(TerminalOptions{DefaultShell: "/bin/bash", WorkingDirectory: "/srv/app"}); got != "cd -- '/srv/app' && exec /bin/bash" {
		t.Fatalf("shellCommand(cwd) = %q", got)
	}
	if got := shellCommand(TerminalOptions{DockerContainer: "web'01", DefaultShell: "/bin/sh"}); got != "docker exec -it -- 'web'\\''01' '/bin/sh'" {
		t.Fatalf("shellCommand(docker) = %q", got)
	}
}

type fakeSSHKeepaliveSender struct {
	requests chan string
	err      error
	block    <-chan struct{}
}

func (f *fakeSSHKeepaliveSender) SendRequest(name string, wantReply bool, payload []byte) (bool, []byte, error) {
	if !wantReply {
		return false, nil, errors.New("keepalive must request a reply")
	}
	select {
	case f.requests <- name:
	default:
	}
	if f.block != nil {
		<-f.block
	}
	return true, nil, f.err
}

func TestRunSSHKeepalive(t *testing.T) {
	sender := &fakeSSHKeepaliveSender{requests: make(chan string, 1)}
	stop := make(chan struct{})
	errCh := make(chan error, 1)
	done := make(chan struct{})
	go func() {
		runSSHKeepalive(sender, 5*time.Millisecond, stop, errCh)
		close(done)
	}()

	select {
	case name := <-sender.requests:
		if name != "keepalive@openssh.com" {
			t.Fatalf("SendRequest() name = %q", name)
		}
	case <-time.After(time.Second):
		t.Fatal("SSH keepalive request was not sent")
	}
	close(stop)
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("SSH keepalive did not stop")
	}
	select {
	case err := <-errCh:
		t.Fatalf("unexpected keepalive error: %v", err)
	default:
	}
}

func TestRunSSHKeepaliveReportsFailure(t *testing.T) {
	wantErr := errors.New("connection closed")
	sender := &fakeSSHKeepaliveSender{requests: make(chan string, 1), err: wantErr}
	stop := make(chan struct{})
	errCh := make(chan error, 1)
	go runSSHKeepalive(sender, 5*time.Millisecond, stop, errCh)
	defer close(stop)

	select {
	case err := <-errCh:
		if !errors.Is(err, wantErr) {
			t.Fatalf("keepalive error = %v, want %v", err, wantErr)
		}
	case <-time.After(time.Second):
		t.Fatal("SSH keepalive failure was not reported")
	}
}

func TestSendSSHKeepaliveTimesOut(t *testing.T) {
	block := make(chan struct{})
	defer close(block)
	sender := &fakeSSHKeepaliveSender{requests: make(chan string, 1), block: block}
	started := time.Now()
	err := sendSSHKeepalive(sender, 10*time.Millisecond)
	if err == nil || !strings.Contains(err.Error(), "timeout") {
		t.Fatalf("sendSSHKeepalive() error = %v", err)
	}
	if time.Since(started) > time.Second {
		t.Fatal("SSH keepalive timeout did not return promptly")
	}
}

func TestTerminalWebSocketPingPong(t *testing.T) {
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
	serverDone := make(chan error, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			serverDone <- err
			return
		}
		defer conn.Close()
		configureTerminalWebSocket(conn)
		pong := make(chan struct{}, 1)
		conn.SetPongHandler(func(string) error {
			_ = conn.SetReadDeadline(time.Now().Add(terminalWebSocketPongWait))
			select {
			case pong <- struct{}{}:
			default:
			}
			return nil
		})
		go func() {
			_, _, _ = conn.ReadMessage()
		}()
		writer := &terminalWSWriter{ws: conn}
		if err := writer.WritePing(); err != nil {
			serverDone <- err
			return
		}
		select {
		case <-pong:
			serverDone <- writer.WriteJSON(TerminalMessage{Type: "ready"})
		case <-time.After(time.Second):
			serverDone <- errors.New("websocket pong timeout")
		}
	}))
	defer server.Close()

	url := "ws" + strings.TrimPrefix(server.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("Dial() error = %v", err)
	}
	defer conn.Close()
	var msg TerminalMessage
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatalf("ReadJSON() error = %v", err)
	}
	if msg.Type != "ready" {
		t.Fatalf("message type = %q", msg.Type)
	}
	if err := <-serverDone; err != nil {
		t.Fatalf("server heartbeat error = %v", err)
	}
}
