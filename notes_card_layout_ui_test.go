package main

import (
	"os"
	"strings"
	"testing"
)

func TestNoteCardDateRendersInFooterAsDateOnly(t *testing.T) {
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}

	jsText := string(js)
	start := strings.Index(jsText, `NotesApp.renderNoteCard = function`)
	end := strings.Index(jsText, `NotesApp._buildLocationHtml = function`)
	if start < 0 || end < 0 || end <= start {
		t.Fatalf("note card renderer block missing")
	}
	noteCardJs := jsText[start:end]
	if strings.Contains(noteCardJs, `note-time note-time-head`) {
		t.Fatalf("note date should not render in the header")
	}
	for _, required := range []string{
		`var dateStr = b.create_time ? b.create_time.substring(0, 10) : '';`,
		`'<div class="note-footer">' + actions + '<span class="note-time"`,
	} {
		if !strings.Contains(noteCardJs, required) {
			t.Fatalf("note footer date-only markup missing %q", required)
		}
	}
	if strings.Contains(noteCardJs, `b.create_time.substring(0, 16).replace('T', ' ')`) {
		t.Fatalf("note card should show date only, not date time")
	}

	cssText := string(css)
	for _, required := range []string{
		".note-footer { display: flex; justify-content: space-between; align-items: center; margin-top: 8px; }",
		".note-time { font-size: 12px; color: var(--color-gray-400, #94a3b8); }",
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("note card footer date style missing %q", required)
		}
	}
}

func TestPinnedNotesUseHeaderBadgeAndArticlesUseTitleInlineBadge(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	js := string(jsBytes)
	css := string(cssBytes)

	for _, required := range []string{
		`NotesApp.noteStatePinnedBadgeHtml = function()`,
		`NotesApp.pinnedTitleBadgeHtml = function()`,
		`NotesApp._syncNoteStatePinBadge = function(header, pinned)`,
		`class="vis-badge pin-badge note-state-pin-badge"`,
		`return '<span class="vis-badge pin-badge note-state-pin-badge">📌 ' + window.__('note.badge.pinned') + '</span>';`,
		`class="topic-card-pin-badge note-title-pin-badge"`,
		`var pinnedBadge = b.is_pinned ? NotesApp.noteStatePinnedBadgeHtml() : '';`,
		`var header = '<div class="note-header">' + pinnedBadge +`,
		`'<div class="note-content">' + html + '</div>'`,
		`return '<span class="topic-card-pin-badge note-title-pin-badge"><i class="fa-solid fa-thumbtack" aria-hidden="true"></i>' + window.__('note.badge.pinned') + '</span>';`,
		`class="article-title-line"`,
		`NotesApp._syncNoteStatePinBadge(card.querySelector('.note-header'), pinned);`,
		`NotesApp._syncPinnedTextBadge(card.querySelector('.article-title-line'), pinned);`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("notes js should contain title-inline pin badge marker %q", required)
		}
	}
	if strings.Contains(js, `NotesApp.injectPinnedBadgeIntoMarkup(html, !!b.is_pinned)`) {
		t.Fatalf("note pinned badge should not render inside note markdown content")
	}
	if strings.Contains(js, `NotesApp._syncPinnedTextBadge(card.querySelector('.note-content'), pinned);`) {
		t.Fatalf("note pin toggle should update the header badge instead of note markdown content")
	}
	if strings.Contains(js, `return (opts.pinned ? '<span class="pin-badge article-state-badge">'`) {
		t.Fatalf("article pinned badge should not render in the article state badge row")
	}
	for _, required := range []string{
		".topic-card-pin-badge { display: inline-flex; align-items: center; gap: 4px; height: 20px;",
		".topic-card-pin-badge i { font-size: 10px; }",
		".note-header .note-state-pin-badge",
		".article-title-line .topic-card-pin-badge",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("notes css should contain title-inline pin badge style %q", required)
		}
	}
	if strings.Contains(js, `class="pin-badge note-title-pin-badge"`) {
		t.Fatalf("notes js should not render the old note-specific pin badge class")
	}
}

func TestNotePinnedBadgeLabelDoesNotIncludeEmoji(t *testing.T) {
	for _, path := range []string{"i18n/zh.go", "i18n/en.go"} {
		bytes, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		text := string(bytes)
		if strings.Contains(text, `"note.badge.pinned":                   "📌`) {
			t.Fatalf("%s note.badge.pinned should use plain text because the badge already renders the topic pin icon", path)
		}
	}
}
