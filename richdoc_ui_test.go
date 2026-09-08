package main

import (
	"os"
	"strings"
	"testing"
)

func readRichdocTestFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile(%s) error = %v", path, err)
	}
	return string(data)
}

func TestRichDocumentEditorUsesSystemImageUpload(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	for _, required := range []string{
		"@hufe921/canvas-editor 0.9.137",
		"/api/uploads",
		"computeFileHash",
		"checkUploadByHash",
		"body.append('category', 'editor')",
		"this.instance.override.pasteImage",
		"self.command('executeImage', { value: data.url",
		"data:image/",
		"blob:",
		"图片尚未上传完成，不能保存内嵌图片",
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document upload adapter missing %q", required)
		}
	}
	if strings.Contains(adapter, "executeImportDocx") || strings.Contains(adapter, "executeExportDocx") {
		t.Fatalf("rich document editor must not expose DOCX import/export")
	}
}

func TestRichDocumentEntryPointsAndShareEditing(t *testing.T) {
	notesTemplate := readRichdocTestFile(t, "templates/notes.html")
	editorJS := readRichdocTestFile(t, "static/js/editor.js")
	commonTemplate := readRichdocTestFile(t, "templates/editor_common.html")
	shareTemplate := readRichdocTestFile(t, "templates/share_view.html")
	router := readRichdocTestFile(t, "routers/router.go")
	controller := readRichdocTestFile(t, "controllers/share.go")

	checks := map[string][]string{
		"notes template":             {notesTemplate, `data-editor-type="richdoc"`},
		"book create dialog":         {editorJS, `data-type="richdoc"`},
		"article and book editor":    {editorJS, `BookStarkRichDoc.mount('richdoc-container'`},
		"shared assets":              {commonTemplate, `/static/js/richdoc-editor.js`},
		"share rich document editor": {shareTemplate, `BookStarkRichDoc.mount('share-richdoc-editor'`},
		"share upload route":         {router, `/api/shares/:identify/edit/uploads`},
		"share password unlock":      {router, `/api/shares/:identify/edit/content/unlock`},
		"share upload handler":       {controller, `func UploadShareEditImage`},
	}
	for name, check := range checks {
		if !strings.Contains(check[0], check[1]) {
			t.Fatalf("%s missing %q", name, check[1])
		}
	}
}

func TestCanvasEditorVendoredWithLicense(t *testing.T) {
	core, err := os.Stat("static/js/canvas-editor/canvas-editor.umd.js")
	if err != nil {
		t.Fatalf("canvas-editor bundle missing: %v", err)
	}
	if core.Size() < 100000 {
		t.Fatalf("canvas-editor bundle is unexpectedly small: %d bytes", core.Size())
	}
	license := readRichdocTestFile(t, "static/js/canvas-editor/LICENSE.txt")
	if !strings.Contains(license, "MIT License") || !strings.Contains(strings.ToLower(license), "hufe") {
		t.Fatalf("canvas-editor MIT license attribution missing")
	}
}

func TestRichDocumentEditorUsesPaperDeskStyleLayout(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	styles := readRichdocTestFile(t, "static/css/richdoc-editor.css")

	for _, required := range []string{
		`class="richdoc-toolbar"`,
		`class="richdoc-footer"`,
		`class="richdoc-footer-mode"`,
		`button('comment'`,
		`button('textMore'`,
		`button('alignmentMenu'`,
		`button('insertMenu'`,
		`button('moreMenu'`,
		`button('pageSetup'`,
		`button('paperDirection'`,
		`button('margins'`,
		`button('columns'`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document PaperDesk layout missing %q", required)
		}
	}
	if strings.Contains(adapter, `class="richdoc-topbar"`) || strings.Contains(adapter, `>BookStark</strong>`) {
		t.Fatal("rich document editor still renders the redundant BookStark header")
	}
	if !strings.Contains(styles, `.richdoc-shell.is-readonly .richdoc-toolbar`) {
		t.Fatal("rich document read-only toolbar visibility rules missing")
	}

	toolbarStart := strings.Index(adapter, `function toolbarHTML()`)
	footerStart := strings.Index(adapter, `function footerHTML(readonly)`)
	if toolbarStart < 0 || footerStart < 0 || toolbarStart >= footerStart {
		t.Fatalf("rich document toolbar/footer layout functions are not in the expected order")
	}
	toolbar := adapter[toolbarStart:footerStart]
	for _, footerOnly := range []string{"pageSetup", "paperDirection", "margins", "columns", "zoomOut", "zoomIn", "fullscreen", "settings"} {
		if strings.Contains(toolbar, `button('`+footerOnly+`'`) {
			t.Fatalf("%s must remain in the PaperDesk-style footer instead of the formatting toolbar", footerOnly)
		}
	}

	for _, required := range []string{
		"height: 62px;",
		"background: radial-gradient",
		".richdoc-canvas > div",
		"height: 34px;",
	} {
		if !strings.Contains(styles, required) {
			t.Fatalf("rich document PaperDesk styles missing %q", required)
		}
	}
}

