package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesEmojiToolbarButtons(t *testing.T) {
	tpl, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(notes.html) error = %v", err)
	}
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	text := string(tpl) + "\n" + string(js) + "\n" + string(css)
	for _, required := range []string{
		`id="composeEmojiBtn"`,
		`id="editorEmojiBtn"`,
		`fa-regular fa-face-smile`,
		`note.compose.emoji`,
		`NotesApp.prototype._bindEmojiButtons`,
		`NotesApp.prototype._emojiCategories`,
		`NotesApp.prototype._toggleEmojiPicker`,
		`editor.mindmap.icon.common`,
		`editor.mindmap.icon.face`,
		`editor.mindmap.icon.symbol`,
		`note-emoji-tab-bar`,
		`note-emoji-grid`,
		`composer.insertAtCursor(emoji)`,
		`.note-emoji-picker`,
		`.note-emoji-tab`,
		`.note-emoji-grid`,
		`.note-emoji-item`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("notes emoji toolbar missing %q", required)
		}
	}
}
