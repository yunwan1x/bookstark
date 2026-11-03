package controllers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"github.com/gin-gonic/gin"
	"io"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func speechRequest(s *ttsService, ctx context.Context, body string, id int64) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Set("memberID", id)
	c.Request = httptest.NewRequest("POST", "/api/ai/tts/stream", strings.NewReader(body)).WithContext(ctx)
	c.Request.Header.Set("Content-Type", "application/json")
	s.serve(c)
	return w
}
func speechService(p ttsProvider) *ttsService {
	return &ttsService{synthesize: p, users: map[int64]int{}, timeout: time.Second}
}
func TestTTSValidationAndFrames(t *testing.T) {
	calls := 0
	s := speechService(func(ctx context.Context, text, voice string, w io.Writer) error {
		calls++
		if voice != "zh-CN-YunxiNeural" {
			t.Error(voice)
		}
		_, e := w.Write(bytes.Repeat([]byte{1, 2}, 20000))
		return e
	})
	for _, tc := range []struct {
		body   string
		id     int64
		status int
	}{
		{`{"text":"你好"}`, 0, 401}, {`{`, 1, 400}, {`{"text":" "}`, 1, 400}, {`{"text":"hi","voice":"untrusted"}`, 1, 400},
		{`{"text":"` + strings.Repeat("好", 801) + `"}`, 1, 400}, {`{"text":"` + strings.Repeat("x", 17000) + `"}`, 1, 400},
	} {
		w := speechRequest(s, context.Background(), tc.body, tc.id)
		if w.Code != tc.status {
			t.Fatalf("status %d !=%d", w.Code, tc.status)
		}
	}
	if calls != 0 {
		t.Fatal("invalid input reached provider")
	}
	w := speechRequest(s, context.Background(), `{"text":"你好"}`, 1)
	if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal(w.Code, w.Header())
	}
	dec := json.NewDecoder(w.Body)
	frames := 0
	for dec.More() {
		var f struct {
			Event string
			Bytes int
		}
		if err := dec.Decode(&f); err != nil {
			t.Fatal(err)
		}
		frames++
		if f.Event == "done" && f.Bytes != 40000 {
			t.Fatal(f)
		}
	}
	if frames != 4 || s.active != 0 || len(s.users) != 0 {
		t.Fatal(frames, s.active, s.users)
	}
}
func TestTTSFailureCancellationAndLimits(t *testing.T) {
	for _, partial := range []bool{false, true} {
		s := speechService(func(ctx context.Context, text, voice string, w io.Writer) error {
			if partial {
				_, _ = w.Write([]byte("audio"))
			}
			return errors.New("secret upstream information")
		})
		w := speechRequest(s, context.Background(), `{"text":"hello"}`, 1)
		if strings.Contains(w.Body.String(), "secret") || strings.Contains(w.Body.String(), `"done"`) {
			t.Fatal(w.Body.String())
		}
		if partial && !strings.Contains(w.Body.String(), `"error"`) {
			t.Fatal(w.Body.String())
		}
		if !partial && w.Code != 502 {
			t.Fatal(w.Code)
		}
	}
	s := speechService(func(ctx context.Context, text, voice string, w io.Writer) error { <-ctx.Done(); return ctx.Err() })
	s.timeout = 10 * time.Millisecond
	w := speechRequest(s, context.Background(), `{"text":"hello"}`, 1)
	if w.Code != 502 || s.active != 0 {
		t.Fatal(w.Code, s.active)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	w = speechRequest(s, ctx, `{"text":"hi"}`, 1)
	if strings.Contains(w.Body.String(), `"done"`) || s.active != 0 {
		t.Fatal(w.Body.String())
	}
	if !s.acquire(1) || !s.acquire(1) || s.acquire(1) {
		t.Fatal("per-user bound")
	}
	for id := int64(2); id <= 7; id++ {
		if !s.acquire(id) {
			t.Fatal(id)
		}
	}
	if s.acquire(8) {
		t.Fatal("global bound")
	}
	w = speechRequest(s, context.Background(), `{"text":"hi"}`, 1)
	if w.Code != 429 {
		t.Fatal(w.Code)
	}
	s = speechService(func(ctx context.Context, text, voice string, w io.Writer) error {
		_, e := w.Write(make([]byte, ttsMaxAudio+1))
		return e
	})
	w = speechRequest(s, context.Background(), `{"text":"hi"}`, 1)
	if w.Code != 502 {
		t.Fatal(w.Code)
	}
}
func TestTTSUnauthenticated(t *testing.T) {
	for _, handler := range []gin.HandlerFunc{AITTSVoices, AITTSStream} {
		w := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(w)
		c.Request = httptest.NewRequest("GET", "/", nil)
		handler(c)
		if w.Code != 401 {
			t.Fatal(w.Code)
		}
	}
}
