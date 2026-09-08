package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesPublicPageRendersInlineComments(t *testing.T) {
	data, err := os.ReadFile("templates/notes_public.html")
	if err != nil {
		t.Fatalf("ReadFile(notes_public.html) error = %v", err)
	}
	html := string(data)
	for _, required := range []string{
		`<meta name="csrf-token" content="{{.CSRFToken}}">`,
		`window.__SHARE_COMMENTS_ENABLED__`,
		`/static/js/share-comments.js`,
		`NotesApp.renderShareCommentsBlock`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("notes public page missing %q", required)
		}
	}

	notesJS, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	if !strings.Contains(string(notesJS), "NotesApp.renderShareCommentsBlock") {
		t.Fatalf("notes.js should expose renderShareCommentsBlock for public notes")
	}
	for _, required := range []string{
		`data-share-comments-toggle`,
		`data-comments-lazy`,
		`data-comments-hydrated`,
		`section.hidden = true`,
	} {
		if !strings.Contains(string(notesJS), required) {
			t.Fatalf("public notes comments should mount lazily, missing %q", required)
		}
	}
	if strings.Contains(string(notesJS), `section.innerHTML =
        '<div class="share-comments-head">`) {
		t.Fatal("public notes should not render a full comments form for every note")
	}
}
