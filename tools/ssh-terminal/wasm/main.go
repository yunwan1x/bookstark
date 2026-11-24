//go:build js && wasm

// SSH lives in the tool, not in BookStark's administrative SSH service.
package main

import (
	"bookstark-ssh-terminal/internal/sessionconfig"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strconv"
	"sync"
	"syscall/js"
	"time"

	"golang.org/x/crypto/ssh"
)

type configuration struct {
	Host       string `json:"host"`
	Shell      string `json:"shell"`
	Port       int    `json:"port"`
	User       string `json:"user"`
	Auth       string `json:"auth"`
	Password   string `json:"password"`
	Key        string `json:"key"`
	Passphrase string `json:"passphrase"`
	Cols       int    `json:"cols"`
	Rows       int    `json:"rows"`
}
type connection struct {
	id        string
	pipe      net.Conn
	transport net.Conn
	input     chan []byte
	keyboard  chan []byte
	resize    chan [2]int
	output    chan bool
	outputMu  sync.Mutex
	writes    chan bool
	trust     chan bool
	done      chan struct{}
	once      sync.Once
	session   *ssh.Session
	stdin     io.WriteCloser
}

var sessions = map[string]*connection{}
var emit js.Value
var callback js.Func

func event(id, kind string, fields map[string]any) {
	if fields == nil {
		fields = map[string]any{}
	}
	fields["id"] = id
	fields["type"] = kind
	emit.Invoke(js.ValueOf(fields))
}
func bytesEvent(id, kind string, data []byte) {
	b := js.Global().Get("Uint8Array").New(len(data))
	js.CopyBytesToJS(b, data)
	emit.Invoke(map[string]any{"id": id, "type": kind, "data": b})
}
func (c *connection) close(reason string) {
	c.once.Do(func() {
		close(c.done)
		c.pipe.Close()
		c.transport.Close()
		if c.session != nil {
			c.session.Close()
		}
		delete(sessions, c.id)
		event(c.id, "closed", map[string]any{"reason": reason})
	})
}
func (c *connection) bridge() {
	go func() {
		for {
			select {
			case b := <-c.input:
				if _, err := c.transport.Write(b); err != nil {
					return
				}
				event(c.id, "read-ack", nil)
			case <-c.done:
				return
			}
		}
	}()
	go func() {
		b := make([]byte, 32*1024)
		for {
			n, err := c.transport.Read(b)
			if n > 0 {
				bytesEvent(c.id, "transport-write", b[:n])
				select {
				case ok := <-c.writes:
					if !ok {
						c.close("TCP 写入失败")
						return
					}
				case <-c.done:
					return
				}
			}
			if err != nil {
				return
			}
		}
	}()
}
func (c *connection) start(cfg configuration) {
	command, err := sessionconfig.ShellCommand(cfg.Shell)
	if err != nil {
		c.close("Shell 程序无效，请使用程序名或绝对路径")
		return
	}
	c.bridge()
	timer := time.AfterFunc(60*time.Second, func() { c.close("连接超时，请重试") })
	defer timer.Stop()
	auth := []ssh.AuthMethod{}
	if cfg.Auth == "key" {
		var signer ssh.Signer
		var err error
		if cfg.Passphrase != "" {
			signer, err = ssh.ParsePrivateKeyWithPassphrase([]byte(cfg.Key), []byte(cfg.Passphrase))
		} else {
			signer, err = ssh.ParsePrivateKey([]byte(cfg.Key))
		}
		cfg.Key = ""
		cfg.Passphrase = ""
		if err != nil {
			c.close("无法解析私钥，请检查格式和口令")
			return
		}
		auth = append(auth, ssh.PublicKeys(signer))
	} else {
		password := cfg.Password
		cfg.Password = ""
		auth = append(auth, ssh.Password(password), ssh.KeyboardInteractive(func(user, instruction string, questions []string, echo []bool) ([]string, error) {
			if len(questions) != 1 || len(echo) != 1 || echo[0] {
				return nil, fmt.Errorf("unsupported interactive challenge")
			}
			return []string{password}, nil
		}))
	}
	clientConfig := &ssh.ClientConfig{User: cfg.User, Auth: auth, HostKeyCallback: func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		event(c.id, "host-key", map[string]any{"host": cfg.Host, "port": cfg.Port, "algorithm": key.Type(), "fingerprint": ssh.FingerprintSHA256(key), "key": base64.StdEncoding.EncodeToString(key.Marshal())})
		select {
		case yes := <-c.trust:
			if yes {
				return nil
			}
			return fmt.Errorf("主机密钥未确认")
		case <-c.done:
			return io.EOF
		}
	}}
	raw, chans, reqs, err := ssh.NewClientConn(c.pipe, net.JoinHostPort(cfg.Host, strconv.Itoa(cfg.Port)), clientConfig)
	clientConfig.Auth = nil
	auth = nil
	if err != nil {
		c.close("SSH 连接失败：" + err.Error())
		return
	}
	client := ssh.NewClient(raw, chans, reqs)
	defer client.Close()
	sess, err := client.NewSession()
	if err != nil {
		c.close("无法创建 SSH 会话：" + err.Error())
		return
	}
	c.session = sess
	if cfg.Cols < 2 {
		cfg.Cols = 80
	}
	if cfg.Rows < 2 {
		cfg.Rows = 24
	}
	if err = sess.RequestPty("xterm-256color", cfg.Rows, cfg.Cols, ssh.TerminalModes{ssh.ECHO: 1, ssh.TTY_OP_ISPEED: 14400, ssh.TTY_OP_OSPEED: 14400}); err != nil {
		c.close("服务器拒绝 PTY：" + err.Error())
		return
	}
	c.stdin, err = sess.StdinPipe()
	if err != nil {
		c.close("无法打开标准输入")
		return
	}
	out := terminalOutput{c}
	sess.Stdout = out
	sess.Stderr = out
	go func() {
		for {
			select {
			case b := <-c.keyboard:
				if _, err := c.stdin.Write(b); err != nil {
					c.close("输入失败")
					return
				}
				event(c.id, "input-ack", nil)
			case <-c.done:
				return
			}
		}
	}()
	if command == "" {
		err = sess.Shell()
	} else {
		err = sess.Start(command)
	}
	if err != nil {
		c.close("无法启动 Shell：" + err.Error())
		return
	}
	timer.Stop()
	go func() {
		for {
			select {
			case size := <-c.resize:
				if err := sess.WindowChange(size[1], size[0]); err != nil {
					c.close("连接已断开")
					return
				}
			case <-c.done:
				return
			}
		}
	}()
	event(c.id, "connected", nil)
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				reply := make(chan error, 1)
				go func() { _, _, err := client.SendRequest("keepalive@openssh.com", true, nil); reply <- err }()
				select {
				case err := <-reply:
					if err != nil {
						c.close("连接已断开")
						return
					}
				case <-time.After(15 * time.Second):
					c.close("连接超时，请重试")
					return
				case <-c.done:
					return
				}

			case <-c.done:
				return
			}
		}
	}()
	if err := sess.Wait(); err != nil {
		c.close("Shell 已退出：" + err.Error())
		return
	}
	c.close("会话已结束")
}

