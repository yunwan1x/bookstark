//go:build wails && !dev

package main

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func (h *nativeCapabilities) handleClient(window application.Window, message string, origin *application.OriginInfo) bool {
	payload, ok := strings.CutPrefix(message, "bookstark:request:")
	if !ok || !strings.Contains(payload, `"client"`) {
		return false
	}
	var request struct {
		ID     string        `json:"id"`
		Action string        `json:"action"`
		Args   clientRequest `json:"args"`
	}
	if len(payload) > 8192 || json.Unmarshal([]byte(payload), &request) != nil || request.Action != "client" || !nativeRequestID.MatchString(request.ID) {
		return false
	}
	if origin == nil || h.workspace == nil || webOrigin(origin.Origin) != request.Args.Origin || (origin.TopOrigin != "" && webOrigin(origin.TopOrigin) != request.Args.Origin) {
		h.reply(window, request.ID, nil, errors.New("Untrusted workspace"))
		return true
	}
	go func() {
		value, err := h.workspace.clientAction(request.Args)
		if err == nil && request.Args.Operation == "tools-open" {
			window.SetURL(h.workspace.startURL() + "?tools=1")
			return
		}
		if err == nil && request.Args.Operation == "switch" {
			window.SetURL(h.workspace.startURL() + "?choose=1")
			return
		}
		reply, _ := json.Marshal([]any{request.ID, value, nil})
		if err != nil {
			reply, _ = json.Marshal([]any{request.ID, nil, "Client settings request failed"})
		}
		expected, _ := json.Marshal(request.Args.Origin)
		window.ExecJS("if(location.origin===" + string(expected) + "){window.BookStarkHostReply&&window.BookStarkHostReply.apply(null," + string(reply) + ")}")
	}()
	return true
}
