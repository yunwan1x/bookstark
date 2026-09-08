package main

import (
	"os"
	"strings"
	"testing"
)

func TestBookmarkTagGroupsProvideBulkExpandAndCollapse(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/bookmarks.js")
	if err != nil {
		t.Fatalf("ReadFile(bookmarks.js) error = %v", err)
	}
	js := string(jsBytes)

	for _, required := range []string{
		"function getVisibleFlatLetters()",
		"function setAllFlatLettersExpanded(expanded)",
		"flatLetterExpanded[letters[i]] = expanded;",
		"flatLetterSearchExpanded[letters[i]] = expanded;",
		"if (nextFilter !== sidebarFilter) flatLetterSearchExpanded = {};",
		"saveFlatLetterExpanded();",
		"saveFlatTagsExpanded();",
		"BM.setAllFlatLettersExpanded(true)",
		"BM.setAllFlatLettersExpanded(false)",
		"aria-label=\"' + escAttr(expandLabel) + '\"",
		"aria-label=\"' + escAttr(collapseLabel) + '\"",
		"setAllFlatLettersExpanded: setAllFlatLettersExpanded",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("bookmark bulk tag toggle missing %q", required)
		}
	}

	cssBytes, err := os.ReadFile("static/css/bookmarks.css")
	if err != nil {
		t.Fatalf("ReadFile(bookmarks.css) error = %v", err)
	}
	css := string(cssBytes)
	for _, required := range []string{
		".bm-section-flat-actions",
		".bm-flat-bulk-btn",
		".bm-section-flat-toggle:focus-visible",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("bookmark bulk tag toggle CSS missing %q", required)
		}
	}
}

func TestBookmarkTagBulkToggleTranslations(t *testing.T) {
	for _, path := range []string{"i18n/zh.go", "i18n/en.go"} {
		content, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		text := string(content)
		for _, key := range []string{
			"bookmark.sidebar.expand_all",
			"bookmark.sidebar.collapse_all",
		} {
			if !strings.Contains(text, key) {
				t.Fatalf("%s missing translation key %q", path, key)
			}
		}
	}
}
