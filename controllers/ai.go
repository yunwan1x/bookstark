package controllers

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"bookstark/models"

	"github.com/gin-gonic/gin"
)

// AICompleteRequest 是前端 POST 上来的请求体。
type AICompleteRequest struct {
	Messages    []map[string]string `json:"messages"`
	Scene       string              `json:"scene,omitempty"`
	Temperature *float64            `json:"temperature,omitempty"`
	MaxTokens   *int                `json:"max_tokens,omitempty"`
}

// AIComplete 把请求转发到上游 AI 服务并把流式响应转发回客户端。
// 支持两种 provider：
//   - openai: OpenAI / DeepSeek / Qwen 等任何兼容 /chat/completions 协议的服务，前端直接吃 SSE
//   - anthropic: Claude Messages API；服务端把它的 SSE 事件翻译成 OpenAI delta 格式，前端零感知
func AIComplete(c *gin.Context) {
	if models.GetSettingWithDefault("ai_enabled", "0") != "1" {
		apiError(c, http.StatusForbidden, "AI 助手未启用")
		return
	}

	provider := strings.ToLower(strings.TrimSpace(models.GetSettingWithDefault("ai_provider", "openai")))
	if provider != "anthropic" {
		provider = "openai"
	}

	baseURL := strings.TrimSpace(models.GetSettingWithDefault("ai_base_url", ""))
	apiKey := strings.TrimSpace(models.GetSettingWithDefault("ai_api_key", ""))
	model := strings.TrimSpace(models.GetSettingWithDefault("ai_model", ""))
	if baseURL == "" || apiKey == "" || model == "" {
		apiError(c, http.StatusServiceUnavailable, "AI 未配置完整 (base_url / api_key / model)")
		return
	}

	var req AICompleteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if len(req.Messages) == 0 {
		apiError(c, http.StatusBadRequest, "messages 不能为空")
		return
	}

	temperature := 0.7
	if req.Temperature != nil {
		temperature = *req.Temperature
	} else if v, err := strconv.ParseFloat(models.GetSettingWithDefault("ai_temperature", "0.7"), 64); err == nil {
		temperature = v
	}
	maxTokens := 2048
	if req.MaxTokens != nil {
		maxTokens = *req.MaxTokens
	} else if v, err := strconv.Atoi(models.GetSettingWithDefault("ai_max_tokens", "2048")); err == nil {
		maxTokens = v
	}

	if provider == "anthropic" {
		proxyAnthropic(c, baseURL, apiKey, model, req.Messages, temperature, maxTokens)
	} else {
		proxyOpenAI(c, baseURL, apiKey, model, req.Messages, temperature, maxTokens)
	}
}

// proxyOpenAI 把 OpenAI 兼容协议的 SSE 原样透传给客户端。
func proxyOpenAI(c *gin.Context, baseURL, apiKey, model string, messages []map[string]string, temperature float64, maxTokens int) {
	upstreamBody := map[string]interface{}{
		"model":       model,
		"messages":    messages,
		"stream":      true,
		"temperature": temperature,
		"max_tokens":  maxTokens,
		// 让上游在最后一帧带上 token usage。OpenAI / DeepSeek / Qwen 都支持。
		"stream_options": map[string]interface{}{"include_usage": true},
	}
	bodyJSON, _ := json.Marshal(upstreamBody)

	endpoint := strings.TrimRight(baseURL, "/") + "/chat/completions"
	upstreamReq, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(bodyJSON))
	if err != nil {
		apiError(c, http.StatusInternalServerError, "构造上游请求失败")
		return
	}
	upstreamReq.Header.Set("Content-Type", "application/json")
	upstreamReq.Header.Set("Authorization", "Bearer "+apiKey)
	upstreamReq.Header.Set("Accept", "text/event-stream")

	client := &http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Do(upstreamReq)
	if err != nil {
		log.Printf("AIComplete[openai]: upstream request failed: %v", err)
		apiError(c, http.StatusBadGateway, "调用 AI 服务失败")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		buf := make([]byte, 1024)
		n, _ := resp.Body.Read(buf)
		log.Printf("AIComplete[openai]: upstream %d: %s", resp.StatusCode, string(buf[:n]))
		apiError(c, http.StatusBadGateway, fmt.Sprintf("AI 服务返回 %d", resp.StatusCode))
		return
	}

	flusher := setSSEHeaders(c)
	if flusher == nil {
		return
	}

	reader := bufio.NewReader(resp.Body)
	clientGone := c.Request.Context().Done()
	var promptTokens, completionTokens int64
	for {
		select {
		case <-clientGone:
			_recordAIUsage(promptTokens, completionTokens)
			return
		default:
		}
		line, err := reader.ReadString('\n')
		if len(line) > 0 {
			if pt, ct, ok := _parseUsage(line); ok {
				if pt > promptTokens {
					promptTokens = pt
				}
				if ct > completionTokens {
					completionTokens = ct
				}
			}
			if _, werr := c.Writer.Write([]byte(line)); werr != nil {
				_recordAIUsage(promptTokens, completionTokens)
				return
			}
			flusher.Flush()
		}
		if err != nil {
			if err != io.EOF {
				log.Printf("AIComplete[openai]: stream read error: %v", err)
			}
			_recordAIUsage(promptTokens, completionTokens)
			return
		}
	}
}

