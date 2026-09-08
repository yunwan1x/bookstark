package main

import (
	"os"
	"strings"
	"testing"
)

func TestEditorEmojiToolbarUsesComplexPicker(t *testing.T) {
	js, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("ReadFile(editor-common.js) error = %v", err)
	}
	editor, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	text := string(js) + "\n" + string(editor) + "\n" + string(css)
	for _, required := range []string{
		"installEditorEmojiToolbar",
		"editor-emoji-toolbar-btn",
		"editor-emoji-picker",
		"editor-emoji-tab-bar",
		"editor-emoji-grid",
		"editor-emoji-item",
		"editor.mindmap.icon.common",
		"editor.mindmap.icon.face",
		"editor.mindmap.icon.symbol",
		"window.__insertEditorText",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("editor emoji toolbar missing %q", required)
		}
	}
}
