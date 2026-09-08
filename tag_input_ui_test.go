package main

import (
	"os"
	"strings"
	"testing"
)

func TestTagInputKeyboardNavigationContract(t *testing.T) {
	js, err := os.ReadFile("static/js/tag-input.js")
	if err != nil {
		t.Fatalf("ReadFile(tag-input.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/components.css")
	if err != nil {
		t.Fatalf("ReadFile(components.css) error = %v", err)
	}

	jsText := string(js)
	for _, required := range []string{
		"_pendingDropdownFocus",
		"_handleDropdownKey",
		"_moveDropdownFocus",
		"_focusDropdownItem",
		"_clickActiveDropdownItem",
		"ArrowDown",
		"ArrowUp",
		"Home",
		"End",
		"aria-selected",
		"aria-activedescendant",
		"role=\"option\"",
		"data-create",
		"_commitInputValue",
		"_splitTagText",
		"clipboardData",
		"data-lpignore",
		"data-1p-ignore",
		"data-bwignore",
		"data-form-type",
		"_markEditableAsNonCredential",
		"_getFieldValue",
		"_setFieldValue",
		"_syncFieldEmpty",
		"contenteditable",
		"plaintext-only",
		"data-placeholder",
		"summaryLimit",
		"_renderSelectedTags",
		"tag-input-selected",
		"tag-input-search-row",
		"tag-input-more",
		"tag-input-chip-label",
		"selected.appendChild(inputRow)",
		"tag-input-sheet-backdrop tag-popover-overlay",
		"tag-input-sheet tag-popover",
		"tag-input-sheet-header tag-popover-header",
		"tag-input-sheet-title tag-popover-title",
		"tag-input-sheet-done tag-popover-close",
		"tag-popover-body",
		"tag-input-sheet-selected tag-popover-chips",
		"tag-input-sheet-search tag-input-wrap",
		"tag-input-sheet-field tag-input",
		"tag-input-sheet-results tag-popover-dropdown",
		"chip.className = 'tag-chip'",
		"tag-remove",
		"panelSelector: '.tag-popover'",
		"classList.add('active')",
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("TagInput keyboard navigation script missing %q", required)
		}
	}
	if strings.Contains(jsText, "tag-input-sheet-check") {
		t.Fatalf("TagInput mobile sheet should reuse editor-style dropdown items without the old sheet check column")
	}

	for _, required := range []string{
		".tag-input-container {\n    display: flex;",
		"flex-wrap: wrap;",
		"align-content: center;",
		"align-items: center;\n    align-content: center;\n    gap: 6px;\n    box-sizing: border-box;\n    padding: 8px 12px;",
		"min-height: 38px",
		"background: var(--color-bg-card, #fff);",
		"[data-theme=\"dark\"] .tag-input-container",
		".tag-input-dd-item:focus",
		".tag-input-dd-item.active",
		".tag-input-selected",
		"flex-wrap: wrap;",
		"align-content: center;",
		"flex: 1 1 100%",
		"max-width: 100%",
		"overflow: visible;",
		".tag-input-selected.expanded {\n    flex-wrap: wrap;",
		"flex: 0 0 auto",
		"max-width: 180px",
		"min-width: 0;\n    overflow: hidden;",
		".tag-input-search-row",
		"flex: 1 1 120px",
		"height: 20px;\n    padding: 0;",
		"display: block;",
		"position: relative;",
		"line-height: 20px;",
		".tag-input-container .tag-input-field:focus-visible",
		"box-shadow: none;",
		`content: attr(data-placeholder);`,
		"position: absolute;",
		"text-overflow: ellipsis;",
		".tag-input-more",
		".tag-input-sheet-selected",
		"overflow-x: auto",
		".tag-popover-overlay",
		".tag-popover {",
		"width: 280px;",
		"border-radius: var(--radius-xl);",
		".tag-popover-header",
		".tag-popover-body",
		".tag-popover-chips",
		".tag-popover .tag-chip",
		".tag-popover .tag-chip .tag-remove",
		".tag-input-wrap",
		"background: var(--color-white);",
		".tag-popover .tag-input-sheet-field",
		"height: 20px;",
		"min-height: 0;",
		"outline: none;",
		".tag-popover .tag-input-sheet-field:focus-visible",
		".tag-popover-dropdown",
		"border-top: 1px solid var(--color-gray-100);",
		".tag-dropdown-item",
		"min-height: 0;",
		"transform: translateY(-100%);",
		".tag-popover.active {\n        display: block;\n        transform: translateY(0);",
	} {
		if !strings.Contains(string(css), required) {
			t.Fatalf("TagInput keyboard navigation style missing %q", required)
		}
	}

	for _, forbidden := range []string{
		"document.createElement('input')",
		"autocomplete=\"new-password\"",
		"bs_non_credential_",
	} {
		if strings.Contains(jsText, forbidden) {
			t.Fatalf("TagInput should not use credential-like input marker %q", forbidden)
		}
	}
}