// proxyAnthropic 把 Claude Messages API 的 SSE 事件流翻译成前端期望的 OpenAI 增量格式。
// 关键差异：
//   - 端点 /v1/messages，鉴权用 x-api-key + anthropic-version 头
//   - system 角色不能放 messages 数组，要单独传 system 字段
//   - 每个 content_block_delta 事件携带一段文本，需要包成 {"choices":[{"delta":{"content":"..."}}]}
//   - usage.input_tokens 在 message_start 帧里，output_tokens 在 message_delta / message_start 中
func proxyAnthropic(c *gin.Context, baseURL, apiKey, model string, messages []map[string]string, temperature float64, maxTokens int) {
	// 抽出 system role 合并为单段；其他消息按 user/assistant 转发。
	var sysParts []string
	var userMsgs []map[string]interface{}
	for _, m := range messages {
		role := strings.ToLower(strings.TrimSpace(m["role"]))
		content := m["content"]
		if role == "system" {
			if strings.TrimSpace(content) != "" {
				sysParts = append(sysParts, content)
			}
			continue
		}
		if role == "" {
			role = "user"
		}
		if role != "user" && role != "assistant" {
			continue
		}
		userMsgs = append(userMsgs, map[string]interface{}{
			"role":    role,
			"content": content,
		})
	}
	if len(userMsgs) == 0 {
		apiError(c, http.StatusBadRequest, "至少需要一条 user/assistant 消息")
		return
	}

	body := map[string]interface{}{
		"model":       model,
		"messages":    userMsgs,
		"max_tokens":  maxTokens,
		"temperature": temperature,
		"stream":      true,
	}
	if len(sysParts) > 0 {
		body["system"] = strings.Join(sysParts, "\n\n")
	}
	payload, _ := json.Marshal(body)

	endpoint := strings.TrimRight(baseURL, "/") + "/v1/messages"
	upstreamReq, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		apiError(c, http.StatusInternalServerError, "构造上游请求失败")
		return
	}
	upstreamReq.Header.Set("Content-Type", "application/json")
	upstreamReq.Header.Set("x-api-key", apiKey)
	upstreamReq.Header.Set("anthropic-version", "2023-06-01")
	upstreamReq.Header.Set("Accept", "text/event-stream")

	client := &http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Do(upstreamReq)
	if err != nil {
		log.Printf("AIComplete[anthropic]: upstream request failed: %v", err)
		apiError(c, http.StatusBadGateway, "调用 AI 服务失败")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		buf := make([]byte, 1024)
		n, _ := resp.Body.Read(buf)
		log.Printf("AIComplete[anthropic]: upstream %d: %s", resp.StatusCode, string(buf[:n]))
		apiError(c, http.StatusBadGateway, fmt.Sprintf("AI 服务返回 %d", resp.StatusCode))
		return
	}

	flusher := setSSEHeaders(c)
	if flusher == nil {
		return
	}

	reader := bufio.NewReader(resp.Body)
	clientGone := c.Request.Context().Done()
	var promptTokens, completionTokens int64
	doneSent := false

	writeDelta := func(text string) bool {
		if text == "" {
			return true
		}
		out := map[string]interface{}{
			"choices": []map[string]interface{}{{
				"delta": map[string]string{"content": text},
			}},
		}
		raw, _ := json.Marshal(out)
		if _, werr := fmt.Fprintf(c.Writer, "data: %s\n\n", raw); werr != nil {
			return false
		}
		flusher.Flush()
		return true
	}
	writeDone := func() {
		if doneSent {
			return
		}
		doneSent = true
		fmt.Fprint(c.Writer, "data: [DONE]\n\n")
		flusher.Flush()
	}

	for {
		select {
		case <-clientGone:
			_recordAIUsage(promptTokens, completionTokens)
			return
		default:
		}
		line, err := reader.ReadString('\n')
		if len(line) > 0 {
			trimmed := strings.TrimSpace(line)
			// Anthropic SSE 行可能是: "event: xxx" / "data: {...}" / 空行 / ": ping" 注释
			if strings.HasPrefix(trimmed, "data:") {
				rawPayload := strings.TrimSpace(strings.TrimPrefix(trimmed, "data:"))
				if rawPayload != "" && rawPayload != "[DONE]" {
					var ev map[string]interface{}
					if jerr := json.Unmarshal([]byte(rawPayload), &ev); jerr == nil {
						switch ev["type"] {
						case "message_start":
							if msg, ok := ev["message"].(map[string]interface{}); ok {
								if usage, ok := msg["usage"].(map[string]interface{}); ok {
									if v, ok := usage["input_tokens"].(float64); ok {
										promptTokens = int64(v)
									}
									if v, ok := usage["output_tokens"].(float64); ok {
										completionTokens = int64(v)
									}
								}
							}
						case "content_block_delta":
							if delta, ok := ev["delta"].(map[string]interface{}); ok {
								if dt, _ := delta["type"].(string); dt == "text_delta" {
									if text, ok := delta["text"].(string); ok {
										if !writeDelta(text) {
											_recordAIUsage(promptTokens, completionTokens)
											return
										}
									}
								}
							}
						case "message_delta":
							if usage, ok := ev["usage"].(map[string]interface{}); ok {
								if v, ok := usage["output_tokens"].(float64); ok && int64(v) > completionTokens {
									completionTokens = int64(v)
								}
							}
						case "message_stop":
							writeDone()
						}
					}
				}
			}
		}
		if err != nil {
			if err != io.EOF {
				log.Printf("AIComplete[anthropic]: stream read error: %v", err)
			}
			writeDone()
			_recordAIUsage(promptTokens, completionTokens)
			return
		}
	}
}

