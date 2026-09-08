package models

import (
	"encoding/json"
	"fmt"
)

const PresentationType = "presentation"

type presentationDocument struct {
	Title  string            `json:"title"`
	Width  float64           `json:"width"`
	Height float64           `json:"height"`
	Theme  map[string]any    `json:"theme"`
	Slides []json.RawMessage `json:"slides"`
}

// DefaultPresentation returns a minimal PPTist presentation with one blank slide.
func DefaultPresentation(title string) string {
	if title == "" {
		title = "未命名演示文稿"
	}
	payload := map[string]any{
		"title":  title,
		"width":  1000,
		"height": 562.5,
		"theme": map[string]any{
			"themeColors":     []string{"#5b9bd5", "#ed7d31", "#a5a5a5", "#ffc000", "#4472c4", "#70ad47"},
			"fontColor":       "#333",
			"fontName":        "",
			"backgroundColor": "#fff",
			"shadow": map[string]any{
				"h": 3, "v": 3, "blur": 2, "color": "#808080",
			},
			"outline": map[string]any{
				"width": 2, "color": "#525252", "style": "solid",
			},
		},
		"slides": []any{
			map[string]any{
				"id":       "slide-1",
				"elements": []any{},
			},
		},
	}
	data, _ := json.Marshal(payload)
	return string(data)
}

func ValidatePresentation(content string) error {
	if content == "" {
		return fmt.Errorf("演示文稿内容不能为空")
	}
	var doc presentationDocument
	if err := json.Unmarshal([]byte(content), &doc); err != nil {
		return fmt.Errorf("演示文稿数据格式无效")
	}
	if doc.Width <= 0 || doc.Height <= 0 {
		return fmt.Errorf("演示文稿画布尺寸无效")
	}
	if len(doc.Slides) == 0 {
		return fmt.Errorf("演示文稿至少需要一页幻灯片")
	}
	for _, slide := range doc.Slides {
		var item map[string]any
		if err := json.Unmarshal(slide, &item); err != nil {
			return fmt.Errorf("演示文稿幻灯片数据无效")
		}
		if _, ok := item["id"].(string); !ok {
			return fmt.Errorf("演示文稿幻灯片缺少标识")
		}
		if _, ok := item["elements"].([]any); !ok {
			return fmt.Errorf("演示文稿幻灯片元素格式无效")
		}
	}
	return nil
}