func TestRichDocumentToolbarCommandsReportFailuresAndPainterUsesRequiredOptions(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	styles := readRichdocTestFile(t, "static/css/richdoc-editor.css")

	for _, required := range []string{
		`painter: ['executePainter', { isDblclick: false }]`,
		`self.invoke(btn.dataset.command)`,
		`[richdoc] command failed:`,
		`button.classList.toggle('is-active'`,
		`button.setAttribute('aria-pressed'`,
		`openChoicePopover(name, '行间距'`,
		`openTablePopover()`,
		`openModal({`,
		`openChoicePopover(name, '纸张类型'`,
		`executePainter', { isDblclick: true }`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document toolbar command handling missing %q", required)
		}
	}
	if !strings.Contains(styles, ".richdoc-tool.is-active") {
		t.Fatalf("rich document toolbar active-state style is missing")
	}
}

func TestRichDocumentToolbarPreservesSelectionAndAppliesLiveColors(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")

	if strings.Contains(adapter, "executeFocus") {
		t.Fatalf("rich document toolbar must not call executeFocus before commands because canvas-editor collapses the active selection")
	}
	for _, required := range []string{
		`class="richdoc-popover" editor-component="menu"`,
		`class="richdoc-modal-layer" editor-component="menu"`,
		`RichDoc.prototype.openColorPopover`,
		`data-richdoc-color="text"`,
		`data-richdoc-color="highlight"`,
		`self.command(command, input.value)`,
		`self.command(command, color)`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document selection-safe toolbar wiring missing %q", required)
		}
	}
}

func TestRichDocumentToolbarGroupsLowFrequencyCommands(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	styles := readRichdocTestFile(t, "static/css/richdoc-editor.css")

	for _, required := range []string{
		`RichDoc.prototype.openTextMorePopover`,
		`RichDoc.prototype.openAlignmentPopover`,
		`RichDoc.prototype.openInsertPopover`,
		`RichDoc.prototype.openMoreToolsPopover`,
		`RichDoc.prototype.openGroupedPopover`,
		`RichDoc.prototype.invokeGrouped`,
		`{ command: 'painter', icon: 'fa-paintbrush', label: '格式刷' }`,
		`{ command: 'format', icon: 'fa-eraser', label: '清除格式' }`,
		`{ command: 'strikeout', icon: 'fa-strikethrough', label: '删除线' }`,
		`{ command: 'separator', icon: 'fa-minus', label: '分隔线' }`,
		`{ command: 'latex', icon: 'fa-square-root-variable', label: '公式' }`,
		`{ command: 'control', icon: 'fa-rectangle-list', label: '通用控件' }`,
		`{ command: 'watermark', icon: 'fa-stamp', label: '水印' }`,
		`{ command: 'print', icon: 'fa-print', label: '打印' }`,
		`this.syncAlignmentPicker`,
		`this.groupActionAnchor || this.commandButton(name)`,
		`executePainter', { isDblclick: true }`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document grouped toolbar missing %q", required)
		}
	}

	toolbarStart := strings.Index(adapter, `function toolbarHTML()`)
	footerStart := strings.Index(adapter, `function footerHTML(readonly)`)
	toolbar := adapter[toolbarStart:footerStart]
	for _, collapsed := range []string{"painter", "format", "sizeAdd", "sizeMinus", "strikeout", "superscript", "subscript", "left", "center", "right", "alignment", "justify", "separator", "watermark", "code", "pageBreak", "control", "checkbox", "radio", "latex", "date", "block", "print"} {
		if strings.Contains(toolbar, `button('`+collapsed+`'`) {
			t.Fatalf("%s should be grouped instead of directly rendered in the toolbar", collapsed)
		}
	}

	for _, required := range []string{
		`.richdoc-grouped-popover`,
		`.richdoc-command-section`,
		`.richdoc-command-grid`,
		`.richdoc-command-item`,
		`.richdoc-color-popover`,
		`.richdoc-color-presets`,
		`.richdoc-insert-group > [data-command="table"]`,
	} {
		if !strings.Contains(styles, required) {
			t.Fatalf("rich document grouped toolbar style missing %q", required)
		}
	}
}

