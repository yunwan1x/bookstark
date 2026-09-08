package main

import (
	"os"
	"strings"
	"testing"
)

func TestEditorMindmapMobileNodeActions(t *testing.T) {
	js, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("ReadFile(editor-common.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/mindmap-reset.css")
	if err != nil {
		t.Fatalf("ReadFile(mindmap-reset.css) error = %v", err)
	}
	text := string(js) + "\n" + string(css)
	for _, required := range []string{
		"var container = mind.container || document.getElementById('mindmap-el');",
		"mind.addChild();",
		"mind.insertSibling('after');",
		"mind.removeNodes(nodes);",
		"data-node-action",
		"selectedEditableNodes",
		"lastSelectedTpc",
		"rememberSelection",
		"me-style-popover",
		"document.body.appendChild(dd)",
		"positionDropdown",
		"max-width: calc(100vw - 16px);",
		"overflow-x: auto;",
		".me-style-popover.open",
		".me-style-toolbar .tb-btn:disabled",
		"@media (max-width: 1024px)",
		"#mindmap-el .mind-elixir-toolbar.lt",
		"top: 56px !important;",
		"function getMindElixirAppTheme()",
		"BookStark Dark",
		"mind.changeTheme(getMindElixirAppTheme())",
		"attributeFilter: ['data-theme']",
		"[data-theme=\"dark\"] #mindmap-el .map-container",
		"--panel-bgcolor: #1e293b;",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("mindmap mobile node action UI missing %q", required)
		}
	}
}
