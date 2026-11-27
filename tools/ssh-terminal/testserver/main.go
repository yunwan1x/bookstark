package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"fmt"
	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
)

func main() {
	dir := os.Args[1]
	_, key, _ := ed25519.GenerateKey(rand.Reader)
	signer, _ := ssh.NewSignerFromKey(key)
	block, _ := ssh.MarshalPrivateKey(key, "BookStark QA only")
	os.WriteFile(filepath.Join(dir, "test-key"), pem.EncodeToMemory(block), 0600)
	encrypted, err := ssh.MarshalPrivateKeyWithPassphrase(key, "BookStark QA only", []byte("test-key-passphrase"))
	if err != nil {
		panic(err)
	}
	os.WriteFile(filepath.Join(dir, "test-key-encrypted"), pem.EncodeToMemory(encrypted), 0600)
	config := &ssh.ServerConfig{PasswordCallback: func(c ssh.ConnMetadata, p []byte) (*ssh.Permissions, error) {
		if c.User() == "tester" && string(p) == "terminal-test-only" {
			return nil, nil
		}
		return nil, fmt.Errorf("denied")
	}, PublicKeyCallback: func(c ssh.ConnMetadata, k ssh.PublicKey) (*ssh.Permissions, error) {
		if c.User() == "tester" && string(k.Marshal()) == string(signer.PublicKey().Marshal()) {
			return nil, nil
		}
		return nil, fmt.Errorf("denied")
	}}
	config.AddHostKey(signer)
	listener, err := net.Listen("tcp", "127.0.0.1:18222")
	if err != nil {
		panic(err)
	}
	fmt.Println("SSH fixture ready", ssh.FingerprintSHA256(signer.PublicKey()))
	for {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		go func() {
			defer conn.Close()
			sc, chans, requests, err := ssh.NewServerConn(conn, config)
			if err != nil {
				return
			}
			defer sc.Close()
			go ssh.DiscardRequests(requests)
			for ch := range chans {
				if ch.ChannelType() != "session" {
					ch.Reject(ssh.UnknownChannelType, "session only")
					continue
				}
				channel, requests, err := ch.Accept()
				if err != nil {
					continue
				}
				go func() {
					defer channel.Close()
					var cmd *exec.Cmd
					var mu sync.Mutex
					cols, rows := uint32(80), uint32(24)
					for r := range requests {
						switch r.Type {
						case "pty-req":
							var p struct {
								Term                      string
								Cols, Rows, Width, Height uint32
								Modes                     string
							}
							ssh.Unmarshal(r.Payload, &p)
							cols, rows = p.Cols, p.Rows
							r.Reply(true, nil)
						case "window-change":
							var p struct{ Cols, Rows, Width, Height uint32 }
							ssh.Unmarshal(r.Payload, &p)
							mu.Lock()
							cols, rows = p.Cols, p.Rows
							mu.Unlock()
							r.Reply(true, nil)
						case "shell":
							r.Reply(true, nil)
							cmd = exec.Command("bash", "--noprofile", "--norc", "-i")
							cmd.Env = append(os.Environ(), "PS1=tester@bookstark-qa:~$ ", "TERM=xterm-256color")
							in, _ := cmd.StdinPipe()
							cmd.Stdout = channel
							cmd.Stderr = channel
							cmd.Start()
							go io.Copy(in, channel)
							go func() {
								cmd.Wait()
								channel.SendRequest("exit-status", false, ssh.Marshal(struct{ Code uint32 }{0}))
								channel.Close()
							}()
						case "subsystem":
							if len(r.Payload) >= 4 && string(r.Payload[4:]) == "sftp" {
								r.Reply(true, nil)
								go func() {
									srv, err := sftp.NewServer(channel)
									if err == nil {
										_ = srv.Serve()
										srv.Close()
									}
									channel.Close()
								}()
							} else {
								r.Reply(false, nil)
							}
						case "env":
							r.Reply(true, nil)
						default:
							r.Reply(false, nil)
						}
					}
					if cmd != nil {
						cmd.Process.Kill()
					}
					_ = cols
					_ = rows
				}()
			}
		}()
	}
}
