package controllers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"bookstark/conf"
	"bookstark/middleware"
	"bookstark/models"
)

func TestAssistantEndToEndProviders(t *testing.T) {
	for _, provider := range []string{"openai", "anthropic"} {
		t.Run(provider, func(t *testing.T) {
			router, token := initAssetControllerTest(t)
			admin, err := models.GetMemberByAccount(conf.App.AdminAccount)
			if err != nil {
				t.Fatal(err)
			}
			own := &models.Blog{MemberID: admin.MemberID, BlogTitle: "learning", BlogContent: "OWNED_BODY", BlogIdentify: "owned-ai", BlogType: "note"}
			if err = own.Insert(); err != nil {
				t.Fatal(err)
			}
			other := &models.Blog{MemberID: admin.MemberID + 1, BlogTitle: "learning", BlogContent: "OTHER_ACCOUNT_SECRET", BlogIdentify: "other-ai", BlogType: "note", Visibility: 1}
			if err = other.Insert(); err != nil {
				t.Fatal(err)
			}
			phase := 0
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				b, _ := io.ReadAll(r.Body)
				defer r.Body.Close()
				raw := string(b)
				if strings.Contains(raw, "OTHER_ACCOUNT_SECRET") {
					t.Error("other account content leaked")
				}
				if strings.Contains(raw, "test-api-key") {
					t.Error("API key in model context")
				}
				if provider == "anthropic" {
					if r.URL.Path != "/v1/messages" || r.Header.Get("x-api-key") != "test-api-key" || !strings.Contains(raw, `"input_schema"`) {
						t.Error("bad Anthropic request")
					}
				} else {
					if r.URL.Path != "/chat/completions" || r.Header.Get("Authorization") != "Bearer test-api-key" {
						t.Error("bad OpenAI request")
					}
				}
				var request map[string]any
				if json.Unmarshal(b, &request) != nil {
					t.Error("invalid provider body")
				}
				calls := []map[string]any{}
				add := func(id, name string, args any) {
					if provider == "anthropic" {
						calls = append(calls, map[string]any{"type": "tool_use", "id": id, "name": name, "input": args})
					} else {
						a, _ := json.Marshal(args)
						calls = append(calls, map[string]any{"type": "function", "id": id, "function": map[string]any{"name": name, "arguments": string(a)}})
					}
				}
				switch phase {
				case 0:
					add("search-1", "search", map[string]any{"kind": "note", "query": "learning"})
				case 1:
					if !strings.Contains(raw, "OWNED_BODY") {
						t.Error("missing search results")
					}
					add("read-1", "read", map[string]any{"kind": "note", "id": own.BlogID})
					add("draft-1", "draft_note", map[string]any{"title": "Summary", "content": "A draft summary"})
					add("forbidden-1", "confirm", map[string]any{"member_id": 999})
				case 2:
					if !strings.Contains(raw, "pending_user_confirmation") || !strings.Contains(raw, "Invalid tool") {
						t.Error("missing draft/denied tool receipts")
					}
				}
				phase++
				w.Header().Set("Content-Type", "application/json")
				if provider == "anthropic" {
					stop := "tool_use"
					if len(calls) == 0 {
						stop = "end_turn"
						calls = append(calls, map[string]any{"type": "text", "text": "Review the draft before confirming."})
					}
					_ = json.NewEncoder(w).Encode(map[string]any{"stop_reason": stop, "content": calls})
				} else {
					finish := "tool_calls"
					m := map[string]any{"role": "assistant", "content": "", "tool_calls": calls}
					if len(calls) == 0 {
						finish = "stop"
						m = map[string]any{"role": "assistant", "content": "Review the draft before confirming."}
					}
					_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": m, "finish_reason": finish}}})
				}
			}))
			defer upstream.Close()
			if err = models.BatchUpdateSettings(map[string]string{"ai_enabled": "1", "ai_provider": provider, "ai_base_url": upstream.URL, "ai_api_key": "test-api-key", "ai_model": "test-tools"}); err != nil {
				t.Fatal(err)
			}
			w := adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
			var state struct {
				Session models.AssistantSession `json:"session"`
			}
			if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &state) != nil {
				t.Fatal(w.Body.String())
			}
			if !strings.Contains(w.Header().Get("Cache-Control"), "no-store") {
				t.Fatal("session is cacheable")
			}
			w = adminAssetRequest(router, token, "POST", "/api/ai/assistant/chat", map[string]any{"session_id": state.Session.ID, "message": "Summarize learning notes and draft a new note"})
			if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &state) != nil {
				t.Fatalf("chat: %d %s", w.Code, w.Body.String())
			}
			if phase != 3 || len(state.Session.Messages) != 2 || len(state.Session.Drafts) != 1 || len(state.Session.Messages[1].Sources) != 1 {
				t.Fatalf("wrong chat results: %+v", state)
			}
			var count int
			if err = models.DB.QueryRow(`SELECT count(*) FROM md_blogs`).Scan(&count); err != nil || count != 2 {
				t.Fatal("draft unexpectedly created resource", err, count)
			}
			draft := state.Session.Drafts[0]
			// Arbitrary payload/member overrides cannot be smuggled into confirmation.
			w = adminAssetRequest(router, token, "POST", "/api/ai/assistant/drafts/"+draft.ID, map[string]any{"session_id": state.Session.ID, "action": "confirm", "member_id": 999})
			if w.Code != 400 {
				t.Fatal("unknown confirmation field accepted", w.Body.String())
			}
			for i := 0; i < 2; i++ {
				w = adminAssetRequest(router, token, "POST", "/api/ai/assistant/drafts/"+draft.ID, map[string]any{"session_id": state.Session.ID, "action": "confirm"})
				if w.Code != 200 {
					t.Fatal(w.Body.String())
				}
			}
			if err = models.DB.QueryRow(`SELECT count(*) FROM md_blogs WHERE blog_title='Summary' AND member_id=? AND visibility=0`, admin.MemberID).Scan(&count); err != nil || count != 1 {
				t.Fatal("duplicate or non-private create", err, count)
			}
			// Real authenticated cookie requests must still pass CSRF.
			jwt, err := middleware.GenerateToken(admin.MemberID, admin.Account, admin.Role)
			if err != nil {
				t.Fatal(err)
			}
			r := httptest.NewRequest("POST", "/api/ai/assistant/reset", bytes.NewBufferString(fmt.Sprintf(`{"session_id":%q}`, state.Session.ID)))
			r.Header.Set("Content-Type", "application/json")
			r.AddCookie(&http.Cookie{Name: "token", Value: jwt})
			csrf := httptest.NewRecorder()
			router.ServeHTTP(csrf, r)
			if csrf.Code != 403 {
				t.Fatalf("CSRF status=%d %s", csrf.Code, csrf.Body.String())
			}
			w = adminAssetRequest(router, token, "POST", "/api/ai/assistant/reset", map[string]any{"session_id": state.Session.ID})
			if w.Code != 200 {
				t.Fatal(w.Body.String())
			}
			if err = models.DB.QueryRow(`SELECT count(*) FROM md_blogs WHERE blog_title='Summary'`).Scan(&count); err != nil || count != 1 {
				t.Fatal("reset deleted resource")
			}
		})
	}
}

