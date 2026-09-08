package main

import (
	"os"
	"strings"
	"testing"
)

func TestSpecialDocAssetLoadingWaitsBeforeShowingComponents(t *testing.T) {
	commonData, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("ReadFile(editor-common.js) error = %v", err)
	}
	editorData, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	zhData, err := os.ReadFile("i18n/zh.go")
	if err != nil {
		t.Fatalf("ReadFile(zh.go) error = %v", err)
	}
	enData, err := os.ReadFile("i18n/en.go")
	if err != nil {
		t.Fatalf("ReadFile(en.go) error = %v", err)
	}

	common := string(commonData)
	adapterData, err := os.ReadFile("static/js/univer-adapter.js")
	if err != nil {
		t.Fatalf("ReadFile(univer-adapter.js) error = %v", err)
	}
	commonAndAdapter := common + "\n" + string(adapterData)
	for _, required := range []string{
		"function waitForStylesheets(links, callback)",
		"function loadAssets(callback)",
		"script.setAttribute('data-univer', 'js')",
		"waitForStylesheets(cssLinks",
		"waitForStylesheets([cssLink]",
		"function versionedAsset(path, version)",
		"var mindCssHref = versionedAsset('/static/js/mind-elixir/mind-elixir.css', window.__mindElixirCssVer__);",
		"var mindResetHref = versionedAsset('/static/css/mindmap-reset.css', window.__mindmapResetCssVer__);",
		"var markedScriptSrc = versionedAsset('/static/js/marked.min.js', window.__markedJsVer__);",
		"script.src = mindScriptSrc;",
		"if (window.BookStarkExcalidraw)",
		"if (keepAssets === false)",
		"excalidrawLoaded = false;",
		"document.querySelectorAll('script[data-excalidraw=\"js\"], link[data-excalidraw=\"css\"]')",
		"sheetDiv.style.cssText = 'width:100%;height:100%;visibility:hidden;'",
		"excCanvas.style.cssText = 'width:100%;min-height:600px;flex:1;display:none;'",
		"mindEl.style.cssText = 'width:100%;height:100%;visibility:hidden;'",
		"function refreshMindElixirLayout(mind, opts)",
		"refreshMindElixirLayout(mind, { center: true });",
		"refreshMindElixirLayout(mind);",
	} {
		if !strings.Contains(commonAndAdapter, required) {
			t.Fatalf("special doc asset loader missing %q", required)
		}
	}

	templateData, err := os.ReadFile("templates/editor_common.html")
	if err != nil {
		t.Fatalf("ReadFile(editor_common.html) error = %v", err)
	}
	template := string(templateData)
	for _, required := range []string{
		"window.__mindElixirCssVer__ = '{{assetVer \"/static/js/mind-elixir/mind-elixir.css\"}}';",
		"window.__mindmapResetCssVer__ = '{{assetVer \"/static/css/mindmap-reset.css\"}}';",
		"window.__mindElixirJsVer__ = '{{assetVer \"/static/js/mind-elixir/mind-elixir.umd.js\"}}';",
		"window.__markedJsVer__ = '{{assetVer \"/static/js/marked.min.js\"}}';",
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("special doc template missing asset version %q", required)
		}
	}

	editor := string(editorData)
	for _, required := range []string{
		"window.__('editor.univer.loading')",
		"window.__('editor.excalidraw.loading')",
		"if (sheet) sheet.style.visibility = 'hidden';",
		"if (canvas) canvas.style.display = 'none';",
		"if (mindEl) mindEl.style.visibility = 'hidden';",
		"if (mindEl) mindEl.style.visibility = '';",
		"showSpreadsheet();",
	} {
		if !strings.Contains(editor, required) {
			t.Fatalf("special doc editor shell missing %q", required)
		}
	}

	for _, required := range []string{
		"editor.univer.loading",
		"editor.excalidraw.loading",
	} {
		if !strings.Contains(string(zhData), required) || !strings.Contains(string(enData), required) {
			t.Fatalf("special doc loading i18n missing %q", required)
		}
	}

	for _, forbidden := range []string{
		"if (mindEl) mindEl.style.display = 'none';",
		"mindEl.style.cssText = 'width:100%;height:100%;display:none;'",
	} {
		if strings.Contains(common+"\n"+editor, forbidden) {
			t.Fatalf("mindmap should not initialize in display:none container, found %q", forbidden)
		}
	}
}
