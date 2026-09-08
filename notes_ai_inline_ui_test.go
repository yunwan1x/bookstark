package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesInlineAIContract(t *testing.T) {
	notesJS, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	composerJS, err := os.ReadFile("static/js/markdown-composer.js")
	if err != nil {
		t.Fatalf("ReadFile(markdown-composer.js) error = %v", err)
	}
	notesCSS, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}

	for _, required := range []string{
		"_initFloatingAI",
		"_bindComposerFloatingAI",
		"_openInlineAIPrompt",
		"_runInlineAI",
		"note-ai-popover",
		"note-ai-popover-expand",
		"note-ai-quick-actions",
		"textarea class=\"note-ai-prompt\"",
		"note-ai-go-inline",
		"note-ai-footer",
		"note-ai-cancel",
		"ai-dlg-btn ai-dlg-btn-cancel",
		"ai-dlg-btn ai-dlg-btn-go",
		"_toggleInlineAIExpanded",
		"_setInlineAIExpanded",
		"_makeInlineAIDraggable",
		"_resetInlineAIPosition",
		"popover.classList.toggle('is-expanded'",
		"popover.classList.add('is-dragged')",
		"prompt.setAttribute('rows', expanded ? '6' : '1')",
		"header.setPointerCapture(e.pointerId)",
		"popover.style.setProperty('left', pos.left + 'px', 'important')",
		"fa-compress",
		"美化格式",
		"美化这段笔记的 Markdown 格式",
		"selectRange(range.from, range.to)",
		"AIHelper.complete",
		"replaceRange(range.from, range.to, '')",
		"composer.replaceRange(insertedEnd, insertedEnd, chunk)",
		"_noteDraftKey",
		"this.memberID",
		"new-note-draft:v1:",
		"_restoreComposeDraft",
		"_saveComposeDraftFrom",
		"clearComposeDraft",
		"localStorage.setItem",
		"localStorage.removeItem",
	} {
		if !strings.Contains(string(notesJS), required) {
			t.Fatalf("notes inline AI script missing %q", required)
		}
	}

	for _, required := range []string{
		"getSelectionRange",
		"getSelectedText",
		"selectRange",
		"replaceRange",
		"getRangeRect",
		"_textareaCaretRect",
		"coordsAtPos",
	} {
		if !strings.Contains(string(composerJS), required) {
			t.Fatalf("MarkdownComposer inline AI API missing %q", required)
		}
	}

	for _, required := range []string{
		".note-ai-popover",
		".note-ai-popover.is-expanded",
		".note-ai-popover.is-dragged",
		".note-ai-popover-dragging",
		".note-ai-popover.is-open.is-expanded",
		"flex-direction: column;",
		".note-ai-popover-actions",
		".note-ai-popover-expand",
		".note-ai-prompt",
		".note-ai-popover.is-expanded .note-ai-quick-actions",
		"order: 1;",
		".note-ai-popover.is-expanded .note-ai-prompt",
		".note-ai-popover.is-expanded .note-ai-input-row",
		".note-ai-popover.is-expanded .note-ai-footer",
		".note-ai-popover.is-expanded .note-ai-go-inline",
		".note-ai-quick-actions",
		".note-ai-status:empty",
		".note-ai-status.is-streaming",
		"note-ai-pulse",
	} {
		if !strings.Contains(string(notesCSS), required) {
			t.Fatalf("notes inline AI style missing %q", required)
		}
	}
	if strings.Contains(string(notesJS)+"\n"+string(notesCSS), "note-ai-selection-menu") {
		t.Fatalf("notes inline AI should not show selection quick menu anymore")
	}

	notesHTML, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(notes.html) error = %v", err)
	}
	for _, required := range []string{
		"id=\"composeClearBtn\"",
		"id=\"editorClearBtn\"",
		"notesApp.clearComposeDraft()",
		"note.compose.clear",
		"memberID: {{.MemberID}}",
	} {
		if !strings.Contains(string(notesHTML), required) {
			t.Fatalf("notes draft clear UI missing %q", required)
		}
	}
}

func TestNotesInlineAIMobileUsesTopPopoverPanel(t *testing.T) {
	notesJS, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	notesCSS, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	js := string(notesJS)
	css := string(notesCSS)

	for _, required := range []string{
		"_isSmallAIViewport",
		"_syncAIMobileViewport",
		"window.visualViewport",
		"--note-ai-vv-top",
		"note-ai-mobile-open",
		"top: calc(var(--note-ai-vv-top",
		"bottom: auto !important;",
		"note-ai-slide-down",
		".note-ai-input-row",
		"grid-template-columns: 1fr;",
		".note-ai-popover.is-expanded",
		"height: min(34vh, 240px);",
	} {
		if !strings.Contains(js+"\n"+css, required) {
			t.Fatalf("notes inline AI mobile top popover panel missing %q", required)
		}
	}
	if strings.Contains(css, "--note-ai-vv-bottom") || strings.Contains(css, "note-ai-slide-up") {
		t.Fatalf("notes inline AI mobile should use top popover panel, found old bottom-sheet markers")
	}
}

func TestNotesInlineAILocksPageScroll(t *testing.T) {
	notesJS, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	text := string(notesJS)

	for _, required := range []string{
		"_lockInlineAIScroll",
		"_unlockInlineAIScroll",
		"BookStarkScrollLock.lock('notes-inline-ai')",
		"BookStarkScrollLock.unlock('notes-inline-ai')",
		"this._lockInlineAIScroll();",
		"this._unlockInlineAIScroll();",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("notes inline AI scroll lock missing %q", required)
		}
	}
}