func TestAssistantUpstreamFailureAndAuthentication(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, "", "GET", "/api/ai/assistant", nil)
	if w.Code != 401 {
		t.Fatal("unauthenticated", w.Code)
	}
	w = adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
	if w.Code != 403 {
		t.Fatal("disabled", w.Code)
	}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(401)
		_, _ = w.Write([]byte("provider secret diagnostic"))
	}))
	defer upstream.Close()
	if err := models.BatchUpdateSettings(map[string]string{"ai_enabled": "1", "ai_base_url": upstream.URL, "ai_api_key": "test-key", "ai_model": "test"}); err != nil {
		t.Fatal(err)
	}
	w = adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
	var data struct {
		Session models.AssistantSession `json:"session"`
	}
	if json.Unmarshal(w.Body.Bytes(), &data) != nil {
		t.Fatal(w.Body.String())
	}
	for i := 0; i < 2; i++ {
		w = adminAssetRequest(router, token, "POST", "/api/ai/assistant/chat", map[string]any{"session_id": data.Session.ID, "message": "hello"})
		if w.Code != 502 || strings.Contains(w.Body.String(), "secret diagnostic") {
			t.Fatal("unsafe upstream failure", w.Code, w.Body.String())
		}
	}
	w = adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
	if json.Unmarshal(w.Body.Bytes(), &data) != nil || data.Session.Busy || len(data.Session.Messages) != 0 || len(data.Session.Drafts) != 0 {
		t.Fatal("failed request changed state", w.Body.String())
	}
}

func TestAssistantRejectsMalformedProviderAndCancels(t *testing.T) {
	router, token := initAssetControllerTest(t)
	mode, calls := "invalid", 0
	entered := make(chan struct{}, 1)
	release := make(chan struct{})
	defer close(release)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.Copy(io.Discard, r.Body)
		calls++
		w.Header().Set("Content-Type", "application/json")
		switch mode {
		case "invalid":
			_, _ = w.Write([]byte("not JSON"))
		case "truncated":
			_, _ = w.Write([]byte(`{"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"partial"}}]}`))
		case "oversized":
			_, _ = w.Write([]byte(strings.Repeat("x", 270000)))
		case "loop":
			_, _ = w.Write([]byte(`{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","tool_calls":[{"id":"loop","type":"function","function":{"name":"delete_all","arguments":"{}"}}]}}]}`))
		case "cancel":
			entered <- struct{}{}
			select {
			case <-r.Context().Done():
			case <-release:
			}
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
	for _, testMode := range []string{"invalid", "truncated", "oversized", "loop"} {
		mode, calls = testMode, 0
		w = adminAssetRequest(router, token, "POST", "/api/ai/assistant/chat", map[string]any{"session_id": state.Session.ID, "message": "hello"})
		expected := 502
		if mode == "loop" {
			expected = 422
			if calls != 7 {
				t.Fatal("tool loop not bounded", calls)
			}
		}
		if w.Code != expected {
			t.Fatal(mode, w.Code, w.Body.String())
		}
	}
	mode = "cancel"
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	body, _ := json.Marshal(map[string]any{"session_id": state.Session.ID, "message": "hello"})
	req := httptest.NewRequest("POST", "/api/ai/assistant/chat", bytes.NewReader(body)).WithContext(ctx)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Token "+token)
	finished := make(chan struct{})
	go func() { router.ServeHTTP(httptest.NewRecorder(), req); close(finished) }()
	select {
	case <-entered:
	case <-time.After(5 * time.Second):
		t.Fatal("provider never entered")
	}
	cancel()
	select {
	case <-finished:
	case <-time.After(5 * time.Second):
		t.Fatal("cancellation did not stop request")
	}
	w = adminAssetRequest(router, token, "GET", "/api/ai/assistant", nil)
	if json.Unmarshal(w.Body.Bytes(), &state) != nil || state.Session.Busy || len(state.Session.Messages) != 0 || len(state.Session.Drafts) != 0 {
		t.Fatal("cancelled/failed request left state", w.Body.String())
	}
}