func TestRichDocumentFontMenuMatchesReferenceLocalFontFlow(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	styles := readRichdocTestFile(t, "static/css/richdoc-editor.css")

	for _, required := range []string{
		`fontPickerHTML()`,
		`data-command="fontMenu"`,
		`class="richdoc-font-search"`,
		`placeholder="搜索字体"`,
		`读取本机字体`,
		`typeof global.queryLocalFonts`,
		`global.queryLocalFonts()`,
		`navigator.permissions.query({ name: 'local-fonts' })`,
		`detectCompatibleFonts`,
		`FONT_PREFERENCES_KEY`,
		`recentFonts`,
		`当前文档字体 · 本机未检测到`,
		`本机字体 · `,
		`兼容字体 · `,
		`华文宋体`,
		`华文黑体`,
		`华文仿宋`,
		`华文楷体`,
		`华文行楷`,
		`Ink Free`,
		`self.command('executeFont', family)`,
		`getSettingsFontFamilies`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document local font menu missing %q", required)
		}
	}
	if strings.Contains(adapter, `<select class="richdoc-select" data-command="font"`) {
		t.Fatal("rich document toolbar still uses the fixed native font select")
	}
	for _, required := range []string{
		`.richdoc-font-picker`,
		`.richdoc-font-popover`,
		`.richdoc-font-search`,
		`.richdoc-font-load`,
		`.richdoc-font-group`,
		`.richdoc-font-option`,
	} {
		if !strings.Contains(styles, required) {
			t.Fatalf("rich document local font menu style missing %q", required)
		}
	}
}

func TestRichDocumentParameterActionsUseStructuredSurfaces(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	styles := readRichdocTestFile(t, "static/css/richdoc-editor.css")

	if strings.Contains(adapter, "prompt(") {
		t.Fatalf("rich document parameter actions must not use native prompt dialogs")
	}
	for _, required := range []string{
		`class="richdoc-popover"`,
		`class="richdoc-modal-layer"`,
		`RichDoc.prototype.openModal`,
		`RichDoc.prototype.openPopover`,
		`RichDoc.prototype.openSearchPopover`,
		`RichDoc.prototype.openControlModal`,
		`title: '插入超链接'`,
		`title: '插入代码块'`,
		`title: '插入 LaTeX 公式'`,
		`RichDoc.prototype.openSettings`,
		`文档与编辑器设置`,
		`data-settings-tab=`,
		`assertSafeSettings`,
		`title: '添加批注'`,
		`focusCommand('executeInsertTable', selectedRow, selectedColumn`,
		`RichDoc.prototype.focusCommand`,
		`executeAddWatermark`,
		`executeDeleteWatermark`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document structured parameter UI missing %q", required)
		}
	}
	for _, required := range []string{
		`.richdoc-popover`,
		`.richdoc-table-grid`,
		`.richdoc-modal`,
		`.richdoc-modal-fields`,
		`.richdoc-search-popover`,
		`.richdoc-search-options`,
	} {
		if !strings.Contains(styles, required) {
			t.Fatalf("rich document structured parameter styles missing %q", required)
		}
	}
}

