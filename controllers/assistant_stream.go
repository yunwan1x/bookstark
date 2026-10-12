package controllers

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// The only writer for this response. Heartbeats and content are serialized;
// Close joins the heartbeat before Gin can reuse its context/response writer.
type assistantSSE struct {
	mu            sync.Mutex
	c             *gin.Context
	ctx           context.Context
	cancel        context.CancelFunc
	stop, stopped chan struct{}
}

func startAssistantSSE(c *gin.Context, ctx context.Context, cancel context.CancelFunc) *assistantSSE {
	s := &assistantSSE{c: c, ctx: ctx, cancel: cancel, stop: make(chan struct{}), stopped: make(chan struct{})}
	c.Header("Content-Type", "text/event-stream; charset=utf-8")
	c.Header("Cache-Control", "private, no-store, no-transform")
	c.Header("X-Accel-Buffering", "no")
	c.Set("assistant_stream", s)
	go func() {
		defer close(s.stopped)
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if s.send("ping", gin.H{}) != nil {
					return
				}
			case <-s.stop:
				return
			case <-ctx.Done():
				return
			}
		}
	}()
	return s
}
func (s *assistantSSE) close() {
	close(s.stop)
	<-s.stopped
	_ = http.NewResponseController(s.c.Writer).SetWriteDeadline(time.Time{})
}
func (s *assistantSSE) send(event string, payload any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.ctx.Err(); err != nil {
		return err
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	// A disconnected/slow reader must not pin this handler indefinitely while
	// writing. Gin exposes Unwrap, so ResponseController reaches net/http.
	deadline := time.Now().Add(10 * time.Second)
	if end, ok := s.ctx.Deadline(); ok && end.Before(deadline) {
		deadline = end
	}
	writer := http.NewResponseController(s.c.Writer)
	_ = writer.SetWriteDeadline(deadline)
	defer writer.SetWriteDeadline(time.Time{})
	_, err = fmt.Fprintf(s.c.Writer, "event: %s\ndata: %s\n\n", event, data)
	if err != nil {
		s.cancel()
		return err
	}
	s.c.Writer.Flush()
	return nil
}

// Bounded SSE parser. A closed connection is NOT success: each provider must
// provide its terminal marker and a valid finish reason. Tool arguments are
// accumulated, never executed from deltas. Reasoning blocks are never emitted.
func readAssistantStream(reader io.Reader, anthropic bool, emit func(string) error) (assistantWireMessage, error) {
	m := assistantWireMessage{Role: "assistant"}
	scan := bufio.NewScanner(io.LimitReader(reader, 2*1024*1024+1))
	scan.Buffer(make([]byte, 4096), 256*1024)
	var data []string
	var size, total int
	finished, started := false, false
	reason := ""
	var input, output int64
	calls := map[int]*assistantCall{}
	type block struct {
		kind   string
		closed bool
		call   *assistantCall
	}
	blocks := map[int]*block{}
	addText := func(text string) error {
		if len(m.Content)+len(text) > 24000 {
			return errAssistantProvider
		}
		m.Content += text
		if text != "" {
			return emit(text)
		}
		return nil
	}
	consume := func(raw string) error {
		if !anthropic {
			if raw == "[DONE]" {
				finished = true
				return nil
			}
			var chunk struct {
				Error   json.RawMessage `json:"error"`
				Choices []struct {
					Index  int    `json:"index"`
					Finish string `json:"finish_reason"`
					Delta  struct {
						Content string `json:"content"`
						Calls   []struct {
							Index    int `json:"index"`
							ID, Type string
							Function struct{ Name, Arguments string }
						} `json:"tool_calls"`
					} `json:"delta"`
				} `json:"choices"`
				Usage struct {
					Input  int64 `json:"prompt_tokens"`
					Output int64 `json:"completion_tokens"`
				} `json:"usage"`
			}
			if json.Unmarshal([]byte(raw), &chunk) != nil || len(chunk.Error) > 0 {
				return errAssistantProvider
			}
			if chunk.Usage.Input > 0 {
				input = chunk.Usage.Input
			}
			if chunk.Usage.Output > 0 {
				output = chunk.Usage.Output
			}
			if len(chunk.Choices) > 1 {
				return errAssistantProvider
			}
			for _, choice := range chunk.Choices {
				if choice.Index != 0 || reason != "" {
					return errAssistantProvider
				}
				if err := addText(choice.Delta.Content); err != nil {
					return err
				}
				for _, d := range choice.Delta.Calls {
					if d.Index < 0 || d.Index >= 5 {
						return errAssistantProvider
					}
					call := calls[d.Index]
					if call == nil {
						call = &assistantCall{}
						calls[d.Index] = call
					}
					call.ID += d.ID
					call.Type += d.Type
					call.Function.Name += d.Function.Name
					call.Function.Arguments += d.Function.Arguments
					if len(call.ID) > 200 || len(call.Type) > 30 || len(call.Function.Name) > 100 || len(call.Function.Arguments) > 24000 {
						return errAssistantProvider
					}
				}
				if choice.Finish != "" {
					reason = choice.Finish
				}
			}
			return nil
		}
		var e struct {
			Type    string
			Index   int
			Error   json.RawMessage
			Message struct {
				Usage struct {
					Input  int64 `json:"input_tokens"`
					Output int64 `json:"output_tokens"`
				}
			}
			Usage struct {
				Output int64 `json:"output_tokens"`
			}
			Block struct {
				Type, Text, ID, Name string
				Input                json.RawMessage
			} `json:"content_block"`
			Delta struct {
				Type, Text string
				JSON       string `json:"partial_json"`
				Stop       string `json:"stop_reason"`
			}
		}
		if json.Unmarshal([]byte(raw), &e) != nil || e.Type == "error" {
			return errAssistantProvider
		}
		if e.Type == "ping" {
			return nil
		}
		if e.Type == "message_start" {
			if started {
				return errAssistantProvider
			}
			started = true
			input = e.Message.Usage.Input
			output = e.Message.Usage.Output
			return nil
		}
		if !started {
			return errAssistantProvider
		}
		switch e.Type {
		case "content_block_start":
			if reason != "" || e.Index < 0 || e.Index >= 32 || blocks[e.Index] != nil {
				return errAssistantProvider
			}
			b := &block{kind: e.Block.Type}
			blocks[e.Index] = b
			switch b.kind {
			case "text":
				return addText(e.Block.Text)
			case "tool_use":
				if len(calls) >= 5 {
					return errAssistantProvider
				}
				call := &assistantCall{ID: e.Block.ID, Type: "function"}
				call.Function.Name = e.Block.Name
				b.call = call
				calls[len(calls)] = call
				if len(e.Block.Input) > 0 && string(e.Block.Input) != "{}" {
					call.Function.Arguments = string(e.Block.Input)
				}
			case "thinking", "redacted_thinking":
			default:
				return errAssistantProvider
			}
		case "content_block_delta":
			b := blocks[e.Index]
			if b == nil || b.closed || reason != "" {
				return errAssistantProvider
			}
			switch e.Delta.Type {
			case "text_delta":
				if b.kind != "text" {
					return errAssistantProvider
				}
				return addText(e.Delta.Text)
			case "input_json_delta":
				if b.call == nil {
					return errAssistantProvider
				}
				b.call.Function.Arguments += e.Delta.JSON
				if len(b.call.Function.Arguments) > 24000 {
					return errAssistantProvider
				}
			case "thinking_delta", "signature_delta":
				if b.kind != "thinking" {
					return errAssistantProvider
				}
			}
		case "content_block_stop":
			b := blocks[e.Index]
			if b == nil || b.closed {
				return errAssistantProvider
			}
			b.closed = true
			if b.call != nil && b.call.Function.Arguments == "" {
				b.call.Function.Arguments = "{}"
			}
		case "message_delta":
			for _, b := range blocks {
				if !b.closed {
					return errAssistantProvider
				}
			}
			if e.Delta.Stop != "" {
				reason = e.Delta.Stop
			}
			output = e.Usage.Output
		case "message_stop":
			finished = true
		}
		return nil
	}
	for scan.Scan() {
		line := scan.Text()
		total += len(line) + 1
		if total > 2*1024*1024 {
			return m, errAssistantProvider
		}
		if line == "" {
			if len(data) > 0 {
				if err := consume(strings.Join(data, "\n")); err != nil {
					return m, err
				}
				data = nil
				size = 0
				if finished {
					break
				}
			}
		} else if strings.HasPrefix(line, "data:") {
			part := strings.TrimPrefix(line, "data:")
			part = strings.TrimPrefix(part, " ")
			size += len(part)
			if size > 256*1024 {
				return m, errAssistantProvider
			}
			data = append(data, part)
		}
	}
	if scan.Err() != nil || !finished {
		return m, errAssistantProvider
	}
	if anthropic {
		for _, b := range blocks {
			if !b.closed {
				return m, errAssistantProvider
			}
		}
		if reason != "end_turn" && reason != "tool_use" && reason != "stop_sequence" {
			return m, errAssistantProvider
		}
	} else if reason != "stop" && reason != "tool_calls" {
		return m, errAssistantProvider
	}
	if (reason == "tool_calls" || reason == "tool_use") != (len(calls) > 0) {
		return m, errAssistantProvider
	}
	seen := map[string]bool{}
	for i := 0; i < len(calls); i++ {
		call := calls[i]
		if call == nil || call.ID == "" || len(call.ID) > 200 || seen[call.ID] || call.Type != "function" || call.Function.Name == "" || len(call.Function.Name) > 100 || len(call.Function.Arguments) > 24000 || !json.Valid([]byte(call.Function.Arguments)) {
			return m, errAssistantProvider
		}
		seen[call.ID] = true
		m.Calls = append(m.Calls, *call)
	}
	if strings.TrimSpace(m.Content) == "" && len(m.Calls) == 0 {
		return m, errAssistantProvider
	}
	_recordAIUsage(input, output)
	return m, nil
}
