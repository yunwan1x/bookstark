package models

import (
	"encoding/json"
	"fmt"
	"strings"
)

const (
	RichDocumentType          = "richdoc"
	RichDocumentSchema        = "bookstark-richdoc"
	RichDocumentSchemaVersion = 1
	RichDocumentEditorVersion = "0.9.137"
	RichDocumentMaxBytes      = 5 * 1024 * 1024
)

type RichDocumentEnvelope struct {
	Schema        string          `json:"schema"`
	SchemaVersion int             `json:"schema_version"`
	EditorVersion string          `json:"editor_version"`
	Data          json.RawMessage `json:"data"`
	Options       json.RawMessage `json:"options,omitempty"`
	Comments      json.RawMessage `json:"comments,omitempty"`
}

func DefaultRichDocument() string {
	return `{"schema":"bookstark-richdoc","schema_version":1,"editor_version":"0.9.137","data":{"header":[],"main":[{"value":""}],"footer":[],"graffiti":[]},"options":{},"comments":[]}`
}

func ValidateRichDocument(content string) error {
	if len(content) > RichDocumentMaxBytes {
		return fmt.Errorf("富文档内容不能超过5MB")
	}
	var envelope RichDocumentEnvelope
	if err := json.Unmarshal([]byte(content), &envelope); err != nil {
		return fmt.Errorf("富文档数据格式错误")
	}
	if envelope.Schema != RichDocumentSchema || envelope.SchemaVersion != RichDocumentSchemaVersion {
		return fmt.Errorf("不支持的富文档数据版本")
	}
	var data struct {
		Main []json.RawMessage `json:"main"`
	}
	if err := json.Unmarshal(envelope.Data, &data); err != nil || data.Main == nil {
		return fmt.Errorf("富文档正文数据缺失")
	}
	if len(envelope.Options) > 0 && !json.Valid(envelope.Options) {
		return fmt.Errorf("富文档页面配置无效")
	}
	if len(envelope.Comments) > 0 {
		var comments []json.RawMessage
		if err := json.Unmarshal(envelope.Comments, &comments); err != nil {
			return fmt.Errorf("富文档批注数据无效")
		}
	}
	if hasEmbeddedRichDocumentImage(json.RawMessage(content)) {
		return fmt.Errorf("富文档图片必须先上传到系统，不能嵌入文档")
	}
	return nil
}

func hasEmbeddedRichDocumentImage(raw json.RawMessage) bool {
	var value any
	if json.Unmarshal(raw, &value) != nil {
		return false
	}
	var walk func(any) bool
	walk = func(v any) bool {
		switch item := v.(type) {
		case map[string]any:
			isImageElement := item["type"] == "image"
			for key, child := range item {
				if value, ok := child.(string); ok && (isImageElement && key == "value" || key == "image" || key == "src" || key == "url") {
					lower := strings.ToLower(strings.TrimSpace(value))
					if strings.HasPrefix(lower, "data:image/") || strings.HasPrefix(lower, "blob:") {
						return true
					}
				}
				if walk(child) {
					return true
				}
			}
		case []any:
			for _, child := range item {
				if walk(child) {
					return true
				}
			}
		}
		return false
	}
	return walk(value)
}

func extractRichDocumentText(raw string) string {
	decoded, err := DecodeContentForType(RichDocumentType, raw)
	if err != nil {
		return ""
	}
	var envelope RichDocumentEnvelope
	if json.Unmarshal([]byte(decoded), &envelope) != nil {
		return ""
	}
	var data map[string]any
	if json.Unmarshal(envelope.Data, &data) != nil {
		return ""
	}
	parts := make([]string, 0, 30)
	var walk func(any)
	walk = func(v any) {
		if len(parts) >= 30 {
			return
		}
		switch item := v.(type) {
		case map[string]any:
			if value, ok := item["value"]; ok {
				if text, isText := value.(string); isText {
					text = strings.TrimSpace(text)
					if text != "" && !strings.HasPrefix(strings.ToLower(text), "data:image/") {
						parts = append(parts, text)
					}
				} else {
					walk(value)
				}
			}
			for _, key := range []string{"valueList", "trList", "tdList"} {
				if child, ok := item[key]; ok {
					walk(child)
				}
			}
		case []any:
			for _, child := range item {
				walk(child)
			}
		}
	}
	walk(data["main"])
	text := strings.Join(strings.Fields(strings.Join(parts, " ")), " ")
	if len([]rune(text)) > 200 {
		return string([]rune(text)[:200])
	}
	return text
}
