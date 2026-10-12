package controllers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type assistantCall struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
	} `json:"function"`
}
type assistantWireMessage struct {
	Role    string          `json:"role"`
	Content string          `json:"content"`
	Calls   []assistantCall `json:"tool_calls,omitempty"`
	CallID  string          `json:"tool_call_id,omitempty"`
}
type assistantProvider struct {
	Kind, BaseURL, Key, Model string
	MaxTokens                 int
}

var errAssistantProvider = errors.New("assistant provider failure")

func assistantTools(anthropic bool) []map[string]any {
	s := func(desc string) map[string]any { return map[string]any{"type": "string", "description": desc} }
	kinds := []string{"note", "article", "task", "bookmark", "book", "document", "topic"}
	type def struct {
		name, description string
		properties        map[string]any
		required          []string
	}
	defs := []def{
		{"search", "Search the current account only. Returns up to 20 matches with short excerpts, newest IDs first. Empty query lists recent records. Use a kind to narrow results; no external web search. Protected and non-Markdown bodies are excluded.", map[string]any{"query": s("Literal keyword, or empty for recent records"), "kind": map[string]any{"type": "string", "enum": append([]string{""}, kinds...)}}, []string{"query", "kind"}},
		{"read", "Read a current-account record identified by search. At most 12000 characters; truncated=true means this is NOT the full content. Never claim to have read unavailable content.", map[string]any{"kind": map[string]any{"type": "string", "enum": kinds}, "id": map[string]any{"type": "integer", "minimum": 1}}, []string{"kind", "id"}},
		{"draft_note", "Prepare a PRIVATE Markdown note for user review, only when the user asks to create one. Does NOT create the note. The user must press Confirm create in the UI. Do not duplicate a draft already proposed.", map[string]any{"title": s("Note title, 1-200 characters"), "content": s("Markdown body, up to 20000 bytes")}, []string{"title", "content"}},
		{"draft_task", "Prepare a pending top-level task for user review, only when asked. Does NOT create a task. User must confirm in UI. If no deadline is specified, use seven days from today's date.", map[string]any{"content": s("Task content, 1-1000 characters"), "due_date": s("Deadline YYYY-MM-DD")}, []string{"content", "due_date"}},
	}
	out := []map[string]any{}
	for _, d := range defs {
		schema := map[string]any{"type": "object", "properties": d.properties, "required": d.required, "additionalProperties": false}
		if anthropic {
			out = append(out, map[string]any{"name": d.name, "description": d.description, "input_schema": schema})
		} else {
			out = append(out, map[string]any{"type": "function", "function": map[string]any{"name": d.name, "description": d.description, "parameters": schema}})
		}
	}
	return out
}

