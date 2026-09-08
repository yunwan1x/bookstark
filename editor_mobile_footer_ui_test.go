package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileEditorFooterStaysInViewport(t *testing.T) {
	tpl, err := os.ReadFile("templates/editor.html")
	if err != nil {
		t.Fatalf("ReadFile(editor.html) error = %v", err)
	}
	common, err := os.ReadFile("templates/editor_common.html")
	if err != nil {
		t.Fatalf("ReadFile(editor_common.html) error = %v", err)
	}
	css, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}

	for _, required := range []string{
		"editor-shell",
		"editor-main",
		"id=\"editorStatusbar\"",
		"editor-statusbar",
		"id=\"statusbar-doc-title\"",
		"statusbar-word-count",
		"statusbar-modify-time",
	} {
		if !strings.Contains(string(tpl), required) {
			t.Fatalf("editor template missing mobile footer guard %q", required)
		}
	}
	if !strings.Contains(string(common), "var(--editor-viewport-height, 100dvh)") {
		t.Fatalf("editor height should use visual viewport CSS variable")
	}
	for _, required := range []string{
		".editor-shell",
		"min-height: 0",
		".editor-statusbar",
		"flex: 0 0 1.5rem",
		".statusbar-doc-title",
		".statusbar-path-sheet",
		".breadcrumb { display: none; }",
		".statusbar-char-sep",
		".statusbar-word-count",
		".statusbar-modify-sep",
		".statusbar-modify-time",
		".content-pager { min-height: 0; }",
		".pager-tabs { flex: 0 0 40px; }",
	} {
		if !strings.Contains(string(css), required) {
			t.Fatalf("editor mobile footer CSS missing %q", required)
		}
	}
	for _, required := range []string{
		"setupEditorViewportHeight",
		"window.visualViewport",
		"--editor-viewport-height",
		"orientationchange",
		"setStatusbarDocTitle",
		"openStatusbarPathSheet",
		"updateStatusbarDocTitleFromTree",
	} {
		if !strings.Contains(string(js), required) {
			t.Fatalf("editor viewport height script missing %q", required)
		}
	}
}

func TestMindmapDoesNotSwitchPagerBySwipe(t *testing.T) {
	js, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	required := "if (currentDocType === 'spreadsheet' || currentDocType === 'drawing' || currentDocType === 'mindmap') return;"
	if !strings.Contains(string(js), required) {
		t.Fatalf("mindmap should not switch editor/preview via pager swipe")
	}
}

func TestMobileStatusbarModifyTimeShowsDateOnly(t *testing.T) {
	js, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	jsText := string(js)
	for _, required := range []string{
		"function formatStatusbarShortDate",
		"return s.substring(5, 10);",
		"function updateStatusbarModifyTime",
		"formatStatusbarShortDate(timeStr)",
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("editor statusbar time script missing %q", required)
		}
	}
	for _, forbidden := range []string{
		"shortSpan.textContent = doc.modify_time.substring(5)",
		"shortSpan.textContent = window.BLOG_MODIFY_TIME.substring(5)",
		"shortSpan.textContent = mm + '-' + dd + ' ' + hh + ':' + mi",
	} {
		if strings.Contains(jsText, forbidden) {
			t.Fatalf("mobile statusbar short time should not include hour/minute: found %q", forbidden)
		}
	}
}
