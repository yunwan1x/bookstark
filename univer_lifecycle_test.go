package main

import (
	"os"
	"strings"
	"testing"
)

func TestUniverAdapterLifecycle(t *testing.T) {
	data, err := os.ReadFile("static/js/univer-adapter.js")
	if err != nil {
		t.Fatalf("ReadFile(univer-adapter.js) error = %v", err)
	}
	js := string(data)
	for _, required := range []string{
		"function loadAssets(callback)",
		"function normalizeData(data)",
		"return createEmptyWorkbook()",
		"workbook = univerAPI.createWorkbook(normalized);",
		"workbook.setEditable(!lastReadonly)",
		"preserveDirty: wasDirty",
		"function revealWhenRendered(container)",
		"window.dispatchEvent(new CustomEvent('bookstark:univer-ready'))",
		"document.querySelectorAll('[data-univer]').forEach",
		"univer.dispose()",
		"stableSnapshot(getSnapshot())",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("Univer lifecycle or migration guard missing %q", required)
		}
	}
}

func TestUniverImagesUseSystemUploadAndURLSources(t *testing.T) {
	entryData, err := os.ReadFile("tools/univer/entry.js")
	if err != nil {
		t.Fatalf("ReadFile(tools/univer/entry.js) error = %v", err)
	}
	entry := string(entryData)
	for _, required := range []string{
		"class BookStarkImageIoService extends ImageIoService",
		"window.BookStarkUniverUploadImage(imageFile)",
		"imageSourceType: ImageSourceType.URL",
		"source: uploaded.url",
		"base64Cache",
		"this._decreaseWaiting()",
		"function BookStarkSheetsDrawingPreset(options = {})",
		"drawingPlugin[1].override",
	} {
		if !strings.Contains(entry, required) {
			t.Fatalf("custom Univer image service missing %q", required)
		}
	}

	adapterData, err := os.ReadFile("static/js/univer-adapter.js")
	if err != nil {
		t.Fatalf("ReadFile(univer-adapter.js) error = %v", err)
	}
	adapter := string(adapterData)
	for _, required := range []string{
		"window.BookStarkUniverUploadImage = uploadImageFile",
		"window.computeFileHash(file)",
		"window.checkUploadByHash(hash)",
		"formData.append('category', 'spreadsheet')",
		"fetcher('/api/uploads'",
		"sdk.BookStarkSheetsDrawingPreset({ allowImageSize: 5 * 1024 * 1024 })",
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("system-backed Univer image upload missing %q", required)
		}
	}
}

func TestUniverAssetsArePinnedAndBuiltLocally(t *testing.T) {
	pkg, err := os.ReadFile("tools/univer/package.json")
	if err != nil {
		t.Fatalf("ReadFile(tools/univer/package.json) error = %v", err)
	}
	manifest := string(pkg)
	for _, required := range []string{
		`"@univerjs/presets": "0.25.1"`,
		`"@univerjs/preset-sheets-conditional-formatting": "0.25.1"`,
		`"@univerjs/preset-sheets-core": "0.25.1"`,
		`"@univerjs/preset-sheets-data-validation": "0.25.1"`,
		`"@univerjs/preset-sheets-drawing": "0.25.1"`,
		`"@univerjs/preset-sheets-filter": "0.25.1"`,
		`"@univerjs/preset-sheets-find-replace": "0.25.1"`,
		`"@univerjs/preset-sheets-hyper-link": "0.25.1"`,
		`"@univerjs/preset-sheets-note": "0.25.1"`,
		`"@univerjs/preset-sheets-sort": "0.25.1"`,
		`"@univerjs/preset-sheets-table": "0.25.1"`,
	} {
		if !strings.Contains(manifest, required) {
			t.Fatalf("Univer dependency is not pinned: %q", required)
		}
	}
	for _, path := range []string{"static/js/univer/univer.js", "static/js/univer/univer.css"} {
		info, statErr := os.Stat(path)
		if statErr != nil || info.Size() == 0 {
			t.Fatalf("built Univer asset missing or empty: %s", path)
		}
	}
}

