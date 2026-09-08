package main

import (
	"os"
	"strings"
	"testing"
)

func TestSharedSelectionControlsSupportSearchTreeAndAccessibility(t *testing.T) {
	js := mustReadSelectionControlFile(t, "static/js/selection-controls.js")
	css := mustReadSelectionControlFile(t, "static/css/selection-controls.css")

	for _, required := range []string{
		"global.BookStarkSearchSelect",
		"global.BookStarkTreePicker",
		`role="combobox"`,
		`role="listbox"`,
		`role="tree"`,
		"AbortController",
		"ArrowDown",
		"setInvalid",
		"setDisabled",
		"document_id",
		"doc_type",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("shared selection controls should contain %q", required)
		}
	}

	for _, required := range []string{
		".bs-selection-trigger",
		".bs-selection-popover",
		".bs-selection-option.is-selected",
		".bs-tree-picker-row",
		".bs-tree-picker-row.is-selected",
		"max-height: min(310px, 42vh)",
		"@media (max-width: 640px)",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("shared selection control styles should contain %q", required)
		}
	}
}

func mustReadSelectionControlFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}
