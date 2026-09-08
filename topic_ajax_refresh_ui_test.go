package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicInitialRenderShowsSkeletonBeforeData(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/topics.html")
	if err != nil {
		t.Fatalf("read topics template: %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}
	template := string(templateBytes)
	js := string(jsBytes)

	for _, required := range []string{
		`id="topicOverviewTitle" class="topic-overview-title"><span class="topic-skeleton-block topic-overview-title-skeleton"></span>`,
		`class="topic-overview-stat topic-overview-stat-resources topic-overview-stat-skeleton" disabled aria-hidden="true"`,
		`class="topic-skeleton-block topic-overview-stat-icon-skeleton"`,
		`class="topic-skeleton-block topic-overview-stat-title-skeleton"`,
		`class="topic-skeleton-block topic-overview-stat-caption-skeleton"`,
		`id="topicOverviewUpdatedAt"><span class="topic-skeleton-block topic-overview-updated-skeleton"></span>`,
		`renderTopicOverviewSkeleton: function()`,
		`renderTopicOverviewStatSkeletonCards: function()`,
		`this.renderTopicListSkeleton();`,
		`this.renderTopicDetailSkeleton();`,
	} {
		if !strings.Contains(template+js, required) {
			t.Fatalf("topic initial render should skeletonize detail before async data, missing %q", required)
		}
	}
	if strings.Contains(template, `id="topicOverviewResourcesCount"`) ||
		strings.Contains(template, `data-topic-stat-tab="resources"`) ||
		strings.Contains(template, `id="topicOverviewUpdatedAt">-</span>`) {
		t.Fatalf("topic overview should not paint fake detail values before async data returns")
	}

	initIndex := strings.Index(js, `init: function()`)
	skeletonIndex := strings.Index(js, `this.renderTopicDetailSkeleton();`)
	switchIndex := strings.Index(js, `this.switchDetailTab(this.activeDetailTab);`)
	loadIndex := strings.Index(js, `this.loadTopics(`)
	if initIndex < 0 || skeletonIndex < initIndex || switchIndex < skeletonIndex || loadIndex < switchIndex {
		t.Fatalf("topic init should render skeletons before switching tabs and loading data")
	}
}

func TestTopicMutationsRefreshAjaxWithoutReloadingWholeList(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}
	js := string(jsBytes)

	for _, required := range []string{
		`refreshSelectedTopic: async function(options)`,
		`syncSelectedTopicListItemFromDetail: function()`,
		`upsertTopicListItem: function(topic, options)`,
		`removeTopicListItem: function(topicId)`,
		`this.refreshSelectedTopic({ silent: true`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topic mutations should refresh the active topic via Ajax, missing %q", required)
		}
	}

	for _, method := range []string{
		"saveTopic",
		"toggleTopicPin",
		"deleteResource",
		"saveInlineSummary",
		"deleteSummary",
		"saveTask",
		"updateTaskDueDate",
		"deleteTask",
		"toggleTaskDone",
	} {
		body := extractJSMethodBody(t, js, method+": async function")
		if strings.Contains(body, `loadTopics()`) {
			t.Fatalf("%s should not reload the whole topic list after a mutation", method)
		}
	}
}

func extractJSMethodBody(t *testing.T, js, signature string) string {
	t.Helper()
	start := strings.Index(js, signature)
	if start < 0 {
		t.Fatalf("missing JS method %q", signature)
	}
	brace := strings.Index(js[start:], "{")
	if brace < 0 {
		t.Fatalf("missing body for JS method %q", signature)
	}
	pos := start + brace
	depth := 0
	for i := pos; i < len(js); i++ {
		switch js[i] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return js[pos : i+1]
			}
		}
	}
	t.Fatalf("unterminated JS method %q", signature)
	return ""
}