// No automatic retries: retries could repeat billable generations. Every
// upstream request is bounded and cancelled with the browser request.
func (p assistantProvider) complete(ctx context.Context, messages []assistantWireMessage, emit func(string) error) (assistantWireMessage, error) {
	anthropic := p.Kind == "anthropic"
	body := map[string]any{"model": p.Model, "max_tokens": p.MaxTokens, "stream": emit != nil, "tools": assistantTools(anthropic)}
	if emit != nil && !anthropic {
		body["stream_options"] = map[string]any{"include_usage": true}
	}
	endpoint := strings.TrimRight(p.BaseURL, "/") + "/chat/completions"
	if anthropic {
		endpoint = strings.TrimRight(p.BaseURL, "/") + "/v1/messages"
		var system []string
		converted := []map[string]any{}
		for _, m := range messages {
			if m.Role == "system" {
				system = append(system, m.Content)
				continue
			}
			blocks := []map[string]any{}
			role := m.Role
			if m.Role == "tool" {
				role = "user"
				blocks = append(blocks, map[string]any{"type": "tool_result", "tool_use_id": m.CallID, "content": m.Content})
			} else {
				if m.Content != "" {
					blocks = append(blocks, map[string]any{"type": "text", "text": m.Content})
				}
				for _, call := range m.Calls {
					var args any
					if json.Unmarshal([]byte(call.Function.Arguments), &args) != nil {
						return assistantWireMessage{}, errAssistantProvider
					}
					blocks = append(blocks, map[string]any{"type": "tool_use", "id": call.ID, "name": call.Function.Name, "input": args})
				}
			}
			// All tool results from one assistant turn must be in one user message.
			if len(converted) > 0 && converted[len(converted)-1]["role"] == role {
				last := converted[len(converted)-1]
				last["content"] = append(last["content"].([]map[string]any), blocks...)
			} else {
				converted = append(converted, map[string]any{"role": role, "content": blocks})
			}
		}
		body["system"] = strings.Join(system, "\n\n")
		body["messages"] = converted
	} else {
		body["messages"] = messages
	}
	data, err := json.Marshal(body)
	if err != nil {
		return assistantWireMessage{}, err
	}
	if len(data) > 512*1024 {
		return assistantWireMessage{}, errAssistantProvider
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	if err != nil {
		return assistantWireMessage{}, errAssistantProvider
	}
	req.Header.Set("Content-Type", "application/json")
	if anthropic {
		req.Header.Set("x-api-key", p.Key)
		req.Header.Set("anthropic-version", "2023-06-01")
	} else {
		req.Header.Set("Authorization", "Bearer "+p.Key)
	}
	client := &http.Client{CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Do(req)
	if err != nil {
		return assistantWireMessage{}, errAssistantProvider
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return assistantWireMessage{}, fmt.Errorf("%w: HTTP %d", errAssistantProvider, resp.StatusCode)
	}
	if emit != nil {
		if !strings.HasPrefix(strings.ToLower(resp.Header.Get("Content-Type")), "text/event-stream") {
			return assistantWireMessage{}, errAssistantProvider
		}
		return readAssistantStream(resp.Body, anthropic, emit)
	}
	data, err = io.ReadAll(io.LimitReader(resp.Body, 256*1024+1))
	if err != nil || len(data) > 256*1024 {
		return assistantWireMessage{}, errAssistantProvider
	}
	m := assistantWireMessage{Role: "assistant"}
	if anthropic {
		var r struct {
			StopReason string `json:"stop_reason"`
			Content    []struct {
				Type, Text, ID, Name string
				Input                json.RawMessage
			} `json:"content"`
			Usage struct {
				Input  int64 `json:"input_tokens"`
				Output int64 `json:"output_tokens"`
			} `json:"usage"`
		}
		if json.Unmarshal(data, &r) != nil || (r.StopReason != "end_turn" && r.StopReason != "tool_use" && r.StopReason != "stop_sequence") {
			return m, errAssistantProvider
		}
		for _, b := range r.Content {
			switch b.Type {
			case "text":
				m.Content += b.Text
			case "tool_use":
				call := assistantCall{ID: b.ID, Type: "function"}
				call.Function.Name = b.Name
				call.Function.Arguments = string(b.Input)
				m.Calls = append(m.Calls, call)
			}
		}
		_recordAIUsage(r.Usage.Input, r.Usage.Output)
	} else {
		var r struct {
			Choices []struct {
				Message      assistantWireMessage `json:"message"`
				FinishReason string               `json:"finish_reason"`
			} `json:"choices"`
			Usage struct {
				Prompt     int64 `json:"prompt_tokens"`
				Completion int64 `json:"completion_tokens"`
			} `json:"usage"`
		}
		if json.Unmarshal(data, &r) != nil || len(r.Choices) != 1 || (r.Choices[0].FinishReason != "stop" && r.Choices[0].FinishReason != "tool_calls") {
			return m, errAssistantProvider
		}
		m = r.Choices[0].Message
		m.Role = "assistant"
		m.CallID = ""
		_recordAIUsage(r.Usage.Prompt, r.Usage.Completion)
	}
	if len(m.Content) > 24000 || len(m.Calls) > 5 || (strings.TrimSpace(m.Content) == "" && len(m.Calls) == 0) {
		return m, errAssistantProvider
	}
	seen := map[string]bool{}
	for _, call := range m.Calls {
		if call.ID == "" || len(call.ID) > 200 || seen[call.ID] || call.Type != "function" || len(call.Function.Arguments) > 24000 {
			return m, errAssistantProvider
		}
		seen[call.ID] = true
	}
	return m, nil
}
