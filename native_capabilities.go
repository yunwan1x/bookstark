//go:build wails && !dev

package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

const nativeExportLimit = 100 * 1024 * 1024

var nativeRequestID = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,100}$`)

type nativeTransfer struct {
	file             *os.File
	path, name, kind string
	size             int64
	finished         bool
	window           uint
}
type nativeCapabilities struct {
	app          *application.App
	workspace    *launcher
	mu           sync.Mutex
	transfers    map[string]*nativeTransfer
	frameTokens  map[uint]string
	closeTokens  map[uint]string
	closeAllowed map[uint]bool
	printWindows map[uint]bool
}

func newNativeCapabilities() *nativeCapabilities {
	return &nativeCapabilities{transfers: map[string]*nativeTransfer{}, frameTokens: map[uint]string{}, closeTokens: map[uint]string{}, closeAllowed: map[uint]bool{}, printWindows: map[uint]bool{}}
}
func (h *nativeCapabilities) reply(window application.Window, id string, value any, err error) {
	payload, _ := json.Marshal([]any{id, value, nil})
	if err != nil {
		payload, _ = json.Marshal([]any{id, nil, err.Error()})
	}
	window.ExecJS("window.BookStarkHostReply && window.BookStarkHostReply.apply(null," + string(payload) + ")")
}
func (h *nativeCapabilities) handle(window application.Window, message string) {
	if token, ok := strings.CutPrefix(message, "bookstark:close-ready:"); ok {
		h.mu.Lock()
		allowed := h.closeTokens[window.ID()] == token && token != ""
		if allowed {
			delete(h.closeTokens, window.ID())
			h.closeAllowed[window.ID()] = true
		}
		h.mu.Unlock()
		if allowed {
			window.Close()
		}
		return
	}
	if message == "bookstark:print-ready" {
		h.mu.Lock()
		ok := h.printWindows[window.ID()]
		delete(h.printWindows, window.ID())
		h.mu.Unlock()
		if ok {
			if view, ok := window.(*application.WebviewWindow); ok {
				_ = view.Print()
			}
		}
		return
	}
	payload, ok := strings.CutPrefix(message, "bookstark:request:")
	if !ok || len(payload) > 300000 {
		return
	}
	var request struct {
		ID     string `json:"id"`
		Action string `json:"action"`
		Args   struct {
			Text  string `json:"text"`
			Name  string `json:"name"`
			Kind  string `json:"kind"`
			Token string `json:"token"`
			Data  string `json:"data"`
		} `json:"args"`
	}
	if json.Unmarshal([]byte(payload), &request) != nil || !nativeRequestID.MatchString(request.ID) {
		return
	}
	go func() {
		var value any
		var err error
		switch request.Action {
		case "capabilities":
			value = map[string]any{"version": 1}
		case "clipboard-write":
			if !h.app.Clipboard.SetText(request.Args.Text) {
				err = errors.New("Clipboard write failed")
			} else {
				value = true
			}
		case "save-begin":
			h.mu.Lock()
			if len(h.transfers) >= 3 {
				err = errors.New("Too many pending exports")
			} else {
				var file *os.File
				file, err = os.CreateTemp("", "bookstark-export-*")
				if err == nil {
					token := rand.Text()
					name := filepath.Base(strings.ReplaceAll(request.Args.Name, "\\", "/"))
					if name == "." || name == "" {
						name = "BookStark"
					}
					h.transfers[token] = &nativeTransfer{file: file, path: file.Name(), name: name, kind: request.Args.Kind, window: window.ID()}
					value = token
				}
			}
			h.mu.Unlock()
		case "save-chunk":
			h.mu.Lock()
			transfer := h.transfers[request.Args.Token]
			if transfer == nil || transfer.window != window.ID() || transfer.finished {
				err = errors.New("Export has expired")
			} else {
				var data []byte
				data, err = base64.StdEncoding.DecodeString(request.Args.Data)
				if err == nil && (len(data) > 196608 || transfer.size+int64(len(data)) > nativeExportLimit) {
					err = errors.New("Export exceeds 100 MB")
				}
				if err == nil {
					var n int
					n, err = transfer.file.Write(data)
					transfer.size += int64(n)
					value = true
				}
				if err != nil {
					transfer.file.Close()
					os.Remove(transfer.path)
					delete(h.transfers, request.Args.Token)
				}
			}
			h.mu.Unlock()
		case "save-cancel":
			h.mu.Lock()
			if transfer := h.transfers[request.Args.Token]; transfer != nil && transfer.window == window.ID() {
				transfer.file.Close()
				os.Remove(transfer.path)
				delete(h.transfers, request.Args.Token)
			}
			h.mu.Unlock()
			value = true
		case "save-finish":
			h.mu.Lock()
			transfer := h.transfers[request.Args.Token]
			if transfer == nil || transfer.window != window.ID() || transfer.finished {
				err = errors.New("Export has expired")
			} else {
				transfer.finished = true
				err = transfer.file.Close()
			}
			h.mu.Unlock()
			if transfer != nil && transfer.window == window.ID() && transfer.finished && err == nil {
				defer func() { h.mu.Lock(); delete(h.transfers, request.Args.Token); h.mu.Unlock(); os.Remove(transfer.path) }()
				if transfer.kind == "print" {
					err = h.print(transfer)
					value = err == nil
				} else {
					var path string
					path, err = h.app.Dialog.SaveFile().SetFilename(transfer.name).AttachToWindow(window).PromptForSingleSelection()
					if err == nil && path != "" {
						var input *os.File
						input, err = os.Open(transfer.path)
						if err == nil {
							var output *os.File
							output, err = os.Create(path)
							if err == nil {
								_, err = io.Copy(output, input)
								if e := output.Close(); err == nil {
									err = e
								}
							}
							input.Close()
						}
						value = err == nil
					} else {
						value = false
					}
				}
			}
		default:
			err = errors.New("Unsupported native action")
		}
		h.reply(window, request.ID, value, err)
	}()
}
func (h *nativeCapabilities) print(transfer *nativeTransfer) error {
	data, err := os.ReadFile(transfer.path)
	if err != nil {
		return err
	}
	nonce := rand.Text()
	// Only our ready notification may run; exported content cannot execute scripts.
	header := `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: http: https:; style-src 'unsafe-inline' http: https:; font-src data: http: https:; script-src 'nonce-` + nonce + `'"><script nonce="` + nonce + `">addEventListener('load',function(){Promise.resolve(document.fonts&&document.fonts.ready).then(function(){var b=window.chrome&&window.chrome.webview||window.webkit&&window.webkit.messageHandlers.external;if(b)b.postMessage('bookstark:print-ready')})})</script>`
	h.mu.Lock()
	view := h.app.Window.NewWithOptions(application.WebviewWindowOptions{Title: "BookStark · 打印 / Print", Width: 900, Height: 800, HTML: header + string(data)})
	h.printWindows[view.ID()] = true
	h.mu.Unlock()
	return nil
}
func (h *nativeCapabilities) guardClose(window *application.WebviewWindow) {
	h.mu.Lock()
	h.closeAllowed[window.ID()] = false
	h.mu.Unlock()
	window.RegisterHook(events.Common.WindowClosing, func(event *application.WindowEvent) {
		h.mu.Lock()
		if h.closeAllowed[window.ID()] {
			h.mu.Unlock()
			return
		}
		token := rand.Text()
		h.closeTokens[window.ID()] = token
		h.mu.Unlock()
		event.Cancel()
		encoded, _ := json.Marshal("bookstark:close-ready:" + token)
		window.ExecJS(fmt.Sprintf(`(async function(){try{if(typeof window.BookStarkBeforeLeave==='function' && !(await window.BookStarkBeforeLeave()))return;var b=window.chrome&&window.chrome.webview||window.webkit&&window.webkit.messageHandlers.external;if(b)b.postMessage(%s)}catch(e){console.error(e)}})()`, encoded))
	})
}
func (h *nativeCapabilities) close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for token, t := range h.transfers {
		t.file.Close()
		os.Remove(t.path)
		delete(h.transfers, token)
	}
}

func (h *nativeCapabilities) shouldQuit() bool {
	if h.app == nil {
		return true
	}
	allowed := true
	h.mu.Lock()
	for _, window := range h.app.Window.GetAll() {
		if ready, guarded := h.closeAllowed[window.ID()]; guarded && !ready {
			allowed = false
			go window.Close()
		}
	}
	h.mu.Unlock()
	return allowed
}
