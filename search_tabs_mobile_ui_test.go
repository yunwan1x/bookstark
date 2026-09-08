package main

import (
	"os"
	"strings"
	"testing"
)

func TestSearchResultTabsAreHorizontallyScrollableOnMobile(t *testing.T) {
	tpl, err := os.ReadFile("templates/search.html")
	if err != nil {
		t.Fatalf("ReadFile(search.html) error = %v", err)
	}
	css, err := os.ReadFile("static/css/search.css")
	if err != nil {
		t.Fatalf("ReadFile(search.css) error = %v", err)
	}
	js, err := os.ReadFile("static/js/search.js")
	if err != nil {
		t.Fatalf("ReadFile(search.js) error = %v", err)
	}

	tplText := string(tpl)
	if !strings.Contains(tplText, `class="search-tabs" id="search-tabs"`) {
		t.Fatalf("search result tabs container missing")
	}
	if strings.Contains(tplText, `data-swipe-nav`) {
		t.Fatalf("search result tabs should use native horizontal scrolling, not shared swipe navigation")
	}

	cssText := string(css)
	for _, required := range []string{
		".search-tabs",
		"overflow-x: auto",
		"overflow-y: hidden",
		"-webkit-overflow-scrolling: touch",
		"overscroll-behavior-x: contain",
		"flex: 0 0 auto",
		"touch-action: pan-x pan-y",
		".search-tabs::-webkit-scrollbar",
		"scrollbar-width: none",
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("search tabs mobile scrolling style missing %q", required)
		}
	}

	jsText := string(js)
	for _, required := range []string{
		"function scrollTabIntoView",
		"inline: 'center'",
		"scrollTabIntoView(activeTab, false)",
		"scrollTabIntoView(this, true)",
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("search tabs active item auto-scroll missing %q", required)
		}
	}
}

func TestGlobalSearchIncludesTopicsTabAndJumpTarget(t *testing.T) {
	tpl, err := os.ReadFile("templates/search.html")
	if err != nil {
		t.Fatalf("ReadFile(search.html) error = %v", err)
	}
	js, err := os.ReadFile("static/js/search.js")
	if err != nil {
		t.Fatalf("ReadFile(search.js) error = %v", err)
	}
	topicJS, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("ReadFile(topics.js) error = %v", err)
	}

	tplText := string(tpl)
	for _, required := range []string{
		`data-tab="topics"`,
		`id="count-topics"`,
		`search.tab.topics`,
	} {
		if !strings.Contains(tplText, required) {
			t.Fatalf("search template should expose topics tab, missing %q", required)
		}
	}

	jsText := string(js)
	for _, required := range []string{
		"'topics'",
		"var topics = data.topics || [];",
		"(counts.topics || 0)",
		"setCount('count-topics', counts.topics || 0);",
		"currentTab === 'all' || currentTab === 'topics'",
		"search.section.topics",
		"'/topics?id=' + encodeURIComponent(topic.id)",
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("search js should render and link topic results, missing %q", required)
		}
	}

	topicJSText := string(topicJS)
	for _, required := range []string{
		"this.initialTopicId",
		"params.get('id')",
		"this.selectTopic(this.selectedId",
	} {
		if !strings.Contains(topicJSText, required) {
			t.Fatalf("topics page should support /topics?id= jump target like notes, missing %q", required)
		}
	}
}
