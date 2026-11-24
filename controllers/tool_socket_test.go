package controllers_test

import (
	"bookstark/conf"
	"bookstark/models"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestToolSocketProxyAuthenticatesAndRelaysBinaryTCP(t *testing.T) {
	router, token := initAssetControllerTest(t)
	echo, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer echo.Close()
	go func() {
		for {
			conn, err := echo.Accept()
			if err != nil {
				return
			}
			go func() { defer conn.Close(); io.Copy(conn, conn) }()
		}
	}()
	for _, id := range []int64{910, 911} {
		if err := models.SaveInstalledTool(1, models.InstalledTool{ID: id, Revision: "tcp-v1", Title: "TCP", ToolMetadata: models.ToolMetadata{Permissions: models.ToolPermissions{Schema: 1, SocketTCP: id == 910}}}, "", ""); err != nil {
			t.Fatal(err)
		}
	}
	tool, _ := models.GetInstalledTool(1, 910)
	server := httptest.NewServer(router)
	defer server.Close()
	address := func(id int64, host, port string) string {
		current, _ := models.GetInstalledTool(1, id)
		params := url.Values{"revision": {current.Revision}, "instance": {current.Instance}, "host": {host}, "port": {port}}
		return "ws" + strings.TrimPrefix(server.URL, "http") + "/api/tool-installs/" + strconv.FormatInt(id, 10) + "/socket?" + params.Encode()
	}
	headers := http.Header{"Origin": {server.URL}, "Authorization": {"Token " + token}}
	attempt := func(address string, headers http.Header, status int) {
		t.Helper()
		connection, response, err := websocket.DefaultDialer.Dial(address, headers)
		if connection != nil {
			connection.Close()
		}
		if err == nil || response == nil || response.StatusCode != status {
			t.Fatalf("handshake: err=%v response=%v, want %d", err, response, status)
		}
		response.Body.Close()
	}
	target := address(910, "127.0.0.1", strconv.Itoa(echo.Addr().(*net.TCPAddr).Port))
	attempt(target, headers, 403) // Remote proxy defaults off, even with a declaration.
	conf.App.ToolLocalClient = true
	attempt(target, http.Header{"Origin": {"https://evil.example"}, "Authorization": {"Token " + token}}, 403)
	attempt(target, http.Header{"Origin": {server.URL}}, 401)
	attempt(address(911, "127.0.0.1", "22"), headers, 403)
	for _, invalid := range []string{"http://example.com", "example.com:22", "evil/host", "a..b"} {
		attempt(address(910, invalid, "22"), headers, 400)
	}
	attempt(address(910, "localhost", "0"), headers, 400)
	ws, response, err := websocket.DefaultDialer.Dial(target, headers)
	if err != nil {
		t.Fatal(err, response)
	}
	defer ws.Close()
	ws.SetReadDeadline(time.Now().Add(10 * time.Second))
	var hello map[string]bool
	if err := ws.ReadJSON(&hello); err != nil || !hello["connected"] {
		t.Fatal(hello, err)
	}
	message := []byte{0, 1, 2, 255, 'S', 'S', 'H', '\n'}
	if err := ws.WriteMessage(websocket.BinaryMessage, message); err != nil {
		t.Fatal(err)
	}
	got := []byte{}
	for len(got) < len(message) {
		kind, data, err := ws.ReadMessage()
		if err != nil || kind != websocket.BinaryMessage {
			t.Fatal(kind, err)
		}
		got = append(got, data...)
	}
	if string(got) != string(message) {
		t.Fatal("TCP bytes changed", got)
	}
	// Revoking the installed capability closes an existing connection too.
	tx, _ := models.DB.Begin()
	meta := tool.ToolMetadata
	meta.Permissions.SocketTCP = false
	if err := models.SaveToolMetadata(tx, 1, 910, meta); err != nil {
		t.Fatal(err)
	}
	tx.Commit()
	_, _, err = ws.ReadMessage()
	if !websocket.IsCloseError(err, 1008) {
		t.Fatal("revoked socket was not closed", err)
	}
}
