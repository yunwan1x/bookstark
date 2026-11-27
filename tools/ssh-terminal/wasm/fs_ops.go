//go:build js && wasm

package main

import (
	"bookstark-ssh-terminal/internal/webdavclient"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"net"
	"os"
	"path"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall/js"
	"time"

	"github.com/pkg/sftp"
)

// ---------------- Dial Bridge for WebDAV over BookStark.sockets ----------------

type dialSocket struct {
	dialID string
	pipe   net.Conn
	peer   net.Conn
	opened chan error
	input  chan []byte
	writes chan bool
	done   chan struct{}
	once   sync.Once
}

var (
	dialMu    sync.Mutex
	dialSocks = map[string]*dialSocket{}
	dialSeq   uint64
)

func (d *dialSocket) close() {
	d.once.Do(func() {
		close(d.done)
		_ = d.pipe.Close()
		_ = d.peer.Close()
		dialMu.Lock()
		delete(dialSocks, d.dialID)
		dialMu.Unlock()
		event("", "dial-close", map[string]any{"dialId": d.dialID})
	})
}

func dialViaBridge(ctx context.Context, sessionID, addr string) (net.Conn, error) {
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, err
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, err
	}
	dialID := fmt.Sprintf("d-%d", atomic.AddUint64(&dialSeq, 1))
	a, b := net.Pipe()
	ds := &dialSocket{
		dialID: dialID,
		pipe:   a,
		peer:   b,
		opened: make(chan error, 1),
		input:  make(chan []byte, 32),
		writes: make(chan bool, 1),
		done:   make(chan struct{}),
	}
	dialMu.Lock()
	dialSocks[dialID] = ds
	dialMu.Unlock()

	event(sessionID, "dial-socket", map[string]any{
		"dialId": dialID,
		"host":   host,
		"port":   port,
	})

	select {
	case err := <-ds.opened:
		if err != nil {
			ds.close()
			return nil, err
		}
	case <-ctx.Done():
		ds.close()
		return nil, ctx.Err()
	case <-time.After(30 * time.Second):
		ds.close()
		return nil, fmt.Errorf("TCP 连接超时 (%s)", addr)
	}

	// Pump peer <-> JS BookStark.sockets
	go func() {
		defer ds.close()
		for {
			select {
			case chunk := <-ds.input:
				if _, err := ds.peer.Write(chunk); err != nil {
					return
				}
				event("", "dial-read-ack", map[string]any{"dialId": dialID})
			case <-ds.done:
				return
			}
		}
	}()
	go func() {
		defer ds.close()
		buf := make([]byte, 32*1024)
		for {
			n, err := ds.peer.Read(buf)
			if n > 0 {
				jsBuf := js.Global().Get("Uint8Array").New(n)
				js.CopyBytesToJS(jsBuf, buf[:n])
				emit.Invoke(map[string]any{
					"type":   "dial-write",
					"dialId": dialID,
					"data":   jsBuf,
				})
				select {
				case ok := <-ds.writes:
					if !ok {
						return
					}
				case <-ds.done:
					return
				}
			}
			if err != nil {
				return
			}
		}
	}()

	return ds.pipe, nil
}

func handleDialMessage(kind string, m js.Value) {
	dialID := m.Get("dialId").String()
	dialMu.Lock()
	ds := dialSocks[dialID]
	dialMu.Unlock()
	if ds == nil {
		return
	}
	switch kind {
	case "dial-open":
		if m.Get("ok").Bool() {
			select {
			case ds.opened <- nil:
			default:
			}
		} else {
			msg := m.Get("error").String()
			if msg == "" {
				msg = "无法建立 TCP 连接"
			}
			select {
			case ds.opened <- fmt.Errorf("%s", msg):
			default:
			}
		}
	case "dial-data":
		b := copyBytes(m.Get("data"))
		select {
		case ds.input <- b:
		case <-ds.done:
		}
	case "dial-write-ack":
		select {
		case ds.writes <- m.Get("ok").Bool():
		default:
		}
	case "dial-close":
		go ds.close()
	}
}

// ---------------- WebDAV Sessions ----------------

type davConfig struct {
	URL                string `json:"url"`
	User               string `json:"user"`
	Password           string `json:"password"`
	BasePath           string `json:"basePath"`
	InsecureSkipVerify bool   `json:"insecureSkipVerify"`
}

type davSession struct {
	id     string
	client *webdavclient.Client
}

var (
	davMu       sync.Mutex
	davSessions = map[string]*davSession{}
)

