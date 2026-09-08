package main

import (
	"os"
	"strings"
	"testing"
)

func TestTrashPageIncludesTopicRecycleTab(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/trash.html")
	if err != nil {
		t.Fatalf("read trash template: %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/trash.js")
	if err != nil {
		t.Fatalf("read trash js: %v", err)
	}
	zhBytes, err := os.ReadFile("i18n/zh.go")
	if err != nil {
		t.Fatalf("read zh i18n: %v", err)
	}
	enBytes, err := os.ReadFile("i18n/en.go")
	if err != nil {
		t.Fatalf("read en i18n: %v", err)
	}
	combined := string(templateBytes) + string(jsBytes) + string(zhBytes) + string(enBytes)

	for _, required := range []string{
		`.trash-type-topic`,
		`[data-theme="dark"] .trash-type-topic`,
		`data-type="topic" onclick="switchType(this, 'topic')"`,
		`{{call .T "trash.filter.topic"}}`,
		`topic: tr('trash.type.topic', '专题')`,
		`topic: 'fa-folder-tree'`,
		`['all', 'book', 'blog', 'bookmark', 'document', 'task', 'topic']`,
		`"trash.filter.topic"`,
		`"trash.type.topic"`,
	} {
		if !strings.Contains(combined, required) {
			t.Fatalf("trash topic recycle tab missing %q", required)
		}
	}
}