// setSSEHeaders 为流式响应配置 SSE 头并返回 Flusher；失败返回 nil。
func setSSEHeaders(c *gin.Context) http.Flusher {
	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("X-Accel-Buffering", "no")
	c.Writer.WriteHeader(http.StatusOK)
	flusher, ok := c.Writer.(http.Flusher)
	if !ok {
		log.Printf("AIComplete: response writer is not a Flusher")
		return nil
	}
	return flusher
}

// _parseUsage 从 OpenAI SSE "data: {json}" 行里解出 usage 字段。
func _parseUsage(line string) (int64, int64, bool) {
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, "data:") {
		return 0, 0, false
	}
	payload := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
	if payload == "" || payload == "[DONE]" {
		return 0, 0, false
	}
	var chunk struct {
		Usage *struct {
			PromptTokens     int64 `json:"prompt_tokens"`
			CompletionTokens int64 `json:"completion_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal([]byte(payload), &chunk); err != nil {
		return 0, 0, false
	}
	if chunk.Usage == nil {
		return 0, 0, false
	}
	return chunk.Usage.PromptTokens, chunk.Usage.CompletionTokens, true
}

// TestAIConnection 用 admin 提供的或 DB 中现有的 provider/base_url/api_key/model 配置，
// 向上游发一个最简短的非流式请求，验证可达性与鉴权。前端用来在保存设置前做"打个 ping"。
// 不计入用量统计。
func TestAIConnection(c *gin.Context) {
	var req struct {
		Provider string `json:"provider"`
		BaseURL  string `json:"base_url"`
		APIKey   string `json:"api_key"`
		Model    string `json:"model"`
	}
	_ = c.ShouldBindJSON(&req)

	pick := func(form, key string) string {
		v := strings.TrimSpace(form)
		if v != "" {
			return v
		}
		return strings.TrimSpace(models.GetSetting(key))
	}
	provider := strings.ToLower(pick(req.Provider, "ai_provider"))
	if provider != "anthropic" {
		provider = "openai"
	}
	baseURL := pick(req.BaseURL, "ai_base_url")
	apiKey := pick(req.APIKey, "ai_api_key")
	model := pick(req.Model, "ai_model")

	if baseURL == "" || apiKey == "" || model == "" {
		c.JSON(http.StatusOK, gin.H{
			"code": 0, "ok": false,
			"message": "未配置完整 (base_url / api_key / model)",
		})
		return
	}

	start := time.Now()
	var ok bool
	var msg, sample, detail string
	if provider == "anthropic" {
		ok, msg, sample, detail = testAnthropicConnection(baseURL, apiKey, model)
	} else {
		ok, msg, sample, detail = testOpenAIConnection(baseURL, apiKey, model)
	}
	latency := time.Since(start).Milliseconds()

	c.JSON(http.StatusOK, gin.H{
		"code":       0,
		"ok":         ok,
		"provider":   provider,
		"message":    msg,
		"sample":     sample,
		"detail":     detail,
		"latency_ms": latency,
	})
}

func testOpenAIConnection(baseURL, apiKey, model string) (ok bool, msg, sample, detail string) {
	body := map[string]interface{}{
		"model":      model,
		"messages":   []map[string]string{{"role": "user", "content": "ping"}},
		"max_tokens": 16,
		"stream":     false,
	}
	payload, _ := json.Marshal(body)
	endpoint := strings.TrimRight(baseURL, "/") + "/chat/completions"
	upReq, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return false, "构造请求失败", "", err.Error()
	}
	upReq.Header.Set("Content-Type", "application/json")
	upReq.Header.Set("Authorization", "Bearer "+apiKey)
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(upReq)
	if err != nil {
		return false, "网络错误", "", err.Error()
	}
	defer resp.Body.Close()
	rb, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode >= 400 {
		return false, fmt.Sprintf("上游返回 HTTP %d", resp.StatusCode), "", string(rb)
	}
	var r struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
		Usage struct {
			PromptTokens     int64 `json:"prompt_tokens"`
			CompletionTokens int64 `json:"completion_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(rb, &r); err != nil {
		return false, "上游响应解析失败", "", string(rb)
	}
	if len(r.Choices) > 0 {
		sample = strings.TrimSpace(r.Choices[0].Message.Content)
	}
	return true, "连接成功", sample, ""
}

