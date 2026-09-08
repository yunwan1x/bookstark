package main

import (
	"os"
	"strings"
	"testing"
)

func TestEditorCreateDocUsesUnifiedToolbarAction(t *testing.T) {
	templateData, err := os.ReadFile("templates/editor.html")
	if err != nil {
		t.Fatalf("ReadFile(editor.html) error = %v", err)
	}
	jsData, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	cssData, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	zhData, err := os.ReadFile("i18n/zh.go")
	if err != nil {
		t.Fatalf("ReadFile(zh.go) error = %v", err)
	}
	enData, err := os.ReadFile("i18n/en.go")
	if err != nil {
		t.Fatalf("ReadFile(en.go) error = %v", err)
	}

	template := string(templateData)
	if strings.Contains(template, "onclick=\"addRootDoc()\"") {
		t.Fatalf("editor sidebar should not render separate root create button")
	}
	if !strings.Contains(template, "onclick=\"addDocFromToolbar()\"") {
		t.Fatalf("editor sidebar missing unified create toolbar button")
	}

	js := string(jsData)
	for _, required := range []string{
		"function addDocFromToolbar()",
		"addDoc(currentDocId || 0, { allowRootChoice: !!currentDocId });",
		"function addDoc(defaultParentId, opts)",
		"if (choice.createAtRoot) parentId = 0;",
		"id=\"create-doc-root\"",
		"createAtRoot: !!(rootInput && rootInput.checked)",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("unified create doc logic missing %q", required)
		}
	}

	if !strings.Contains(string(cssData), ".create-doc-root-option") {
		t.Fatalf("create doc root option style missing")
	}
	if !strings.Contains(string(zhData), `"editor.create_doc.root":`) || !strings.Contains(string(enData), `"editor.create_doc.root":`) {
		t.Fatalf("create doc root option i18n missing")
	}
}
