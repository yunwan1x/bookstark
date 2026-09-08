package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicDesktopCommentsSupportCollapsedStandardAndExpandedLayouts(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/topics.html")
	if err != nil {
		t.Fatalf("read topics template: %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/topics.css")
	if err != nil {
		t.Fatalf("read topics css: %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}
	template := string(templateBytes)
	css := string(cssBytes)
	js := string(jsBytes)

	for _, required := range []string{
		`id="topicCommentCollapseBtn"`,
		`id="topicCommentExpandBtn"`,
		`id="topicCommentCollapsedBtn"`,
		`id="topicCommentCollapsedCount"`,
		`id="topicDesktopRailRestoreBtn"`,
		`aria-controls="topicCommentPanel"`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("topic comments layout controls missing %q", required)
		}
	}

	for _, required := range []string{
		`topicCommentLayout: 'standard'`,
		`initTopicCommentLayout: function()`,
		`setTopicCommentLayout: function(mode, options)`,
		`updateTopicCommentLayoutControls: function()`,
		`bookstark.topic.commentLayout`,
		`topic-comments-collapsed`,
		`topic-comments-expanded`,
		`if (this.topicCommentLayout === 'collapsed') this.setTopicCommentLayout('standard');`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topic comments layout behavior missing %q", required)
		}
	}

	for _, required := range []string{
		`@media (min-width: 1181px)`,
		`.topic-workbench.topic-comments-collapsed`,
		`grid-template-columns: minmax(280px, 320px) minmax(0, 1fr) 44px;`,
		`.topic-workbench.topic-comments-expanded`,
		`grid-template-columns: minmax(0, 1fr) clamp(480px, 38vw, 640px);`,
		`.topic-workbench.topic-comments-expanded .topic-rail`,
		`display: none;`,
		`.topic-comment-collapsed-trigger`,
		`.topic-desktop-rail-restore`,
		`.topic-comment-layout-btn,`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("topic comments responsive layout missing %q", required)
		}
	}
}
