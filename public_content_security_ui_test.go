package main

import (
	"os"
	"strings"
	"testing"
)

func TestPublicMarkdownRenderingUsesSharedSanitizer(t *testing.T) {
	utilsData, err := os.ReadFile("static/js/utils.js")
	if err != nil {
		t.Fatalf("ReadFile(utils.js): %v", err)
	}
	utils := string(utilsData)
	for _, required := range []string{
		"function sanitizeRenderedHTML(html)",
		"window.sanitizeRenderedHTML = sanitizeRenderedHTML",
		"element.removeAttribute(attribute.name)",
		"'noopener noreferrer'",
	} {
		if !strings.Contains(utils, required) {
			t.Fatalf("shared Markdown sanitizer missing %q", required)
		}
	}

	sharesData, err := os.ReadFile("templates/shares.html")
	if err != nil {
		t.Fatalf("ReadFile(shares.html): %v", err)
	}
	shares := string(sharesData)
	if got := strings.Count(shares, "marked.parse("); got != 2 {
		t.Fatalf("shares.html marked.parse call count = %d; update this test when adding a render path", got)
	}
	if got := strings.Count(shares, "sanitizeRenderedHTML(marked.parse("); got != 2 {
		t.Fatalf("shares.html has %d sanitized Markdown render paths; want 2", got)
	}
}

func TestPublicNoteCardsDoNotDependOnPrivateNotesAppInstance(t *testing.T) {
	notesData, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js): %v", err)
	}
	notes := string(notesData)
	for _, required := range []string{
		"var isInteractive = showActions !== false;",
		"isInteractive ?",
		"NotesApp._buildReadonlyTagBadgesHtml",
		"sanitizeRenderedHTML(marked.parse(text))",
	} {
		if !strings.Contains(notes, required) {
			t.Fatalf("read-only public note rendering missing %q", required)
		}
	}

	publicData, err := os.ReadFile("templates/notes_public.html")
	if err != nil {
		t.Fatalf("ReadFile(notes_public.html): %v", err)
	}
	publicPage := string(publicData)
	if !strings.Contains(publicPage, "NotesApp.renderNoteCard(b, false)") {
		t.Fatal("public notes page must request read-only note cards")
	}
	if strings.Contains(publicPage, "notesApp.") {
		t.Fatal("public notes page must not call the private notesApp instance")
	}
}