func TestUniverInsertToolbarPresetsAreRegistered(t *testing.T) {
	entryData, err := os.ReadFile("tools/univer/entry.js")
	if err != nil {
		t.Fatalf("ReadFile(tools/univer/entry.js) error = %v", err)
	}
	entry := string(entryData)
	adapterData, err := os.ReadFile("static/js/univer-adapter.js")
	if err != nil {
		t.Fatalf("ReadFile(univer-adapter.js) error = %v", err)
	}
	adapter := string(adapterData)

	for _, preset := range []string{
		"UniverSheetsHyperLinkPreset",
		"UniverSheetsNotePreset",
	} {
		if !strings.Contains(entry, preset) {
			t.Fatalf("Univer entry missing insert feature preset %q", preset)
		}
		if !strings.Contains(adapter, "sdk."+preset+"(") {
			t.Fatalf("Univer adapter does not register insert feature preset %q", preset)
		}
	}
	for _, source := range []string{entry, adapter} {
		if strings.Contains(source, "ThreadComment") {
			t.Fatal("thread comments should not be registered in the spreadsheet editor")
		}
	}
}

func TestUniverDataToolbarPresetsAreRegistered(t *testing.T) {
	entryData, err := os.ReadFile("tools/univer/entry.js")
	if err != nil {
		t.Fatalf("ReadFile(tools/univer/entry.js) error = %v", err)
	}
	entry := string(entryData)
	adapterData, err := os.ReadFile("static/js/univer-adapter.js")
	if err != nil {
		t.Fatalf("ReadFile(univer-adapter.js) error = %v", err)
	}
	adapter := string(adapterData)

	for _, preset := range []string{
		"UniverSheetsConditionalFormattingPreset",
		"UniverSheetsDataValidationPreset",
		"UniverSheetsFilterPreset",
		"UniverSheetsFindReplacePreset",
		"UniverSheetsSortPreset",
		"UniverSheetsTablePreset",
	} {
		if !strings.Contains(entry, preset) {
			t.Fatalf("Univer entry missing data feature preset %q", preset)
		}
		if !strings.Contains(adapter, "sdk."+preset+"(") {
			t.Fatalf("Univer adapter does not register data feature preset %q", preset)
		}
	}
	for _, locale := range []string{
		"conditionalFormattingLocale",
		"dataValidationLocale",
		"filterLocale",
		"findReplaceLocale",
		"sortLocale",
		"tableLocale",
	} {
		if !strings.Contains(adapter, locale) {
			t.Fatalf("Univer adapter does not merge locale %q", locale)
		}
	}
}

func TestUniverAssetVersionsAreAvailableInEditorAndShareViews(t *testing.T) {
	for _, path := range []string{"templates/editor_common.html", "templates/share_view.html"} {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		template := string(data)
		for _, required := range []string{"window.__univerCssVer__", "window.__univerJsVer__", "/static/js/univer-adapter.js"} {
			if !strings.Contains(template, required) {
				t.Fatalf("%s missing Univer asset version or adapter %q", path, required)
			}
		}
	}
}

func TestLegacySpreadsheetRuntimeWasRemoved(t *testing.T) {
	if _, err := os.Stat("static/js/luckysheet"); !os.IsNotExist(err) {
		t.Fatalf("legacy spreadsheet assets should be removed")
	}
	for _, path := range []string{"static/js/editor-common.js", "static/js/editor.js", "static/css/editor.css"} {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		if strings.Contains(strings.ToLower(string(data)), "luckysheet") {
			t.Fatalf("legacy spreadsheet runtime reference remains in %s", path)
		}
	}
}

func TestSpreadsheetCharacterCountUsesUniverSheets(t *testing.T) {
	data, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("ReadFile(editor-common.js) error = %v", err)
	}
	js := string(data)
	for _, required := range []string{"if (data.sheets)", "data.sheets[sheetId].cellData", "String(value).length"} {
		if !strings.Contains(js, required) {
			t.Fatalf("Univer character-count traversal missing %q", required)
		}
	}
}
