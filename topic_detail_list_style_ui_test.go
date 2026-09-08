package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicDetailListsReuseNotesAndTasksVisualStyles(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/topics.html")
	if err != nil {
		t.Fatalf("read topics template: %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/topics.css")
	if err != nil {
		t.Fatalf("read topics css: %v", err)
	}

	template := string(templateBytes)
	js := string(jsBytes)
	css := string(cssBytes)

	for _, required := range []string{
		`/static/css/tasks.css`,
		`id="topicSummariesList" class="topic-items-list topic-summary-list"`,
		`id="topicActionsList" class="tasks-list topic-actions-list"`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("topics template should use shared list container style %q", required)
		}
	}

	for _, required := range []string{
		`note-card topic-summary-card`,
		`note-content`,
		`note-footer`,
		`note-actions`,
		`row-action`,
		`note-time`,
		`task-row topic-task-row`,
		`task-tools`,
		`topic-task-main`,
		`task-icon-btn task-check-btn`,
		`task-body`,
		`task-content note-content`,
		`task-meta`,
		`task-pill`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topics js should render shared notes/tasks style fragment %q", required)
		}
	}

	for _, forbidden := range []string{
		`.topic-summary-row {`,
		`.topic-action-row {`,
		`.topic-action-check {`,
		`'<span class="vis-badge">' + html(typeLabel) + '</span>'`,
		`'<span class="vis-badge">AI</span>'`,
		`'<em>AI</em>'`,
		`  .topic-summary-card .note-content {
    display: -webkit-box;`,
		`-webkit-line-clamp: 4;`,
		`.topic-summary-card .note-header`,
	} {
		if strings.Contains(css, forbidden) || strings.Contains(js, forbidden) {
			t.Fatalf("topic detail lists should not keep cropped content or manual summary badges %q", forbidden)
		}
	}
}
