//go:build wails && !dev

package main

import (
	"encoding/json"
	"github.com/wailsapp/wails/v3/pkg/application"
	"strings"
	"testing"
	"time"
)

func TestNativeClientBridgeOriginBoundary(t *testing.T) {
	l := &launcher{dir: t.TempDir(), addr: "127.0.0.1:12345", token: "never-expose-native-access-token"}
	h := newNativeCapabilities()
	h.workspace = l
	w := &capabilityWindow{number: 1, replies: make(chan string, 4)}
	origin := "http://" + l.addr
	call := func(operation string, info *application.OriginInfo, token string) string {
		payload, _ := json.Marshal(map[string]any{"id": "client_test", "action": "client", "args": clientRequest{Operation: operation, Origin: origin, BridgeToken: token}})
		if !h.handleClient(w, "bookstark:request:"+string(payload), info) {
			t.Fatal("client action not handled")
		}
		select {
		case reply := <-w.replies:
			return reply
		case <-time.After(3 * time.Second):
			t.Fatal("missing client reply")
			return ""
		}
	}
	for _, info := range []*application.OriginInfo{nil, {Origin: "https://other.example"}, {Origin: origin, TopOrigin: "https://other.example"}} {
		if reply := call("info", info, ""); !strings.Contains(reply, "Untrusted workspace") {
			t.Fatal("untrusted native frame was accepted")
		}
	}
	info := &application.OriginInfo{Origin: origin, IsMainFrame: true}
	if reply := call("info", info, ""); !strings.HasPrefix(reply, "if(location.origin===") || strings.Contains(reply, l.token) {
		t.Fatal("client info leaked startup capability or omitted navigation check")
	}
	if reply := call("credentials-load", info, ""); !strings.Contains(reply, "Client settings request failed") {
		t.Fatal("missing main-document handshake accepted")
	}
}
