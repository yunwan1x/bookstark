package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileModalsOpenFromTop(t *testing.T) {
	checks := map[string][]string{
		"static/css/notes.css": {
			`.editor-overlay.active,`,
			`.editor-overlay.bs-mobile-sheet-root.active { align-items: flex-start; overflow-y: auto; }`,
			`animation: editor-slide-down 0.2s ease-out;`,
			`content: none;`,
		},
		"static/css/components.css": {
			`.asset-modal-backdrop.open,`,
			`.asset-modal-backdrop.active`,
			`place-items: start center;`,
			`border-radius: 0 0 var(--radius-xl) var(--radius-xl);`,
			`animation: asset-slide-down .2s ease-out;`,
		},
		"static/css/editor.css": {
			`top: 0; right: 0; bottom: auto; left: 0;`,
			`transform: translateY(-100%);`,
			`box-shadow: 0 4px 24px rgba(0,0,0,0.16);`,
		},
		"templates/base.html": {
			`.bs-dialog-form-overlay.active { align-items: flex-start; }`,
			`animation: bs-dialog-slide-down 0.2s ease-out;`,
		},
		"templates/notes.html": {
			`id="taskComposeOverlay" role="dialog" aria-modal="true" aria-labelledby="taskComposeModalTitle" data-mobile-sheet`,
			`id="editorOverlay" role="dialog" aria-modal="true" aria-labelledby="editorModalTitle" data-mobile-sheet`,
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
				t.Fatalf("%s missing mobile top-sheet marker %q", path, needle)
			}
		}
	}
}

func TestMobileSheetsDoNotCloseByDragging(t *testing.T) {
	data, err := os.ReadFile("static/js/mobile-ui.js")
	if err != nil {
		t.Fatalf("ReadFile(static/js/mobile-ui.js) error = %v", err)
	}
	text := string(data)
	for _, forbidden := range []string{
		"data-mobile-sheet-origin",
		"data-sheet-drag-ignore",
		"dy >= 92",
		"panel.style.transform = 'translateY('",
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("mobile sheet drag-close marker should not exist: %q", forbidden)
		}
	}
}

func TestMobileTaskComposeDueDateLivesInHeader(t *testing.T) {
	cssData, err := os.ReadFile("static/css/tasks.css")
	if err != nil {
		t.Fatalf("ReadFile(static/css/tasks.css) error = %v", err)
	}
	tplData, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(templates/notes.html) error = %v", err)
	}

	css := string(cssData)
	for _, required := range []string{
		"#taskComposeOverlay .editor-modal {",
		"position: relative;",
		"#taskComposeOverlay .editor-modal-header",
		"#taskComposeOverlay .editor-modal-body.notes-drop-zone",
		"position: static;",
		"#taskComposeModalTitle",
		"max-width: calc(50% - 96px);",
		"#taskComposeOverlay .task-modal-date",
		"position: absolute;",
		"top: 12px;",
		"left: 50%;",
		"transform: translateX(-50%);",
		"width: 160px;",
		"background: transparent;",
		"border: 0;",
		"box-shadow: none;",
		"#taskComposeOverlay .task-modal-date input",
		"width: 112px;",
		"font-variant-numeric: tabular-nums;",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("mobile task compose due date header style missing %q", required)
		}
	}

	tpl := string(tplData)
	for _, required := range []string{
		`id="taskComposeModalTitle"`,
		`class="task-compose-date task-modal-date"`,
		`id="taskModalDueDate"`,
	} {
		if !strings.Contains(tpl, required) {
			t.Fatalf("task compose modal due date template missing %q", required)
		}
	}
}
