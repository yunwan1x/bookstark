package main

import (
	"os"
	"strings"
	"testing"
)

func TestBookmarkMobileSwipeActionsUI(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/bookmarks.js")
	if err != nil {
		t.Fatalf("ReadFile(bookmarks.js) error = %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/bookmarks.css")
	if err != nil {
		t.Fatalf("ReadFile(bookmarks.css) error = %v", err)
	}
	js := string(jsBytes)
	css := string(cssBytes)

	for _, required := range []string{
		`function initSwipeActions()`,
		`list.addEventListener('touchstart'`,
		`list.addEventListener('touchmove'`,
		`bm-row-swipe-actions`,
		`BM.editBookmark(`,
		`BM.toggleBookmarkPin(`,
		`BM.setBookmarkNavVisible(`,
		`BM.setBookmarkPublic(`,
		`BM.deleteBookmark(`,
		`html += '<div class="bm-row-content">';`,
		`initSwipeActions();`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("bookmark mobile swipe JS missing %q", required)
		}
	}

	for _, required := range []string{
		`.bm-row-content`,
		`.bm-row-swipe-actions`,
		`.bm-row-swipe-action.danger`,
		`.bm-row-swipe-action.pin`,
		`.bm-row-swipe-action.nav`,
		`.bm-row-swipe-action.share`,
		`.bm-row.bm-row-swipe-open .bm-row-content`,
		`transform: translateX(calc(-1 * var(--bm-swipe-width, 96px)));`,
		`touch-action: pan-y;`,
		`.bm-batch-actions .bm-batch-dropdown`,
		`display: inline-flex;`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("bookmark mobile swipe CSS missing %q", required)
		}
	}

	if !strings.Contains(css, ".bm-batch-actions .bm-batch-dropdown {\n    display: inline-flex;") {
		t.Fatalf("bookmark batch actions should use the compact grouped menus on every viewport size")
	}
	templateBytes, err := os.ReadFile("templates/bookmarks.html")
	if err != nil {
		t.Fatalf("ReadFile(bookmarks.html) error = %v", err)
	}
	template := string(templateBytes)
	if strings.Contains(template, `class="bm-batch-group"`) || strings.Contains(template, `class="bm-batch-divider"`) {
		t.Fatalf("bookmark batch toolbar should not keep duplicate desktop action controls")
	}
}
