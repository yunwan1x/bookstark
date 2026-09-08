package main

import (
	"os"
	"strings"
	"testing"
)

func TestDarkMarkdownEditorBackgroundMatchesPreviewer(t *testing.T) {
	cssBytes, err := os.ReadFile("static/css/cherry-theme-dark.css")
	if err != nil {
		t.Fatalf("ReadFile(cherry-theme-dark.css) error = %v", err)
	}
	css := string(cssBytes)
	for _, required := range []string{
		"--base-editor-bg: #0f172a;",
		"--base-previewer-bg: #0f172a;",
		".cherry.theme__dark .cherry-editor {\n  background-color: #0f172a;",
		".cherry.theme__dark .cm-editor {\n  background-color: #0f172a;",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("dark markdown editor theme missing %q", required)
		}
	}
}