func handleDavConnect(id string, m js.Value) {
	var cfg davConfig
	if err := json.Unmarshal([]byte(js.Global().Get("JSON").Call("stringify", m).String()), &cfg); err != nil {
		event(id, "dav-error", map[string]any{"reason": "无效的 WebDAV 配置"})
		return
	}
	cl, err := webdavclient.New(webdavclient.Config{
		URL:                cfg.URL,
		User:               cfg.User,
		Password:           cfg.Password,
		BasePath:           cfg.BasePath,
		InsecureSkipVerify: cfg.InsecureSkipVerify,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialViaBridge(ctx, id, addr)
		},
	})
	if err != nil {
		event(id, "dav-error", map[string]any{"reason": err.Error()})
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cwd, entries, err := cl.List(ctx, "/")
	if err != nil {
		cl.Close()
		event(id, "dav-error", map[string]any{"reason": err.Error()})
		return
	}
	davMu.Lock()
	if old := davSessions[id]; old != nil {
		old.client.Close()
	}
	davSessions[id] = &davSession{id: id, client: cl}
	davMu.Unlock()

	rawEntries, _ := json.Marshal(entries)
	event(id, "dav-connected", map[string]any{
		"cwd":     cwd,
		"entries": string(rawEntries),
	})
}

func handleDavTest(reqID string, m js.Value) {
	var cfg davConfig
	if err := json.Unmarshal([]byte(js.Global().Get("JSON").Call("stringify", m).String()), &cfg); err != nil {
		event("", "dav-test-res", map[string]any{"reqId": reqID, "ok": false, "error": "配置解析失败"})
		return
	}
	start := time.Now()
	cl, err := webdavclient.New(webdavclient.Config{
		URL:                cfg.URL,
		User:               cfg.User,
		Password:           cfg.Password,
		BasePath:           cfg.BasePath,
		InsecureSkipVerify: cfg.InsecureSkipVerify,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return dialViaBridge(ctx, "", addr)
		},
	})
	if err != nil {
		event("", "dav-test-res", map[string]any{"reqId": reqID, "ok": false, "error": err.Error()})
		return
	}
	defer cl.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_, entries, err := cl.List(ctx, "/")
	if err != nil {
		event("", "dav-test-res", map[string]any{"reqId": reqID, "ok": false, "error": err.Error()})
		return
	}
	event("", "dav-test-res", map[string]any{
		"reqId": reqID,
		"ok":    true,
		"ms":    int(time.Since(start).Milliseconds()),
		"count": len(entries),
	})
}

func handleDavClose(id string) {
	davMu.Lock()
	if s := davSessions[id]; s != nil {
		s.client.Close()
		delete(davSessions, id)
	}
	davMu.Unlock()
}

// ---------------- Unified FS RPC (SFTP + WebDAV) ----------------

func sendFSResult(sessionID, reqID string, payload map[string]any) {
	if payload == nil {
		payload = map[string]any{}
	}
	payload["reqId"] = reqID
	payload["ok"] = true
	event(sessionID, "fs-res", payload)
}

func sendFSBytesResult(sessionID, reqID string, data []byte, size int64, truncated bool) {
	b := js.Global().Get("Uint8Array").New(len(data))
	js.CopyBytesToJS(b, data)
	emit.Invoke(map[string]any{
		"id":        sessionID,
		"type":      "fs-res",
		"reqId":     reqID,
		"ok":        true,
		"data":      b,
		"size":      size,
		"truncated": truncated,
	})
}

func sendFSError(sessionID, reqID, errMsg string) {
	event(sessionID, "fs-res", map[string]any{
		"reqId": reqID,
		"ok":    false,
		"error": errMsg,
	})
}

func sendFSProgress(sessionID, reqID string, done, total int64) {
	event(sessionID, "fs-progress", map[string]any{
		"reqId": reqID,
		"done":  done,
		"total": total,
	})
}

func (c *connection) ensureSFTP() (*sftp.Client, error) {
	c.sftpMu.Lock()
	defer c.sftpMu.Unlock()
	if c.sftp != nil {
		return c.sftp, nil
	}
	if c.client == nil {
		return nil, fmt.Errorf("SSH 尚未连接")
	}
	sc, err := sftp.NewClient(c.client)
	if err != nil {
		return nil, fmt.Errorf("无法启动 SFTP 子系统：%w", err)
	}
	c.sftp = sc
	return sc, nil
}