type terminalOutput struct{ c *connection }

func (w terminalOutput) Write(b []byte) (int, error) {
	w.c.outputMu.Lock()
	defer w.c.outputMu.Unlock()
	bytesEvent(w.c.id, "output", b)
	select {
	case <-w.c.output:
		return len(b), nil
	case <-w.c.done:
		return 0, io.EOF
	}
}
func copyBytes(v js.Value) []byte {
	b := make([]byte, v.Get("byteLength").Int())
	js.CopyBytesToGo(b, v)
	return b
}
func main() {
	emit = js.Global().Get("postMessage")
	callback = js.FuncOf(func(this js.Value, args []js.Value) any {
		m := args[0]
		id := m.Get("id").String()
		kind := m.Get("type").String()
		c := sessions[id]
		if kind == "connect" {
			if c != nil {
				return nil
			}
			var cfg configuration
			if err := json.Unmarshal([]byte(js.Global().Get("JSON").Call("stringify", m).String()), &cfg); err != nil {
				return nil
			}
			a, b := net.Pipe()
			c = &connection{id: id, pipe: a, transport: b, input: make(chan []byte, 4), keyboard: make(chan []byte, 4), resize: make(chan [2]int, 1), output: make(chan bool, 1), writes: make(chan bool, 1), trust: make(chan bool, 1), done: make(chan struct{})}
			sessions[id] = c
			go c.start(cfg)
			return nil
		}
		if c == nil {
			return nil
		}
		switch kind {
		case "data":
			b := copyBytes(m.Get("data"))
			select {
			case c.input <- b:
			default:
				go c.close("接收队列已满")
			}
		case "write-ack":
			select {
			case c.writes <- m.Get("ok").Bool():
			default:
			}
		case "trust":
			select {
			case c.trust <- m.Get("accept").Bool():
			default:
			}
		case "input":
			b := copyBytes(m.Get("data"))
			select {
			case c.keyboard <- b:
			default:
				go c.close("输入队列已满")
			}
		case "output-ack":
			select {
			case c.output <- true:
			default:
			}

		case "resize":
			cols, rows := m.Get("cols").Int(), m.Get("rows").Int()
			if cols > 1 && rows > 1 {
				size := [2]int{cols, rows}
				select {
				case c.resize <- size:
				default:
					select {
					case <-c.resize:
					default:
					}
					select {
					case c.resize <- size:
					default:
					}
				}
			}

		case "close":
			go c.close("连接已断开")
		}
		return nil
	})
	js.Global().Set("bookstarkSSH", callback)
	event("", "ready", nil)
	select {}
}
