package controllers

import (
	"bookstark/conf"
	"bookstark/models"
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/netip"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var toolSocketDomain = regexp.MustCompile(`^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$`)
var toolSocketSlots = struct {
	sync.Mutex
	total   int
	members map[int64]int
	tools   map[string]int
}{members: map[int64]int{}, tools: map[string]int{}}

func reserveToolSocket(member, id int64) (func(), bool) {
	key := strconv.FormatInt(member, 10) + ":" + strconv.FormatInt(id, 10)
	toolSocketSlots.Lock()
	defer toolSocketSlots.Unlock()
	if toolSocketSlots.total >= 128 || toolSocketSlots.members[member] >= 16 || toolSocketSlots.tools[key] >= 8 {
		return nil, false
	}
	toolSocketSlots.total++
	toolSocketSlots.members[member]++
	toolSocketSlots.tools[key]++
	return func() {
		toolSocketSlots.Lock()
		defer toolSocketSlots.Unlock()
		toolSocketSlots.total--
		toolSocketSlots.members[member]--
		toolSocketSlots.tools[key]--
		if toolSocketSlots.members[member] == 0 {
			delete(toolSocketSlots.members, member)
		}
		if toolSocketSlots.tools[key] == 0 {
			delete(toolSocketSlots.tools, key)
		}
	}, true
}
func toolSocketEnabled() bool {
	return conf.App.ToolLocalClient || models.GetSettingWithDefault("tool_socket_proxy", "0") == "1"
}
func validToolSocketHost(host string) bool {
	if len(host) == 0 || len(host) > 253 {
		return false
	}
	if _, err := netip.ParseAddr(host); err == nil {
		return true
	}
	return toolSocketDomain.MatchString(host) && !strings.Contains(host, "..")
}
func ToolInstallSocket(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	c.Header("Cache-Control", "private, no-store")
	// WebSocket handshakes cannot carry a CSRF header. Require the host page's
	// exact browser Origin instead; an iframe never receives an authenticated URL.
	if c.GetHeader("Origin") != toolParentOrigin(c) {
		c.JSON(403, gin.H{"error": "invalid_origin"})
		return
	}
	tool, err := models.GetInstalledTool(member, id)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	if tool.Revision != c.Query("revision") || tool.Instance != c.Query("instance") {
		toolAPIError(c, models.ErrToolConflict)
		return
	}
	if !tool.Permissions.SocketTCP {
		toolAPIError(c, models.ErrToolPermission)
		return
	}
	if !toolSocketEnabled() {
		c.JSON(403, gin.H{"error": "socket_proxy_disabled"})
		return
	}
	host := c.Query("host")
	port, err := strconv.Atoi(c.Query("port"))
	if err != nil || port < 1 || port > 65535 || !validToolSocketHost(host) {
		c.JSON(400, gin.H{"error": "invalid_socket_target"})
		return
	}
	release, ok := reserveToolSocket(member, id)
	if !ok {
		c.JSON(429, gin.H{"error": "socket_limit"})
		return
	}
	defer release()

	upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return r.Header.Get("Origin") == toolParentOrigin(c) }, ReadBufferSize: 32 << 10, WriteBufferSize: 32 << 10}
	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	defer ws.Close()
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	tcp, err := (&net.Dialer{}).DialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	cancel()
	if err != nil {
		_ = ws.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1011, "connect_failed"), time.Now().Add(time.Second))
		return
	}
	defer tcp.Close()
	ws.SetReadLimit(64 << 10)
	_ = ws.SetReadDeadline(time.Now().Add(45 * time.Second))
	ws.SetPongHandler(func(string) error { return ws.SetReadDeadline(time.Now().Add(45 * time.Second)) })
	var writer sync.Mutex
	send := func(kind int, data []byte) error {
		writer.Lock()
		defer writer.Unlock()
		_ = ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
		return ws.WriteMessage(kind, data)
	}
	if err := send(websocket.TextMessage, []byte(`{"connected":true}`)); err != nil {
		return
	}
	done := make(chan struct{})
	var workers sync.WaitGroup
	defer func() { close(done); tcp.Close(); ws.Close(); workers.Wait() }()
	workers.Add(2)
	// TCP is a byte stream: WebSocket frame boundaries carry no application meaning.
	go func() {
		defer workers.Done()
		defer ws.Close()
		buffer := make([]byte, 32<<10)
		for {
			n, readErr := tcp.Read(buffer)
			if n > 0 {
				if err := send(websocket.BinaryMessage, buffer[:n]); err != nil {
					return
				}
			}
			if readErr != nil {
				if errors.Is(readErr, io.EOF) {
					_ = ws.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1000, "eof"), time.Now().Add(time.Second))
				}
				return
			}
		}
	}()
	go func() {
		defer workers.Done()
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		ticks := 0
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
				current, err := models.GetInstalledTool(member, id)
				if err != nil || current.Revision != tool.Revision || current.Instance != tool.Instance || !current.Permissions.SocketTCP || !toolSocketEnabled() {
					_ = ws.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1008, "permission_revoked"), time.Now().Add(time.Second))
					ws.Close()
					tcp.Close()
					return
				}
				ticks++
				if ticks%4 == 0 {
					if ws.WriteControl(websocket.PingMessage, nil, time.Now().Add(time.Second)) != nil {
						ws.Close()
						tcp.Close()
						return
					}
				}
			}
		}
	}()
	for {
		kind, data, readErr := ws.ReadMessage()
		if readErr != nil {
			return
		}
		if kind != websocket.BinaryMessage {
			_ = ws.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(1003, "binary_required"), time.Now().Add(time.Second))
			return
		}
		_ = tcp.SetWriteDeadline(time.Now().Add(10 * time.Second))
		for len(data) > 0 {
			n, writeErr := tcp.Write(data)
			if writeErr != nil || n == 0 {
				return
			}
			data = data[n:]
		}
	}
}