func handleFSRequest(sessionID string, m js.Value) {
	reqID := m.Get("reqId").String()
	op := m.Get("op").String()
	targetPath := ""
	if p := m.Get("path"); !p.IsUndefined() && !p.IsNull() {
		targetPath = p.String()
	}

	// Check if this is a WebDAV session first
	davMu.Lock()
	dav := davSessions[sessionID]
	davMu.Unlock()

	if dav != nil {
		handleDavFS(dav, reqID, op, targetPath, m)
		return
	}

	c := getSession(sessionID)
	if c == nil {
		sendFSError(sessionID, reqID, "会话已断开")
		return
	}
	handleSFTPFS(c, reqID, op, targetPath, m)
}

func handleDavFS(s *davSession, reqID, op, targetPath string, m js.Value) {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	switch op {
	case "list":
		cwd, entries, err := s.client.List(ctx, targetPath)
		if err != nil {
			sendFSError(s.id, reqID, err.Error())
			return
		}
		raw, _ := json.Marshal(entries)
		sendFSResult(s.id, reqID, map[string]any{"cwd": cwd, "entries": string(raw)})
	case "read":
		maxBytes := int64(2 * 1024 * 1024)
		if mv := m.Get("maxBytes"); !mv.IsUndefined() && !mv.IsNull() {
			maxBytes = int64(mv.Int())
		}
		var lastReport time.Time
		data, total, trunc, err := s.client.Read(ctx, targetPath, maxBytes, func(done, tot int64) {
			if time.Since(lastReport) > 80*time.Millisecond || (tot > 0 && done >= tot) {
				lastReport = time.Now()
				sendFSProgress(s.id, reqID, done, tot)
			}
		})
		if err != nil {
			sendFSError(s.id, reqID, err.Error())
			return
		}
		sendFSBytesResult(s.id, reqID, data, total, trunc)
	case "write":
		data := copyBytes(m.Get("data"))
		err := s.client.Write(ctx, targetPath, data, func(done, tot int64) {
			sendFSProgress(s.id, reqID, done, tot)
		})
		if err != nil {
			sendFSError(s.id, reqID, err.Error())
			return
		}
		sendFSResult(s.id, reqID, map[string]any{"size": len(data)})
	case "mkdir":
		if err := s.client.Mkdir(ctx, targetPath); err != nil {
			sendFSError(s.id, reqID, err.Error())
			return
		}
		sendFSResult(s.id, reqID, nil)
	case "rename":
		toPath := m.Get("to").String()
		if err := s.client.Rename(ctx, targetPath, toPath); err != nil {
			sendFSError(s.id, reqID, err.Error())
			return
		}
		sendFSResult(s.id, reqID, nil)
	case "delete":
		if err := s.client.Delete(ctx, targetPath); err != nil {
			sendFSError(s.id, reqID, err.Error())
			return
		}
		sendFSResult(s.id, reqID, nil)
	default:
		sendFSError(s.id, reqID, "WebDAV 不支持此操作："+op)
	}
}

