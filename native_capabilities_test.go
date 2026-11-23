//go:build wails && !dev

package main

import (
	"encoding/base64"
	"encoding/json"
	"github.com/wailsapp/wails/v3/pkg/application"
	"os"
	"strings"
	"testing"
	"time"
)

type capabilityWindow struct {
	application.Window
	number  uint
	replies chan string
}

func (w *capabilityWindow) ID() uint             { return w.number }
func (w *capabilityWindow) ExecJS(script string) { w.replies <- script }
func capabilityCall(t *testing.T, h *nativeCapabilities, w *capabilityWindow, action string, args any) (any, any) {
	t.Helper()
	payload, _ := json.Marshal(map[string]any{"id": "test_id", "action": action, "args": args})
	h.handle(w, "bookstark:request:"+string(payload))
	select {
	case script := <-w.replies:
		var values []any
		jsonText := strings.TrimSuffix(strings.SplitN(script, ".apply(null,", 2)[1], ")")
		if err := json.Unmarshal([]byte(jsonText), &values); err != nil {
			t.Fatal(err)
		}
		return values[1], values[2]
	case <-time.After(3 * time.Second):
		t.Fatal("native request did not acknowledge")
		return nil, nil
	}
}
func TestNativeExportOwnershipAndLimits(t *testing.T) {
	h := newNativeCapabilities()
	defer h.close()
	owner := &capabilityWindow{number: 1, replies: make(chan string, 5)}
	other := &capabilityWindow{number: 2, replies: make(chan string, 5)}
	result, err := capabilityCall(t, h, owner, "save-begin", map[string]any{"name": "../../draft.json"})
	if err != nil {
		t.Fatal(err)
	}
	token := result.(string)
	transfer := h.transfers[token]
	path := transfer.path
	_, err = capabilityCall(t, h, other, "save-chunk", map[string]any{"token": token, "data": base64.StdEncoding.EncodeToString([]byte("stolen"))})
	if err == nil {
		t.Fatal("another window appended export")
	}
	capabilityCall(t, h, other, "save-cancel", map[string]any{"token": token})
	if h.transfers[token] == nil {
		t.Fatal("another window cancelled export")
	}
	_, err = capabilityCall(t, h, owner, "save-chunk", map[string]any{"token": token, "data": base64.StdEncoding.EncodeToString([]byte("draft"))})
	if err != nil {
		t.Fatal(err)
	}
	bytes, _ := os.ReadFile(path)
	if string(bytes) != "draft" {
		t.Fatalf("wrong bytes %q", bytes)
	}
	transfer.size = nativeExportLimit
	_, err = capabilityCall(t, h, owner, "save-chunk", map[string]any{"token": token, "data": "YQ=="})
	if err == nil {
		t.Fatal("accepted export larger than limit")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("failed export temp file was not removed")
	}
	_, err = capabilityCall(t, h, owner, "shell-execute", map[string]any{})
	if err == nil {
		t.Fatal("unknown native command accepted")
	}
}
