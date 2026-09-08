package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileListItemsUseSingleBottomDivider(t *testing.T) {
	notesBytes, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	tasksBytes, err := os.ReadFile("static/css/tasks.css")
	if err != nil {
		t.Fatalf("ReadFile(tasks.css) error = %v", err)
	}
	topicsBytes, err := os.ReadFile("static/css/topics.css")
	if err != nil {
		t.Fatalf("ReadFile(topics.css) error = %v", err)
	}

	notesCSS := string(notesBytes)
	for _, expected := range []string{
		".note-card { border: 0; border-bottom: 1px solid var(--color-gray-100, #f1f5f9); border-radius: 0;",
		".article-card { border: 0; border-bottom: 1px solid var(--color-gray-100, #f1f5f9); border-radius: 0;",
	} {
		if !strings.Contains(notesCSS, expected) {
			t.Fatalf("mobile notes list item should use one bottom divider, missing %q", expected)
		}
	}

	tasksCSS := string(tasksBytes)
	if !strings.Contains(tasksCSS, ".task-row {\n        border: 0;\n        border-bottom: 1px solid var(--color-gray-100, #f1f5f9);\n        border-radius: 0;") {
		t.Fatalf("mobile task rows should use one bottom divider")
	}

	topicsCSS := string(topicsBytes)
	if strings.Contains(topicsCSS, ".topic-resource-content-item {\n  padding-left: 8px;\n  border-bottom:") {
		t.Fatalf("topic resource rows should use the shared compact row bottom divider only")
	}
}
