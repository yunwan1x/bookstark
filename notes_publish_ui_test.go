package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotePublishButtonsDebounce(t *testing.T) {
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	utils, err := os.ReadFile("static/js/utils.js")
	if err != nil {
		t.Fatalf("ReadFile(utils.js) error = %v", err)
	}
	text := string(js)
	for _, required := range []string{
		"_runSubmitRequest",
		"BookStarkRequestLock.run",
		"notes:compose:create",
		"notes:editor:create",
		"notes:editor:update:",
		"notes:article:create",
		"notes:article:update:",
		"notes:note:pin:",
		"notes:note:visibility:",
		"notes:note:delete:",
		"notes:article:publish:",
		"notes:article:unpublish:",
		"notes:article:delete:",
		"notes:article:pin:",
		"notes:article:visibility:",
		"notes:share:edit-token:",
		"notes:share:reset-token:",
		"notes:share:unpublish:",
		"articleSettingSaveBtn",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("notes publish debounce missing %q", required)
		}
	}
	shared := string(utils)
	for _, required := range []string{
		"BookStarkRequestLock",
		"var locks = {}",
		"if (locks[key]) return null",
		"button.disabled = !!busy",
		"setAttribute('aria-busy'",
	} {
		if !strings.Contains(shared, required) {
			t.Fatalf("shared request lock missing %q", required)
		}
	}
}

func TestMobileEditorToolbarIsCompact(t *testing.T) {
	css, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	text := string(css)
	for _, required := range []string{
		".editor-modal-tool-row { gap: 2px; margin: -2px 0 6px; }",
		".editor-modal-tool-row .compose-btn",
		"min-width: 32px",
		".editor-modal-tool-row .editor-toolbar-submit",
		"white-space: nowrap",
		"flex: 0 0 auto",
		".compose-submit:disabled",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("mobile editor toolbar compact styles missing %q", required)
		}
	}
}
