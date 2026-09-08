package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileModalsUseVisualViewportHeightAndHiddenScrollbars(t *testing.T) {
	checks := map[string][]string{
		"static/js/mobile-ui.js": {
			"function syncVisualViewportHeight()",
			"window.visualViewport",
			"document.documentElement.style.setProperty('--bs-vvh'",
			"visualViewport.addEventListener('resize', syncVisualViewportHeight)",
			"visualViewport.addEventListener('scroll', syncVisualViewportHeight)",
		},
		"templates/base.html": {
			"max-height: calc(var(--bs-vvh, 100dvh) - 8px) !important",
			"scrollbar-width: none",
			".bs-dialog-box::-webkit-scrollbar",
		},
		"static/css/notes.css": {
			"max-height: calc(var(--bs-vvh, 100dvh) - 8px)",
			".editor-modal::-webkit-scrollbar",
			".editor-modal-body::-webkit-scrollbar",
		},
		"templates/index.html": {
			`class="book-modal-overlay asset-modal-backdrop"`,
			`class="book-modal asset-modal"`,
		},
		"static/css/editor.css": {
			".tag-popover::-webkit-scrollbar",
			".share-popover::-webkit-scrollbar",
		},
		"static/css/components.css": {
			"max-height: calc(var(--bs-vvh, 100dvh) - 8px)",
			".asset-modal::-webkit-scrollbar",
			".ai-dlg-body::-webkit-scrollbar",
		},
		"templates/labels.html": {
			".mobile-strategy-content::-webkit-scrollbar",
		},
	}
	for path, needles := range checks {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		text := string(data)
		for _, needle := range needles {
			if !strings.Contains(text, needle) {
				t.Fatalf("%s missing mobile viewport modal marker %q", path, needle)
			}
		}
	}
}

func TestMobileNoteEditorUsesBalancedComposerHeight(t *testing.T) {
	checks := map[string][]string{
		"static/js/notes.js": {
			"var isMobileEditor = window.matchMedia && window.matchMedia('(max-width: 640px)').matches;",
			"minHeight: isMobileEditor ? 270 : 320",
		},
		"static/css/notes.css": {
			"#editorOverlay .editor-modal-body .md-composer-host-full { min-height: 270px; }",
			"#editorOverlay .editor-modal-body .md-composer-fallback { min-height: 270px; }",
			"#editorOverlay .editor-modal-body .cm-scroller { min-height: 270px !important; }",
		},
		"static/css/tasks.css": {
			"#taskComposeOverlay .editor-modal",
			"max-height: calc(var(--bs-vvh, 100dvh) - 8px)",
		},
	}
	for path, needles := range checks {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		text := string(data)
		for _, needle := range needles {
			if !strings.Contains(text, needle) {
				t.Fatalf("%s missing compact mobile note editor marker %q", path, needle)
			}
		}
	}
}

func TestKnowledgeModalsReuseAssetModalClasses(t *testing.T) {
	checks := map[string][]string{
		"templates/notes.html": {
			`id="taskComposeOverlay"`,
			`class="editor-overlay asset-modal-backdrop"`,
			`data-mobile-sheet-panel=".asset-modal"`,
			`class="editor-modal asset-modal asset-modal-wide"`,
			`class="editor-modal-header editor-modal-header-compact asset-modal-head"`,
			`class="editor-modal-body asset-modal-body notes-drop-zone"`,
			`id="editorOverlay"`,
			`id="articleSettingOverlay"`,
			`class="editor-modal asset-modal article-setting-modal"`,
			`class="editor-modal-footer asset-modal-foot"`,
		},
		"templates/index.html": {
			`id="bookModalOverlay"`,
			`class="book-modal-overlay asset-modal-backdrop"`,
			`data-mobile-sheet-panel=".asset-modal"`,
			`class="book-modal asset-modal"`,
			`class="book-modal-header asset-modal-head"`,
			`class="book-modal-body asset-modal-body"`,
			`class="book-modal-footer asset-modal-foot"`,
		},
		"static/css/components.css": {
			"/* ===== Shared asset-style modal ===== */",
			".asset-modal-backdrop.open,",
			".asset-modal-backdrop.active",
			"grid-template-columns: minmax(0, 1fr)",
			".asset-modal-wide",
			".asset-modal-head",
			".asset-modal-body",
			".asset-modal-foot",
		},
		"static/js/notes.js": {
			"document.querySelector('#editorOverlay .asset-modal')",
			"document.querySelector('#articleSettingOverlay .asset-modal')",
			"document.querySelector('#editorOverlay .asset-modal-body')",
		},
		"static/js/tasks.js": {
			"document.querySelector('#taskComposeOverlay .asset-modal')",
		},
	}
	for path, needles := range checks {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		text := string(data)
		for _, needle := range needles {
			if !strings.Contains(text, needle) {
				t.Fatalf("%s missing shared asset modal marker %q", path, needle)
			}
		}
	}
}

func TestDesktopModalBackdropClicksDoNotDismiss(t *testing.T) {
	data, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	text := string(data)
	for _, needle := range []string{
		"function isDesktopModalViewport()",
		"window.matchMedia('(max-width: 768px)')",
		"function isModalBackdropClick(target)",
		".asset-modal-backdrop, .editor-overlay, .book-modal-overlay, .bs-dialog-form-overlay",
		"document.addEventListener('click', function(e) {",
		"if (!isDesktopModalViewport()) return;",
		"if (!isModalBackdropClick(e.target)) return;",
		"e.stopImmediatePropagation();",
		"}, true);",
	} {
		if !strings.Contains(text, needle) {
			t.Fatalf("base template missing desktop modal backdrop guard marker %q", needle)
		}
	}
}
