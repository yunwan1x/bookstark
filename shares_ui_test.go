package main

import (
	"os"
	"strings"
	"testing"
)

func TestUnifiedSharesSurface(t *testing.T) {
	for name, needles := range map[string][]string{
		"templates/public_feed.html":     {`{{if .Account}}`, `/home`, `/shares?type=bookmark`, `action="/shares"`, `data-note-action="copy"`, `data-note-action="expand"`, `data-note-action="comments"`, `data-comments-lazy="1" hidden`, `data-public-action="unpublish"`, `index $.Management .ShareIdentify`, `{{if $.IsAdmin}}`, `share-note-reader`, `window.__SHARE_COMMENT_ACCOUNT__`},
		"static/js/share-note-reader.js": {`function openShareImageLightbox`, `function openShareNoteViewer`, `function copyShareNoteContent`, `sanitizeRenderedHTML(marked.parse(note.content`, `.public-note-card .sh-note-text img`, `BookStarkScrollLock`},
		"static/js/public-feed.js":       {`sanitizeRenderedHTML(marked.parse(note.content))`, `BookStarkShareComments.toggle`, `BSDialog.confirm2`, `csrfFetch`, `btn.disabled = true`, `positionKey`},
		"static/css/public-feed.css":     {`@media (max-width: 640px)`, `flex-wrap: nowrap`, `.public-info { display: none; }`, `.public-note-actions`, `color: var(--color-text)`},
	} {
		data, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		for _, needle := range needles {
			if !strings.Contains(string(data), needle) {
				t.Fatalf("%s missing %s", name, needle)
			}
		}
	}
	if _, err := os.Stat("templates/shares.html"); !os.IsNotExist(err) {
		t.Fatal("legacy signed-in share template must be removed")
	}
}

func TestPublicPinnedBadgePlacement(t *testing.T) {
	tmpl, err := os.ReadFile("templates/public_feed.html")
	if err != nil {
		t.Fatal(err)
	}
	heading := strings.Index(string(tmpl), `<div class="public-entry-heading">`)
	if heading < 0 {
		t.Fatal("missing entry heading")
	}
	rest := string(tmpl)[heading:]
	if strings.Index(rest, `class="tag-badge public-pinned"`) > strings.Index(rest, "<h2>") {
		t.Fatal("pinned badge must precede title")
	}
	if strings.Contains(string(tmpl)[strings.Index(string(tmpl), `<div class="public-meta">`):], `class="tag-badge public-pinned"`) {
		t.Fatal("pinned badge must not appear on a separate footer row")
	}
	css, err := os.ReadFile("static/css/public-feed.css")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(css), `.public-pinned { display: inline-flex; align-items: center;`) {
		t.Fatal("pinned icon and label must be centered")
	}
}
