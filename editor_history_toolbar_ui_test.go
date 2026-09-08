package main

import (
	"os"
	"strings"
	"testing"
)

func TestCherryHistoryToolbarFallback(t *testing.T) {
	js, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("ReadFile(editor-common.js) error = %v", err)
	}
	src := string(js)
	required := []string{
		"function installCherryHistoryToolbarFallback(instance)",
		".cherry-toolbar-undo, .cherry-toolbar-redo",
		"runCherryHistoryCommand(instance, action)",
		"instance.editor.defaultKeymap",
		"installCherryHistoryToolbarFallback(instance)",
	}
	for _, want := range required {
		if !strings.Contains(src, want) {
			t.Fatalf("editor history toolbar fallback missing %q", want)
		}
	}
}