func testAnthropicConnection(baseURL, apiKey, model string) (ok bool, msg, sample, detail string) {
	body := map[string]interface{}{
		"model":      model,
		"messages":   []map[string]string{{"role": "user", "content": "ping"}},
		"max_tokens": 16,
		"stream":     false,
	}
	payload, _ := json.Marshal(body)
	endpoint := strings.TrimRight(baseURL, "/") + "/v1/messages"
	upReq, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return false, "构造请求失败", "", err.Error()
	}
	upReq.Header.Set("Content-Type", "application/json")
	upReq.Header.Set("x-api-key", apiKey)
	upReq.Header.Set("anthropic-version", "2023-06-01")
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(upReq)
	if err != nil {
		return false, "网络错误", "", err.Error()
	}
	defer resp.Body.Close()
	rb, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode >= 400 {
		return false, fmt.Sprintf("上游返回 HTTP %d", resp.StatusCode), "", string(rb)
	}
	var r struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(rb, &r); err != nil {
		return false, "上游响应解析失败", "", string(rb)
	}
	for _, b := range r.Content {
		if b.Type == "text" {
			sample += b.Text
		}
	}
	return true, "连接成功", strings.TrimSpace(sample), ""
}

// _recordAIUsage 持久化每次请求的 token 计数；请求计数永远 +1，token 计数仅在上游汇报时累加。
func _recordAIUsage(promptTokens, completionTokens int64) {
	if _, err := models.IncrementSettingInt("ai_total_requests", 1); err != nil {
		log.Printf("AIComplete: bump ai_total_requests failed: %v", err)
	}
	if promptTokens > 0 {
		if _, err := models.IncrementSettingInt("ai_total_prompt_tokens", promptTokens); err != nil {
			log.Printf("AIComplete: bump ai_total_prompt_tokens failed: %v", err)
		}
	}
	if completionTokens > 0 {
		if _, err := models.IncrementSettingInt("ai_total_completion_tokens", completionTokens); err != nil {
			log.Printf("AIComplete: bump ai_total_completion_tokens failed: %v", err)
		}
	}
}
