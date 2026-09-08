package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesNoteTagInputsKeepSharedInputPadding(t *testing.T) {
	data, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	css := string(data)

	for _, selector := range []string{".compose-tag-row.tag-input-container", ".editor-tag-row.tag-input-container"} {
		if strings.Contains(css, selector) {
			t.Fatalf("%s should use shared TagInput padding and border styling", selector)
		}
	}
}
