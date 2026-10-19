package controllers_test

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"bookstark/models"
)

func TestAssistantStreamDisconnectCancelsUpstream(t *testing.T) {
	router, token := initAssetControllerTest(t)
	cancelled, finished := make(chan struct{}), make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.Copy(io.Discard, r.Body)
		w.Header().Set("Content-Type", "text/event-stream")
		assistantTestSSE(w, "message", map[string]any{"choices": []any{map[string]any{"index": 0, "delta": map[string]any{"content": "partial"}}}})
		select {
		case <-r.Context().Done():
			close(cancelled)
		case <-time.After(15 * time.Second):
		}
	}))
	defer upstream.Close()
	if err := models.BatchUpdateSettings(map[string]string{"ai_enabled": "1", "ai_provider": "openai", "ai_base_url": upstream.URL, "ai_api_key": "test", "ai_model": "test"}); err != nil {
		t.Fatal(err)
	}
	w := adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
	var state struct {
		Session models.AssistantSession `json:"session"`
	}
	if json.Unmarshal(w.Body.Bytes(), &state) != nil {
		t.Fatal(w.Body.String())
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { router.ServeHTTP(w, r); close(finished) }))
	defer server.Close()
	body, _ := json.Marshal(map[string]string{"session_id": state.Session.ID, "message": "hello"})
	req, _ := http.NewRequest("POST", server.URL+"/api/ai/assistant/chat", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("Authorization", "Token "+token)
	response, err := (&http.Client{Timeout: 12 * time.Second}).Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	r := bufio.NewReader(response.Body)
	for {
		event, _ := assistantReadEvent(t, r)
		if event == "delta" {
			break
		}
		if event == "error" {
			t.Fatal("unexpected stream error")
		}
	}
	// Provider deliberately stalls. Heartbeats must reach the browser even when
	// the model is not producing tokens, then closing the body must cancel it.
	for {
		event, _ := assistantReadEvent(t, r)
		if event == "ping" {
			break
		}
	}
	_ = response.Body.Close()
	select {
	case <-cancelled:
	case <-time.After(3 * time.Second):
		t.Fatal("upstream was not cancelled")
	}
	select {
	case <-finished:
	case <-time.After(3 * time.Second):
		t.Fatal("handler/heartbeat did not exit")
	}
	w = adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
	if json.Unmarshal(w.Body.Bytes(), &state) != nil || state.Session.Busy || len(state.Session.Messages) > 0 || len(state.Session.Drafts) > 0 {
		t.Fatal("cancelled stream persisted state or lease", w.Body.String())
	}
}

func assistantTestSSE(w http.ResponseWriter, event string, payload any) {
	data, _ := json.Marshal(payload)
	frame := fmt.Sprintf("event: %s\r\ndata: %s\r\n\r\n", event, data)
	// Deliberately split JSON and UTF-8 across writes.
	for len(frame) > 0 {
		n := min(3, len(frame))
		_, _ = io.WriteString(w, frame[:n])
		frame = frame[n:]
	}
	w.(http.Flusher).Flush()
}
func assistantReadEvent(t *testing.T, r *bufio.Reader) (string, map[string]any) {
	t.Helper()
	var event string
	var data []string
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			t.Fatal("stream ended before terminal event", err)
		}
		line = strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
		if line == "" && len(data) > 0 {
			var body map[string]any
			if err = json.Unmarshal([]byte(strings.Join(data, "\n")), &body); err != nil {
				t.Fatal(err)
			}
			return event, body
		}
		if strings.HasPrefix(line, "event:") {
			event = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
		}
		if strings.HasPrefix(line, "data:") {
			data = append(data, strings.TrimSpace(strings.TrimPrefix(line, "data:")))
		}
	}
}