func TestRichDocumentRegistersReferenceContextMenus(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	styles := readRichdocTestFile(t, "static/css/richdoc-editor.css")

	for _, required := range []string{
		`register.contextMenuList([`,
		`name: '批注'`,
		`context.editorHasSelection && context.zone === zone.MAIN`,
		`name: '新增题注'`,
		`name: '修改题注'`,
		`openImageCaptionModal(command, context.startElement, false)`,
		`openImageCaptionModal(command, context.startElement, true)`,
		`command.executeSetImageCaption`,
		`name: '签名'`,
		`context.editorTextFocus`,
		`canvas.toBlob`,
		`self.insertImageFile(new File([blob]`,
		`name: '格式整理'`,
		`command.executeWordTool()`,
		`name: '清空涂鸦信息'`,
		`command.executeClearGraffiti()`,
		`name: '宏'`,
		`name: '录制宏'`,
		`name: '停止录制宏'`,
		`name: '回放宏'`,
		`name: '管理宏'`,
		`bookstark:richdoc:macros:v1`,
		`onCancel: function() { self.macro.cancelRecording(); }`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document context menu parity missing %q", required)
		}
	}
	if strings.Contains(adapter, `executeInsertElementList([{ value: canvas.toDataURL`) {
		t.Fatal("signature must use the system upload flow instead of embedding a data URL")
	}
	for _, required := range []string{
		`.richdoc-signature-canvas`,
		`.ce-contextmenu-comment`,
		`.ce-contextmenu-caption`,
		`.ce-contextmenu-signature`,
		`.ce-contextmenu-word-tool`,
	} {
		if !strings.Contains(styles, required) {
			t.Fatalf("rich document context menu style missing %q", required)
		}
	}
}

func TestRichDocumentReferenceInteractionsExposeSearchAndOptionMenus(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")

	for _, required := range []string{
		`class="richdoc-search-input"`,
		`class="richdoc-search-result"`,
		`data-search-nav="prev"`,
		`data-search-nav="next"`,
		`data-search-option="reg"`,
		`data-search-option="case"`,
		`data-search-option="selection"`,
		`executeSearchNavigatePre`,
		`executeSearchNavigateNext`,
		`getSearchNavigateInfo`,
		`isRegEnable:`,
		`isIgnoreCase:`,
		`isLimitSelection:`,
		`button('list'`,
		`openChoicePopover(name, '下划线样式'`,
		`openChoicePopover(name, '控件类型'`,
		`openChoicePopover(name, '插入日期'`,
		`openChoicePopover(name, '页面模式'`,
		`openChoicePopover(name, '纸张方向'`,
		`title: '页边距'`,
		`title: '分栏'`,
		`{ label: '网址', value: 'iframe' }`,
		`{ label: '视频', value: 'video' }`,
		`className = 'richdoc-table-close'`,
		`document.addEventListener('keydown', this.shortcutHandler, true)`,
		`clearTimeout(self.painterTimer)`,
		`splitButton('underline','underlineStyle'`,
		`RichDoc.prototype.syncCommandAvailability`,
		`this.currentMode === 'trace'`,
		`options.watermark.type === 'image'`,
		`mergeSettings(draft, value)`,
		`target.matches('input, textarea, select')`,
		`this.currentMode = readonly ? 'readonly' : 'edit'`,
		`this.syncCommandAvailability(this.controlActive)`,
		`['page','页面布局']`,
		`['advanced','高级 JSON']`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document reference interaction missing %q", required)
		}
	}

	for _, controlType := range []string{"text", "number", "select", "date", "checkbox", "radio"} {
		if !strings.Contains(adapter, controlType+`: {`) && !strings.Contains(adapter, `value: '`+controlType+`'`) {
			t.Fatalf("rich document control menu missing %q", controlType)
		}
	}
}

func TestRichDocumentCatalogDoesNotCoverNarrowEditingCanvas(t *testing.T) {
	adapter := readRichdocTestFile(t, "static/js/richdoc-editor.js")
	for _, required := range []string{
		`function shellHTML(readonly, compactLayout)`,
		`(readonly || compactLayout) ? ' hidden' : ''`,
		`container.clientWidth < 1100`,
	} {
		if !strings.Contains(adapter, required) {
			t.Fatalf("rich document narrow-layout catalog guard missing %q", required)
		}
	}
}
