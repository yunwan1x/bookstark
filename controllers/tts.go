package controllers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"bookstark/internal/edgetts"
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
)

const ttsMaxAudio = 1024 * 1024

var ttsVoices = []struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Locale string `json:"locale"`
}{
	{"zh-CN-YunxiNeural", "云希 · 普通话男声", "zh-CN"},
	{"zh-CN-XiaoxiaoNeural", "晓晓 · 普通话女声", "zh-CN"},
	{"en-US-AriaNeural", "Aria · English", "en-US"},
	{"en-US-GuyNeural", "Guy · English", "en-US"},
}

type ttsProvider func(context.Context, string, string, io.Writer) error
type ttsService struct {
	synthesize ttsProvider
	mu         sync.Mutex
	active     int
	users      map[int64]int
	timeout    time.Duration
}

var assistantSpeech = &ttsService{synthesize: edgeSpeech, users: map[int64]int{}, timeout: 25 * time.Second}

func edgeSpeech(ctx context.Context, text, voice string, w io.Writer) error {
	proxy := strings.TrimSpace(os.Getenv("BOOKSTARK_TTS_PROXY"))
	if proxy != "" {
		u, err := url.Parse(proxy)
		if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
			return errors.New("invalid TTS proxy configuration")
		}
	}
	return edgetts.WriteTo(ctx, text, voice, proxy, w)
}
func ttsAllowed(c *gin.Context) bool {
	if middleware.GetMemberID(c) <= 0 {
		apiError(c, http.StatusUnauthorized, "请先登录")
		return false
	}
	if models.GetSettingWithDefault("ai_enabled", "0") != "1" {
		apiError(c, http.StatusForbidden, "AI 助手未启用")
		return false
	}
	return true
}
func AITTSVoices(c *gin.Context) {
	if !ttsAllowed(c) {
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{"code": 0, "voices": ttsVoices})
}
func AITTSStream(c *gin.Context) {
	if !ttsAllowed(c) {
		return
	}
	assistantSpeech.serve(c)
}
func (s *ttsService) acquire(id int64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.active >= 8 || s.users[id] >= 2 {
		return false
	}
	s.active++
	s.users[id]++
	return true
}
func (s *ttsService) release(id int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.active--
	s.users[id]--
	if s.users[id] == 0 {
		delete(s.users, id)
	}
}
func (s *ttsService) serve(c *gin.Context) {
	id := middleware.GetMemberID(c)
	if id <= 0 {
		apiError(c, http.StatusUnauthorized, "请先登录")
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 16*1024)
	var req struct {
		Text  string `json:"text"`
		Voice string `json:"voice"`
	}
	if c.ShouldBindJSON(&req) != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误或内容过大")
		return
	}
	req.Text = strings.TrimSpace(req.Text)
	if req.Text == "" || !utf8.ValidString(req.Text) || utf8.RuneCountInString(req.Text) > 800 {
		apiError(c, http.StatusBadRequest, "每段朗读内容须为 1 至 800 字")
		return
	}
	if req.Voice == "" {
		req.Voice = "zh-CN-YunxiNeural"
	}
	found := false
	for _, v := range ttsVoices {
		if v.ID == req.Voice {
			found = true
			break
		}
	}
	if !found {
		apiError(c, http.StatusBadRequest, "不支持的音色")
		return
	}
	if !s.acquire(id) {
		apiError(c, http.StatusTooManyRequests, "朗读请求较多，请稍后再试")
		return
	}
	defer s.release(id)
	ctx, cancel := context.WithTimeout(c.Request.Context(), s.timeout)
	defer cancel()
	writer := &ttsFrameWriter{ctx: ctx, c: c}
	err := s.synthesize(ctx, req.Text, req.Voice, writer)
	if c.Request.Context().Err() != nil {
		return
	}
	if err != nil || ctx.Err() != nil || writer.bytes == 0 {
		if !writer.started {
			apiError(c, http.StatusBadGateway, "语音合成失败，请稍后重试")
		} else {
			_ = writer.frame(gin.H{"event": "error", "message": "语音连接中断，请重新朗读"})
		}
		return
	}
	_ = writer.frame(gin.H{"event": "done", "bytes": writer.bytes})
}

// NDJSON framing makes an upstream failure distinguishable from a complete MP3.
// Streaming clients may play audio immediately and stop on an error frame.
type ttsFrameWriter struct {
	ctx     context.Context
	c       *gin.Context
	bytes   int
	started bool
}

func (w *ttsFrameWriter) frame(v any) error {
	if err := w.c.Request.Context().Err(); err != nil {
		return err
	}
	if !w.started {
		w.c.Header("Content-Type", "application/x-ndjson; charset=utf-8")
		w.c.Header("Cache-Control", "no-store")
		w.c.Header("X-Accel-Buffering", "no")
		w.c.Header("X-Content-Type-Options", "nosniff")
		w.c.Status(http.StatusOK)
		w.started = true
	}
	if err := json.NewEncoder(w.c.Writer).Encode(v); err != nil {
		return err
	}
	w.c.Writer.Flush()
	return nil
}
func (w *ttsFrameWriter) Write(p []byte) (int, error) {
	if err := w.ctx.Err(); err != nil {
		return 0, err
	}
	if w.bytes+len(p) > ttsMaxAudio {
		return 0, errors.New("audio limit")
	}
	n := 0
	for len(p) > 0 {
		size := len(p)
		if size > 16*1024 {
			size = 16 * 1024
		}
		if err := w.frame(gin.H{"event": "audio", "data": base64.StdEncoding.EncodeToString(p[:size])}); err != nil {
			return n, err
		}
		w.bytes += size
		n += size
		p = p[size:]
	}
	return n, nil
}
