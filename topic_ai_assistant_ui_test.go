package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicPageUsesSharedAIReadingAssistant(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/topics.html")
	if err != nil {
		t.Fatalf("read topics template: %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}
	assistantBytes, err := os.ReadFile("static/js/ai-reading-assistant.js")
	if err != nil {
		t.Fatalf("read shared assistant js: %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/ai-reading-assistant.css")
	if err != nil {
		t.Fatalf("read shared assistant css: %v", err)
	}
	topicCSSBytes, err := os.ReadFile("static/css/topics.css")
	if err != nil {
		t.Fatalf("read topics css: %v", err)
	}

	template := string(templateBytes)
	js := string(jsBytes)
	assistant := string(assistantBytes)
	css := string(cssBytes)
	topicCSS := string(topicCSSBytes)

	for _, required := range []string{
		`/static/css/ai-reading-assistant.css`,
		`id="topicOverviewAIAssistantBtn"`,
		`class="topic-card-tool-btn topic-overview-ai-btn"`,
		`aria-label="{{call .T "topic.ai.assistant.title"}}"`,
		`/static/js/ai-reading-assistant.js`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("topics template should contain %q", required)
		}
	}
	for _, required := range []string{
		"topicOverviewAIAssistantBtn",
		"openTopicAIAssistant",
		"buildTopicAIAssistantContext",
		"t('topic.ai.assistant.title'",
		"openContextEditorOnFullClick: true",
		"t('topic.ai.action.summarize'",
		"t('topic.ai.action.conclusion'",
		"t('topic.ai.action.gaps'",
		"t('topic.ai.action.next'",
		"t('topic.ai.action.outline'",
		"topic_assistant",
		"t('topic.ai.context_label'",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topics js should contain %q", required)
		}
	}
	for _, required := range []string{
		"window.AIReadingAssistant",
		"preview-ai-panel",
		"preview-ai-maximized",
		"drawing-ai-collapsed",
		"visualViewport",
		"openContextEditor",
		"preview-ai-context-editor",
		".preview-ai-input').addEventListener('keydown'",
		"if (e.key === 'Enter'",
		"config.openContextEditorOnFullClick",
		"AIHelper.complete",
		"AIHelper.buildMessages",
		"data-context=\"full\"",
		"data-context=\"clear\"",
	} {
		if !strings.Contains(assistant, required) {
			t.Fatalf("shared assistant js should contain %q", required)
		}
	}
	for _, required := range []string{
		".preview-ai-panel",
		".preview-ai-context-strip",
		".preview-ai-context-badge",
		".preview-ai-input",
		".preview-ai-message-content.note-content",
		"white-space: normal;",
		".preview-ai-message.from-user",
		"white-space: pre-wrap;",
		"@media (max-width: 640px)",
		"left: 5px;",
		"height: 76px;",
		"@keyframes preview-ai-slide-down",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("shared assistant css should contain %q", required)
		}
	}
	for _, required := range []string{
		".topic-overview-ai-btn",
		"display: inline-flex;",
	} {
		if !strings.Contains(topicCSS, required) {
			t.Fatalf("topics css should contain overview AI button style %q", required)
		}
	}

	for _, required := range []string{
		".topic-overview-ai-btn",
		"background: transparent;",
		"border-color: transparent;",
		"color: #7c3aed;",
		".topic-overview-ai-btn:hover",
		"background: rgba(124, 58, 237, 0.1);",
	} {
		if !strings.Contains(topicCSS, required) {
			t.Fatalf("topic assistant button should match the blue primary action style %q", required)
		}
	}
}

func TestTopicAIAssistantContextExcludesResources(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}
	js := string(jsBytes)
	start := strings.Index(js, "buildTopicAIAssistantContext: function()")
	end := strings.Index(js, "ensureTopicAIAssistant: function()")
	if start < 0 || end < 0 || end <= start {
		t.Fatalf("topics js should define buildTopicAIAssistantContext before ensureTopicAIAssistant")
	}
	contextBuilder := js[start:end]

	for _, forbidden := range []string{
		"detail.resources",
		"resources.length",
		"pushBlock('资料'",
		"title_snapshot",
		"desc_snapshot",
		"open_url",
		"暂无资料",
		"统计：资料",
	} {
		if strings.Contains(contextBuilder, forbidden) {
			t.Fatalf("topic AI assistant context should not include resource content or counts, found %q", forbidden)
		}
	}
}
