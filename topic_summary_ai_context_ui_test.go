package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicSummaryAIDefaultContextComesFromEditorSelectionOrContent(t *testing.T) {
	data, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("ReadFile(topics.js) error = %v", err)
	}
	js := string(data)

	for _, required := range []string{
		"getTopicSummaryAIContextFromEditor: function()",
		"if (range && range.from !== range.to) return value.substring(range.from, range.to).trim();",
		"this.topicSummaryAIContextText = this.getTopicSummaryAIContextFromEditor();",
		"var context = (this.topicSummaryAIContextText || '').trim();",
		"var contextTitle = this.topicSummaryAIActiveKind === 'comment' ? '评论上下文' : '小结上下文';",
		"var userMsg = context ? '【' + contextTitle + '】\\n' + context +",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topics.js missing %q", required)
		}
	}

	if strings.Contains(js, "this.topicSummaryAIContextText = this.topicSummaryAIContext();") {
		t.Fatalf("topic summary AI should not default to full topic context")
	}
}
