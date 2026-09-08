package main

import (
	"os"
	"strings"
	"testing"
)

func TestEditorDraftRecoveryAppliesAndDiscardsAllDocTypes(t *testing.T) {
	editorData, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	commonData, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("ReadFile(editor-common.js) error = %v", err)
	}
	excalidrawData, err := os.ReadFile("static/js/excalidraw/excalidraw-percentages-BXMCSKIN.js")
	if err != nil {
		t.Fatalf("ReadFile(excalidraw-percentages-BXMCSKIN.js) error = %v", err)
	}
	editor := string(editorData)
	common := string(commonData)
	excalidraw := string(excalidrawData)

	for _, required := range []string{
		"function applyDraftContentToActiveEditor(content)",
		"BookStarkEditor.loadSpreadsheetData(content, { readonly: mode === 'preview' });",
		"BookStarkEditor.loadDrawingData(content, { readonly: mode === 'preview', onChange: onSpecialDocContentChange });",
		"BookStarkEditor.loadMindElixirData(content, { readonly: mode === 'preview', onChange: onSpecialDocContentChange });",
		"showDraftBanner(serverContent, draftContent)",
		"applyDraftContentToActiveEditor(draftContent);",
		"saveMgr.setSaveStatus('unsaved');",
		"applyDraftContentToActiveEditor(serverContent);",
	} {
		if !strings.Contains(editor, required) {
			t.Fatalf("editor draft recovery missing %q", required)
		}
	}

	for _, required := range []string{
		"function loadDrawingData(data, options)",
		"destroyExcalidraw(true)",
		"var onChange = options && options.onChange;",
		"window.BookStarkExcalidraw.initExcalidraw('excalidraw-canvas', data, function()",
		"window.BookStarkExcalidraw.initExcalidrawPreview('excalidraw-canvas', data)",
		"excalidrawRunning = true;",
		"if (container) container.style.display = '';",
		"if (loading) {\n        loading.innerHTML = '';\n        loading.style.display = 'none';\n      }",
		"function loadMindElixirData(data, options)",
		"destroyMindElixir()",
		"initMindElixir(data, { readonly: readonly });",
		"loadDrawingData: loadDrawingData",
		"loadMindElixirData: loadMindElixirData",
	} {
		if !strings.Contains(common, required) {
			t.Fatalf("editor common draft recovery missing %q", required)
		}
	}

	for _, forbidden := range []string{
		"\n        initExcalidraw('excalidraw-canvas', data, function()",
		"\n        initExcalidrawPreview('excalidraw-canvas', data)",
	} {
		if strings.Contains(common, forbidden) {
			t.Fatalf("editor common draft recovery should not call undefined internal Excalidraw helper %q", forbidden)
		}
	}

	for _, required := range []string{
		"var bsOnChange = null;",
		"bsOnChange = n;",
		"if (typeof bsOnChange === \"function\") bsOnChange();",
	} {
		if !strings.Contains(excalidraw, required) {
			t.Fatalf("excalidraw draft recovery integration missing %q", required)
		}
	}
}