func handleSFTPFS(c *connection, reqID, op, targetPath string, m js.Value) {
	sc, err := c.ensureSFTP()
	if err != nil {
		sendFSError(c.id, reqID, err.Error())
		return
	}
	switch op {
	case "list":
		dir := strings.TrimSpace(targetPath)
		if dir == "" || dir == "~" {
			if wd, err := sc.Getwd(); err == nil && wd != "" {
				dir = wd
			} else {
				dir = "/"
			}
		} else {
			dir = path.Clean(dir)
		}
		infos, err := sc.ReadDir(dir)
		if err != nil {
			sendFSError(c.id, reqID, "无法读取目录："+err.Error())
			return
		}
		entries := make([]webdavclient.Entry, 0, len(infos))
		for _, info := range infos {
			name := info.Name()
			full := path.Join(dir, name)
			isDir := info.IsDir()
			if info.Mode()&os.ModeSymlink != 0 {
				if st, err := sc.Stat(full); err == nil && st.IsDir() {
					isDir = true
				}
			}
			mt := ""
			if !isDir {
				mt = mime.TypeByExtension(path.Ext(name))
			}
			entries = append(entries, webdavclient.Entry{
				Name:    name,
				Path:    full,
				IsDir:   isDir,
				Size:    info.Size(),
				Mode:    fmt.Sprintf("%04o", info.Mode().Perm()),
				ModTime: info.ModTime().Unix(),
				Mime:    mt,
			})
		}
		sort.Slice(entries, func(i, j int) bool {
			if entries[i].IsDir != entries[j].IsDir {
				return entries[i].IsDir
			}
			return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
		})
		raw, _ := json.Marshal(entries)
		sendFSResult(c.id, reqID, map[string]any{"cwd": dir, "entries": string(raw)})

	case "read":
		maxBytes := int64(2 * 1024 * 1024)
		if mv := m.Get("maxBytes"); !mv.IsUndefined() && !mv.IsNull() {
			maxBytes = int64(mv.Int())
		}
		f, err := sc.Open(targetPath)
		if err != nil {
			sendFSError(c.id, reqID, "无法打开文件："+err.Error())
			return
		}
		defer f.Close()
		var total int64
		if st, err := f.Stat(); err == nil {
			total = st.Size()
		}
		out := make([]byte, 0, minInt64(total, 64*1024))
		buf := make([]byte, 32*1024)
		var done int64
		truncated := false
		var lastReport time.Time
		for {
			n, rerr := f.Read(buf)
			if n > 0 {
				if maxBytes > 0 && done+int64(n) > maxBytes {
					remain := maxBytes - done
					if remain > 0 {
						out = append(out, buf[:remain]...)
						done += remain
					}
					truncated = true
					break
				}
				out = append(out, buf[:n]...)
				done += int64(n)
				if time.Since(lastReport) > 80*time.Millisecond || (total > 0 && done >= total) {
					lastReport = time.Now()
					sendFSProgress(c.id, reqID, done, total)
				}
			}
			if rerr == io.EOF {
				break
			}
			if rerr != nil {
				sendFSError(c.id, reqID, "读取文件失败："+rerr.Error())
				return
			}
		}
		sendFSBytesResult(c.id, reqID, out, total, truncated)

	case "write":
		data := copyBytes(m.Get("data"))
		f, err := sc.Create(targetPath)
		if err != nil {
			sendFSError(c.id, reqID, "无法写入文件："+err.Error())
			return
		}
		total := int64(len(data))
		var written int64
		var lastReport time.Time
		const chunkSize = 32 * 1024
		for offset := 0; offset < len(data); offset += chunkSize {
			end := offset + chunkSize
			if end > len(data) {
				end = len(data)
			}
			n, werr := f.Write(data[offset:end])
			written += int64(n)
			if werr != nil {
				_ = f.Close()
				sendFSError(c.id, reqID, "上传失败："+werr.Error())
				return
			}
			if time.Since(lastReport) > 80*time.Millisecond || written >= total {
				lastReport = time.Now()
				sendFSProgress(c.id, reqID, written, total)
			}
		}
		if err := f.Close(); err != nil {
			sendFSError(c.id, reqID, "保存文件失败："+err.Error())
			return
		}
		sendFSProgress(c.id, reqID, total, total)
		sendFSResult(c.id, reqID, map[string]any{"size": total})

	case "mkdir":
		if err := sc.MkdirAll(targetPath); err != nil {
			sendFSError(c.id, reqID, "创建目录失败："+err.Error())
			return
		}
		sendFSResult(c.id, reqID, nil)

	case "rename":
		toPath := m.Get("to").String()
		if err := sc.Rename(targetPath, toPath); err != nil {
			sendFSError(c.id, reqID, "重命名失败："+err.Error())
			return
		}
		sendFSResult(c.id, reqID, nil)

	case "chmod":
		modeStr := strings.TrimSpace(m.Get("mode").String())
		parsed, err := strconv.ParseUint(modeStr, 8, 32)
		if err != nil || parsed > 0o7777 {
			sendFSError(c.id, reqID, "权限格式无效，请输入如 0644 或 0755")
			return
		}
		if err := sc.Chmod(targetPath, os.FileMode(parsed)); err != nil {
			sendFSError(c.id, reqID, "修改权限失败："+err.Error())
			return
		}
		sendFSResult(c.id, reqID, nil)

	case "delete":
		if err := removeSFTPRecursive(sc, targetPath); err != nil {
			sendFSError(c.id, reqID, "删除失败："+err.Error())
			return
		}
		sendFSResult(c.id, reqID, nil)

	default:
		sendFSError(c.id, reqID, "不支持的 SFTP 操作："+op)
	}
}

func removeSFTPRecursive(sc *sftp.Client, p string) error {
	st, err := sc.Lstat(p)
	if err != nil {
		return err
	}
	if !st.IsDir() {
		return sc.Remove(p)
	}
	items, err := sc.ReadDir(p)
	if err != nil {
		return err
	}
	for _, item := range items {
		if err := removeSFTPRecursive(sc, path.Join(p, item.Name())); err != nil {
			return err
		}
	}
	return sc.RemoveDirectory(p)
}

func minInt64(a, b int64) int64 {
	if a <= 0 {
		return b
	}
	if a < b {
		return a
	}
	return b
}
