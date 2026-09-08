package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesTagBrowserUsesSharedCompactInteractionModel(t *testing.T) {
	template := mustReadNotesTagBrowserFile(t, "templates/notes.html")
	js := mustReadNotesTagBrowserFile(t, "static/js/notes.js")
	css := mustReadNotesTagBrowserFile(t, "static/css/notes.css")

	for _, required := range []string{
		`data-note-tag-search`,
		`id="tagsSelected"`,
		`id="mobileTagsSelected"`,
		`notesApp.setAllTagGroupsExpanded(true)`,
		`notesApp.setAllTagGroupsExpanded(false)`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("notes tag browser template missing %q", required)
		}
	}

	for _, required := range []string{
		`this.tagSearchQuery = '';`,
		`this._letterExpanded = this._loadTagGroupState('notes');`,
		`return this._letterExpanded[letter] !== false;`,
		`NotesApp.prototype.setTagSearch = function(value)`,
		`NotesApp.prototype.setAllTagGroupsExpanded = function(expanded)`,
		`NotesApp.prototype.clearLabelFilter = function()`,
		`this._renderTagBrowser(container, document.getElementById('tagsSelected'), labels);`,
		`this._renderTagBrowser(container, document.getElementById('mobileTagsSelected'), labels);`,
		`aria-pressed="' + (isActive ? 'true' : 'false') + '"`,
		`escAttr(escJs(name))`,
		`label.blog_count || 0`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("notes tag browser JS missing %q", required)
		}
	}

	for _, obsolete := range []string{
		`this.tagsExpanded`,
		`_renderCollapsedTags`,
		`_renderExpandedTags`,
	} {
		if strings.Contains(js, obsolete) {
			t.Fatalf("notes tag browser should remove contradictory state %q", obsolete)
		}
	}

	for _, required := range []string{
		`.sidebar-tags-search`,
		`.sidebar-tags-selected-chip`,
		`.sidebar-tags-action`,
		`.sidebar-tags-body,`,
		`.mobile-tags-bar { display: flex; flex-wrap: wrap;`,
		`.tag-letter-group.expanded { flex-basis: 100%;`,
		`.tag-letter-group.expanded .tag-letter-body`,
		`.sidebar-tag-pill.active`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("notes tag browser CSS missing %q", required)
		}
	}
}

func TestNotesTagBrowserTranslations(t *testing.T) {
	for _, path := range []string{"i18n/zh.go", "i18n/en.go"} {
		content := mustReadNotesTagBrowserFile(t, path)
		for _, key := range []string{
			"note.tags.search",
			"note.tags.selected",
			"note.tags.clear",
			"note.tags.expand_all",
			"note.tags.collapse_all",
			"note.tags.no_match",
		} {
			if !strings.Contains(content, key) {
				t.Fatalf("%s missing translation key %q", path, key)
			}
		}
	}
}

func mustReadNotesTagBrowserFile(t *testing.T, path string) string {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile(%s) error = %v", path, err)
	}
	return string(content)
}
