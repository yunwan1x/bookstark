package main

import (
	"os"
	"strings"
	"testing"
)

func TestBookmarkTagFilterDefaultsExpandedAndSorted(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/bookmarks.js")
	if err != nil {
		t.Fatalf("ReadFile(bookmarks.js) error = %v", err)
	}
	js := string(jsBytes)

	for _, required := range []string{
		"return treeCollapsed[prefix] !== false;",
		"return saved === null ? true : saved === 'true';",
		"function isFlatLetterExpanded(letter)",
		"return flatLetterExpanded[letter] !== false;",
		"flatLetterExpanded[letter] = !isFlatLetterExpanded(letter);",
		"order.sort(compareBookmarkLetters);",
		"groups[order[i]].sort(compareBookmarkLabels);",
		"parentOrder.sort(compareBookmarkLabels);",
		"flat.sort(compareBookmarkLabels);",
		"parentMap[parentOrder[pi]].sort(compareBookmarkLabels);",
		"function compareBookmarkLetters(a, b)",
		"function compareBookmarkLabels(a, b)",
		"if (a === '#') return 1;",
		"if (b === '#') return -1;",
		"var letterExp = isFlatLetterExpanded(letter);",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("bookmark tag filter UI missing %q", required)
		}
	}

	if strings.Contains(js, "var letterExp = !!flatLetterExpanded[letter];") {
		t.Fatalf("bookmark letter groups should default expanded instead of truthy-only expanded")
	}
}
