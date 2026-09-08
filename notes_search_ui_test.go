package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesSearchInputUsesSpecificId(t *testing.T) {
	tpl, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(notes.html) error = %v", err)
	}
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}

	if !strings.Contains(string(tpl), `id="noteSearchInput"`) {
		t.Fatalf("notes search input should use noteSearchInput")
	}
	for _, required := range []string{
		`type="text" class="search-input" id="noteSearchInput"`,
		`autocomplete="off"`,
		`data-form-type="other"`,
		`data-lpignore="true"`,
		`data-1p-ignore="true"`,
		`data-bwignore="true"`,
		`data-dashlane-disabled="true"`,
		`data-protonpass-ignore="true"`,
		`data-keeper-ignore="true"`,
		`data-autofill-shield="true"`,
		`readonly`,
	} {
		if !strings.Contains(string(tpl), required) {
			t.Fatalf("notes search input should match task non-credential guard, missing %q", required)
		}
	}
	if strings.Contains(string(tpl), `id="searchInput"`) {
		t.Fatalf("notes search input should not use generic searchInput id")
	}
	if !strings.Contains(string(js), `getElementById('noteSearchInput')`) {
		t.Fatalf("notes.js should bind noteSearchInput")
	}
	for _, required := range []string{
		"_installSearchAutofillShield(searchInput)",
		"__bookstarkAutofillShield",
		"data-autofill-shield",
		"input.setAttribute('readonly', 'readonly')",
		"input.removeAttribute('readonly')",
		"document.activeElement === input",
		"pointerdown",
		"touchstart",
		"blur",
		"focusout",
		"relockWhenOutside",
		"document.addEventListener('focusin'",
		"document.addEventListener('pointerdown'",
	} {
		if !strings.Contains(string(js), required) {
			t.Fatalf("notes search autofill shield missing %q", required)
		}
	}
	if strings.Contains(string(js), `getElementById('searchInput')`) {
		t.Fatalf("notes.js should not bind generic searchInput")
	}
}

func TestNotesTabLoadsWhenReturningFromArticles(t *testing.T) {
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	text := string(js)
	for _, required := range []string{
		"this._notesLoaded = false",
		"} else if (tab === 'notes' && !this._notesLoaded) {",
		"this.loadNotes();",
		"self._notesLoaded = true;",
		"_renderNotesLoadError",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("notes tab first-load guard missing %q", required)
		}
	}
}

func TestNoteTagBadgesCanFilterAndSidebarUsesSearchableLetterGroups(t *testing.T) {
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	jsText := string(js)
	for _, required := range []string{
		`tag-badge tag-badge-clickable`,
		`notesApp.selectLabel`,
		`data-label="`,
		`event.stopPropagation();notesApp.removeBlogLabel`,
		`this._filterTagLabels(labels)`,
		`this._groupTagLabels(filtered)`,
		`this._isTagGroupExpanded(letter)`,
		`NotesApp.prototype.setTagSearch = function(value)`,
		`NotesApp.prototype.setAllTagGroupsExpanded = function(expanded)`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("notes tag UI missing %q", required)
		}
	}
	if !strings.Contains(string(css), `.tag-badge-remove {`) || !strings.Contains(string(css), `margin-left: 4px;`) {
		t.Fatalf("note tag remove button should keep visual space from label text")
	}
}

func TestNotesCodeFilterChipWiresHasCodeQuery(t *testing.T) {
	tpl, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(notes.html) error = %v", err)
	}
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}

	tplText := string(tpl)
	for _, required := range []string{
		`id="chipCode"`,
		`notesApp.toggleCodeFilter()`,
		`note.filter.code`,
	} {
		if !strings.Contains(tplText, required) {
			t.Fatalf("notes code filter template missing %q", required)
		}
	}

	jsText := string(js)
	for _, required := range []string{
		`this.filterCode = false;`,
		`NotesApp.prototype.toggleCodeFilter = function()`,
		`var chipCode = document.getElementById('chipCode');`,
		`chipCode.classList.toggle('active', !!this.filterCode);`,
		`params.set('has_code', '1');`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("notes code filter script missing %q", required)
		}
	}
}

func TestNoteItemFullscreenViewerUI(t *testing.T) {
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

	tplText := string(tpl)
	for _, required := range []string{
		`id="noteViewerOverlay"`,
		`class="editor-overlay note-viewer-overlay"`,
		`id="noteViewerContent"`,
		`id="noteViewerCopyBtn"`,
		`id="noteViewerEditBtn"`,
		`id="noteViewerPrevBtn"`,
		`id="noteViewerNextBtn"`,
		`id="noteViewerMeta"`,
		`class="note-viewer-shell"`,
		`class="note-viewer-panel"`,
		`notesApp.closeNoteViewer()`,
		`note.viewer.title`,
		`note.viewer.previous`,
		`note.viewer.next`,
	} {
		if !strings.Contains(tplText, required) {
			t.Fatalf("note viewer template missing %q", required)
		}
	}

	jsText := string(js)
	for _, required := range []string{
		`class="note-fullscreen-btn"`,
		`notesApp.openNoteViewer(`,
		`NotesApp.prototype.openNoteViewer = function(id, options)`,
		`fetch('/api/blogs/' + id`,
		`marked.parse(text)`,
		`BookStarkScrollLock.lock('notes-viewer-modal')`,
		`NotesApp.prototype.closeNoteViewer = function()`,
		`NotesApp.prototype.copyNoteViewerContent = function()`,
		`NotesApp.prototype.editNoteFromViewer = function()`,
		`NotesApp.prototype._getNoteViewerIds = function()`,
		`NotesApp.prototype.showAdjacentNoteViewer = function(delta)`,
		`e.key === 'ArrowLeft'`,
		`e.key === 'ArrowRight'`,
		`#noteViewerOverlay .note-viewer-shell`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("note viewer script missing %q", required)
		}
	}

	cssText := string(css)
	for _, required := range []string{
		`.note-fullscreen-btn`,
		`.note-viewer-overlay`,
		`background: rgba(2, 6, 23, 0.86);`,
		`.note-viewer-shell`,
		`.note-viewer-panel`,
		`.note-viewer-topbar`,
		`.note-viewer-nav`,
		`.note-viewer-icon-btn`,
		`.note-viewer-content`,
		`height: var(--bs-vvh, 100dvh);`,
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("note viewer style missing %q", required)
		}
	}
}