func TestAssistantStreamingProviders(t *testing.T) {
	for _, provider := range []string{"openai", "anthropic"} {
		for _, broken := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/broken=%v", provider, broken), func(t *testing.T) {
				router, token := initAssetControllerTest(t)
				argsReady, argsResume, textResume := make(chan struct{}), make(chan struct{}), make(chan struct{})
				var phase atomic.Int32
				upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					var req map[string]any
					if json.NewDecoder(r.Body).Decode(&req) != nil || req["stream"] != true {
						t.Error("not a streaming upstream request")
					}
					w.Header().Set("Content-Type", "text/event-stream")
					call := phase.Add(1)
					send := func(event string, p any) { assistantTestSSE(w, event, p) }
					wait := func(ch <-chan struct{}) bool {
						select {
						case <-ch:
							return true
						case <-r.Context().Done():
							return false
						case <-time.After(5 * time.Second):
							t.Error("test gate timed out")
							return false
						}
					}
					if provider == "openai" {
						chunk := func(delta any, finish any) {
							send("message", map[string]any{"choices": []any{map[string]any{"index": 0, "delta": delta, "finish_reason": finish}}})
						}
						if call == 1 {
							chunk(map[string]any{"tool_calls": []any{map[string]any{"index": 0, "id": "draft", "type": "function", "function": map[string]any{"name": "draft_note", "arguments": "{\"title\":\"流式笔记\","}}}}, nil)
							close(argsReady)
							if !wait(argsResume) {
								return
							}
							chunk(map[string]any{"tool_calls": []any{map[string]any{"index": 0, "function": map[string]any{"arguments": "\"content\":\"正文\"}"}}}}, nil)
							chunk(map[string]any{}, "tool_calls")
						} else {
							chunk(map[string]any{"reasoning_content": "INTERNAL_THINKING", "content": "你好"}, nil)
							if !wait(textResume) || broken {
								return
							}
							chunk(map[string]any{"content": "，请确认草稿。"}, nil)
							chunk(map[string]any{}, "stop")
						}
						_, _ = io.WriteString(w, "data: [DONE]\n\n")
						w.(http.Flusher).Flush()
					} else {
						send("message_start", map[string]any{"type": "message_start", "message": map[string]any{}})
						if call == 1 {
							send("content_block_start", map[string]any{"type": "content_block_start", "index": 0, "content_block": map[string]any{"type": "tool_use", "id": "draft", "name": "draft_note", "input": map[string]any{}}})
							send("content_block_delta", map[string]any{"type": "content_block_delta", "index": 0, "delta": map[string]any{"type": "input_json_delta", "partial_json": "{\"title\":\"流式笔记\","}})
							close(argsReady)
							if !wait(argsResume) {
								return
							}
							send("content_block_delta", map[string]any{"type": "content_block_delta", "index": 0, "delta": map[string]any{"type": "input_json_delta", "partial_json": "\"content\":\"正文\"}"}})
						} else {
							send("content_block_start", map[string]any{"type": "content_block_start", "index": 0, "content_block": map[string]any{"type": "text", "text": ""}})
							send("content_block_delta", map[string]any{"type": "content_block_delta", "index": 0, "delta": map[string]any{"type": "text_delta", "text": "你好"}})
							if !wait(textResume) || broken {
								return
							}
							send("content_block_delta", map[string]any{"type": "content_block_delta", "index": 0, "delta": map[string]any{"type": "text_delta", "text": "，请确认草稿。"}})
						}
						send("content_block_stop", map[string]any{"type": "content_block_stop", "index": 0})
						reason := "end_turn"
						if call == 1 {
							reason = "tool_use"
						}
						send("message_delta", map[string]any{"type": "message_delta", "delta": map[string]any{"stop_reason": reason}})
						send("message_stop", map[string]any{"type": "message_stop"})
					}
				}))
				defer upstream.Close()
				if err := models.BatchUpdateSettings(map[string]string{"ai_enabled": "1", "ai_provider": provider, "ai_base_url": upstream.URL, "ai_api_key": "test", "ai_model": "test"}); err != nil {
					t.Fatal(err)
				}
				w := adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
				var initial struct {
					Session models.AssistantSession `json:"session"`
				}
				if json.Unmarshal(w.Body.Bytes(), &initial) != nil {
					t.Fatal(w.Body.String())
				}
				server := httptest.NewServer(router)
				defer server.Close()
				body, _ := json.Marshal(map[string]string{"session_id": initial.Session.ID, "message": "创建笔记"})
				req, _ := http.NewRequest("POST", server.URL+"/api/ai/assistant/chat", bytes.NewReader(body))
				req.Header.Set("Content-Type", "application/json")
				req.Header.Set("Accept", "text/event-stream")
				req.Header.Set("Authorization", "Token "+token)
				client := &http.Client{Timeout: 10 * time.Second}
				response, err := client.Do(req)
				if err != nil {
					t.Fatal(err)
				}
				defer response.Body.Close()
				if response.Header.Get("X-Accel-Buffering") != "no" || !strings.Contains(response.Header.Get("Content-Type"), "text/event-stream") {
					t.Fatal("stream headers missing")
				}
				r := bufio.NewReader(response.Body)
				event, _ := assistantReadEvent(t, r)
				if event != "round" {
					t.Fatal("missing immediate progress", event)
				}
				select {
				case <-argsReady:
				case <-time.After(5 * time.Second):
					t.Fatal("partial args not sent")
				}
				var count int
				if err = models.DB.QueryRow(`SELECT count(*) FROM md_assistant_drafts`).Scan(&count); err != nil || count != 0 {
					t.Fatal("partial arguments executed", count, err)
				}
				close(argsResume)
				for {
					event, payload := assistantReadEvent(t, r)
					if event == "error" || event == "done" {
						t.Fatal("completed before partial text", event)
					}
					if event == "delta" {
						if payload["text"] != "你好" {
							t.Fatal("wrong delta", payload)
						}
						break
					}
				}
				// We have received answer text while the provider is still waiting.
				close(textResume)
				for {
					event, payload := assistantReadEvent(t, r)
					if event == "error" {
						if !broken {
							t.Fatal(payload)
						}
						break
					}
					if event == "done" {
						if broken {
							t.Fatal("truncated stream committed")
						}
						encoded, _ := json.Marshal(payload)
						if strings.Contains(string(encoded), "INTERNAL_THINKING") {
							t.Fatal("reasoning leaked")
						}
						if payload["session_id"] != initial.Session.ID {
							t.Fatal("invalid completion receipt", payload)
						}
						snapshot := adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
						var final struct {
							Session models.AssistantSession `json:"session"`
						}
						_ = json.Unmarshal(snapshot.Body.Bytes(), &final)
						if len(final.Session.Drafts) != 1 || len(final.Session.Messages) != 0 || !strings.Contains(string(encoded), "你好，请确认草稿。") {
							t.Fatal(string(encoded))
						}
						break
					}
				}
				if err = models.DB.QueryRow(`SELECT count(*) FROM md_blogs`).Scan(&count); err != nil || count != 0 {
					t.Fatal("stream created resources without confirmation")
				}
				if err = models.DB.QueryRow(`SELECT count(*) FROM md_assistant_drafts`).Scan(&count); err != nil {
					t.Fatal(err)
				}
				expected := 1
				if broken {
					expected = 0
				}
				if count != expected {
					t.Fatal("unexpected persisted drafts", count)
				}
			})
		}
	}
}
