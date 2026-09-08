package main

import (
	"os"
	"strings"
	"testing"
)

func TestEditorAIFloatingWindowCanMaximizeAndRestore(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)

	for _, required := range []string{
		"_setAIFloatMaximized",
		"drawing-ai-maximize",
		"drawing-ai-maximized",
		"aria-pressed",
		"fa-compress",
		"fa-expand",
		"root._aiCompactStyle",
		"root.style.setProperty('left', pos.left + 'px', 'important')",
		"root.style.setProperty('top', pos.top + 'px', 'important')",
		"root.style.setProperty('transform', 'none', 'important')",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor floating AI maximize behavior missing %q", required)
		}
	}
	for _, required := range []string{
		".drawing-ai-float.drawing-ai-maximized",
		"transform: translate(-50%, -50%) !important;",
		".drawing-ai-float.drawing-ai-maximized .ai-dlg-body",
		".markdown-ai-float.drawing-ai-maximized",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor floating AI maximize style missing %q", required)
		}
	}
}

func TestEditorAIFloatingWindowStateTransitionsResetInlineSize(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)

	for _, required := range []string{
		"_snapshotAIFloatStyle",
		"_applyAIFloatStyle",
		"_clearAIFloatBoxStyle",
		"root.style.getPropertyPriority(prop)",
		"root.style.removeProperty(prop)",
		"_clearAIFloatBoxStyle(root)",
		"['left', 'top', 'right', 'bottom', 'width', 'height', 'transform'].forEach(function(prop)",
		"if (nextMaximized && root.classList.contains('drawing-ai-collapsed')) setCollapsed(false);",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor floating AI state transition guard missing %q", required)
		}
	}
	for _, required := range []string{
		"width: min(860px, calc(100vw - 32px)) !important;",
		"height: min(78vh, 720px) !important;",
		"width: min(780px, calc(100vw - 32px)) !important;",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor floating AI maximized style should override normal float sizing, missing %q", required)
		}
	}
}

func TestEditorAIFloatingWindowMinimizeWorksAfterMaximize(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)

	required := "if (nextCollapsed && root.classList.contains('drawing-ai-maximized')) _setAIFloatMaximized(root, false, maxBtn);"
	if strings.Count(js, required) < 2 {
		t.Fatalf("editor floating AI collapse should first restore maximized state in both drawing and markdown windows")
	}
	for _, required := range []string{
		".drawing-ai-float.drawing-ai-collapsed",
		"width: 260px !important;",
		".drawing-ai-float.drawing-ai-collapsed .ai-dlg-body",
		".drawing-ai-float.drawing-ai-collapsed .ai-dlg-footer",
		"display: none !important;",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor floating AI collapsed style should beat maximized layout, missing %q", required)
		}
	}
}

func TestEditorAIFloatingWindowCollapseClearsInlineSize(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	js := string(editorJS)

	for _, required := range []string{
		"_setAIFloatCollapsed",
		"root._aiExpandedStyle = _snapshotAIFloatStyle(root)",
		"root.style.removeProperty('width')",
		"root.style.removeProperty('height')",
		"_applyAIFloatStyle(root, root._aiExpandedStyle)",
		"root.classList.toggle('drawing-ai-collapsed', collapsed)",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor floating AI collapse should manage inline size state, missing %q", required)
		}
	}
}

func TestEditorPreviewAIFloatingWindowStateTransitionsResetInlineGeometry(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)

	for _, required := range []string{
		"setPreviewAIMaximized",
		"panel._previewAICompactStyle = _snapshotAIFloatStyle(panel)",
		"_clearAIFloatBoxStyle(panel)",
		"_applyAIFloatStyle(panel, panel._previewAICompactStyle)",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor preview AI maximize should reuse floating state guard, missing %q", required)
		}
	}
	for _, required := range []string{
		".preview-ai-panel.preview-ai-maximized",
		"width: min(880px, calc(100vw - 32px)) !important;",
		"height: min(82vh, 760px) !important;",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor preview AI maximized style should beat stale inline sizing, missing %q", required)
		}
	}
}

func TestEditorMarkdownAIAppliesDirectlyWithoutOutputPanel(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)

	for _, required := range []string{
		"markdown-ai-insert",
		"markdown-ai-replace-selection",
		"光标处插入",
		"替换选区",
		"currentSelectionText",
		"setPendingSelection",
		"当前选区",
		"markdown-ai-context-locator",
		"title=\"定位到选区\"",
		"_selectEditorRange(replaceTarget, true)",
		"renderQuickActions",
		"refreshQuickActions",
		"defaultActions",
		"selectionActions",
		"_clearEditorSelection(replaceTarget || currentSelectionRange)",
		"generateAndApply",
		"setReplaceAvailable",
		"bindSelectionSync",
		"syncSelectionContext",
		"_selectEditorRange(all)",
		"readCurrentInsertTarget",
		"prepareLiveApply",
		"applyLiveDelta",
		"full.slice(liveAppliedLen)",
		`'<button type="button" class="ai-dlg-btn ai-dlg-btn-stop" style="display:none;">停止</button>' +
          '<button type="button" class="ai-dlg-btn ai-dlg-btn-replace markdown-ai-replace-selection"`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor markdown AI direct apply behavior missing %q", required)
		}
	}
	if strings.Contains(js, `'<div class="ai-dlg-output" aria-live="polite"></div>' +
        '</div>' +
        '<div class="ai-dlg-footer">' +
          '<button type="button" class="ai-dlg-btn ai-dlg-btn-cancel">取消</button>'`) {
		t.Fatalf("markdown AI should not render the old output preview panel before the footer")
	}
	for _, forbidden := range []string{
		"markdown-ai-use-current-selection",
		"使用当前选区",
		"root.querySelector('.markdown-ai-use-current-selection')",
	} {
		if strings.Contains(js, forbidden) {
			t.Fatalf("editor markdown AI should not keep current-selection button marker %q", forbidden)
		}
	}
	for _, forbidden := range []string{
		".markdown-ai-float .ai-dlg-output",
		".markdown-ai-float.drawing-ai-maximized .ai-dlg-output",
	} {
		if strings.Contains(css, forbidden) {
			t.Fatalf("editor markdown AI style should not keep output panel rule %q", forbidden)
		}
	}
	for _, required := range []string{
		".markdown-ai-float.drawing-ai-maximized .ai-dlg-body",
		".markdown-ai-float.drawing-ai-maximized .ai-dlg-prompt",
		".markdown-ai-context-locator",
		".markdown-ai-float .ai-dlg-quick",
		"text-decoration: underline",
		"text-underline-offset: 3px",
		"grid-template-rows",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor markdown AI maximized layout missing %q", required)
		}
	}
}

func TestEditorMarkdownPreviewAIUsesReaderChatWindow(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	editorCommon, err := os.ReadFile("templates/editor_common.html")
	if err != nil {
		t.Fatalf("ReadFile(editor_common.html) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)
	tpl := string(editorCommon)

	for _, required := range []string{
		"openMarkdownPreviewAI",
		"preview-ai-panel",
		"阅读助手",
		"preview-ai-maximize",
		"preview-ai-maximized",
		"_makeDrawingAIDraggable(panel, '.preview-ai-header')",
		"renderPreviewAIMarkdown",
		"preview-ai-context-locator",
		"总结全文",
		"解释这段",
		"preview-ai-conversation",
		"preview-ai-composer-actions",
		`textarea class="preview-ai-input" rows="3"`,
		".preview-ai-input').addEventListener('keydown'",
		"if (e.key === 'Enter'",
		"preview-ai-copy",
		"copyPreviewAIMessage",
		"root.style.setProperty('height', rect.height + 'px', 'important')",
		"renderPreviewAISelectionHighlight",
		"clearPreviewAISelectionHighlight",
		"CSS.highlights.set('preview-ai-selection'",
		"note-content",
		"marked.parse",
		"AIHelper.complete",
		"currentDocType === 'markdown'",
		"openMarkdownPreviewAI(opts)",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor preview AI reader window missing %q", required)
		}
	}
	for _, forbidden := range []string{
		"preview-ai-replace-selection",
		"preview-ai-insert",
		"data-context=\"selection\"",
		"preview-ai-context-preview",
		"可以问我关于当前 Markdown 预览内容的问题",
		"markdown-ai-context-preview",
	} {
		if strings.Contains(js, forbidden) {
			t.Fatalf("editor preview AI should not expose edit actions marker %q", forbidden)
		}
	}
	for _, required := range []string{
		".preview-ai-panel",
		".preview-ai-panel.open",
		".preview-ai-panel.preview-ai-maximized",
		".preview-ai-conversation",
		".preview-ai-context-locator",
		".preview-ai-copy",
		"::highlight(preview-ai-selection)",
		".preview-ai-selection-overlay",
		".preview-ai-selection-rect",
		".preview-ai-suggestion-row",
		".preview-ai-composer-actions",
		".preview-ai-suggestion:focus-visible",
		".preview-ai-composer",
		".preview-ai-message.note-content",
		".preview-ai-message-content.note-content",
		"white-space: normal;",
		".preview-ai-message.from-user",
		"white-space: pre-wrap;",
		"grid-template-rows: auto auto minmax(0, 1fr) auto",
		"min-height: 102px",
		"height: 28px;",
		"background: transparent",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor preview AI reader window style missing %q", required)
		}
	}
	contextStripStart := strings.Index(css, ".preview-ai-context-strip {")
	if contextStripStart == -1 {
		t.Fatalf("editor preview AI reader window missing context strip style")
	}
	contextStripEnd := strings.Index(css[contextStripStart:], "}")
	if contextStripEnd == -1 {
		t.Fatalf("editor preview AI reader window context strip style is malformed")
	}
	contextStripBlock := css[contextStripStart : contextStripStart+contextStripEnd]
	if !strings.Contains(contextStripBlock, "border-bottom: 1px solid var(--color-border);") {
		t.Fatalf("editor preview AI context strip should use the same bottom divider as the header")
	}
	for _, forbidden := range []string{
		".preview-ai-context-preview",
		".markdown-ai-context-preview",
		".markdown-ai-float.drawing-ai-maximized .markdown-ai-context-preview",
	} {
		if strings.Contains(css, forbidden) {
			t.Fatalf("editor AI should not keep context preview style %q", forbidden)
		}
	}
	if !strings.Contains(tpl, "/static/js/marked.min.js") {
		t.Fatalf("editor preview AI markdown rendering requires marked script in editor template")
	}
}

func TestEditorMarkdownPreviewAIMobileTopSheetTracksKeyboardViewport(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)

	for _, required := range []string{
		"function syncPreviewAIViewportHeight()",
		"window.visualViewport",
		"visualViewport.addEventListener('resize', syncPreviewAIViewportHeight)",
		"visualViewport.addEventListener('scroll', syncPreviewAIViewportHeight)",
		"visualViewport.removeEventListener('resize', syncPreviewAIViewportHeight)",
		"visualViewport.removeEventListener('scroll', syncPreviewAIViewportHeight)",
		"panel.style.setProperty('--preview-ai-viewport-height'",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor preview AI mobile viewport behavior missing %q", required)
		}
	}

	for _, required := range []string{
		"@media (max-width: 640px)",
		".preview-ai-panel {",
		"left: 5px;",
		"right: 5px;",
		"top: calc(8px + env(safe-area-inset-top, 0px));",
		"bottom: auto;",
		"height: min(calc(var(--preview-ai-viewport-height, var(--editor-viewport-height, 100dvh)) - 16px - env(safe-area-inset-top, 0px)), 620px);",
		"transform: translateY(-12px);",
		".preview-ai-panel.open {",
		"animation: preview-ai-slide-down 0.18s ease-out;",
		"@keyframes preview-ai-slide-down",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor preview AI mobile top sheet style missing %q", required)
		}
	}
}

func TestEditorMarkdownPreviewAIMobileInputStartsThreeRowsTall(t *testing.T) {
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	css := string(editorCSS)

	mobileStart := strings.Index(css, "@media (max-width: 640px)")
	if mobileStart == -1 {
		t.Fatalf("editor preview AI mobile styles missing media query")
	}
	mobileCSS := css[mobileStart:]
	for _, required := range []string{
		".preview-ai-input {",
		"box-sizing: border-box;",
		"height: 76px;",
		"min-height: 76px;",
		"max-height: 132px;",
	} {
		if !strings.Contains(mobileCSS, required) {
			t.Fatalf("editor preview AI mobile input height missing %q", required)
		}
	}
}

func TestEditorAIFloatingWindowMobileSlidesFromTop(t *testing.T) {
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	css := string(editorCSS)

	mobileStart := strings.Index(css, "@media (max-width: 640px)")
	if mobileStart == -1 {
		t.Fatalf("editor AI mobile styles missing media query")
	}
	mobileCSS := css[mobileStart:]
	for _, required := range []string{
		".drawing-ai-float {",
		"left: 5px;",
		"right: 5px;",
		"top: calc(8px + env(safe-area-inset-top, 0px));",
		"bottom: auto;",
		"max-width: calc(100vw - 10px);",
		"max-height: calc(var(--editor-viewport-height, 100dvh) - 16px - env(safe-area-inset-top, 0px));",
		"animation: preview-ai-slide-down 0.18s ease-out;",
	} {
		if !strings.Contains(mobileCSS, required) {
			t.Fatalf("editor AI mobile top sheet style missing %q", required)
		}
	}
}

func TestEditorAIFloatingWindowMobileMaximizedStaysTopSheet(t *testing.T) {
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	css := string(editorCSS)

	mobileStart := strings.Index(css, "@media (max-width: 640px)")
	if mobileStart == -1 {
		t.Fatalf("editor AI mobile styles missing media query")
	}
	mobileCSS := css[mobileStart:]
	for _, required := range []string{
		".preview-ai-panel.preview-ai-maximized {",
		"left: 5px !important;",
		"right: 5px !important;",
		"top: calc(8px + env(safe-area-inset-top, 0px)) !important;",
		"bottom: auto !important;",
		"width: auto !important;",
		"max-width: calc(100vw - 10px) !important;",
		"transform: none !important;",
		"animation: ai-mobile-max-slide-down 0.18s ease-out;",
		".preview-ai-panel.preview-ai-maximized.open {",
		".drawing-ai-float.drawing-ai-maximized {",
		"height: min(calc(var(--editor-viewport-height, 100dvh) - 16px - env(safe-area-inset-top, 0px)), 720px) !important;",
		"@keyframes ai-mobile-max-slide-down",
	} {
		if !strings.Contains(mobileCSS, required) && !strings.Contains(css, required) {
			t.Fatalf("editor AI mobile maximized top sheet style missing %q", required)
		}
	}
}

func TestEditorMarkdownPreviewAIMobileContextStripStaysOneLine(t *testing.T) {
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	css := string(editorCSS)

	mobileStart := strings.Index(css, "@media (max-width: 640px)")
	if mobileStart == -1 {
		t.Fatalf("editor preview AI mobile styles missing media query")
	}
	mobileCSS := css[mobileStart:]
	for _, required := range []string{
		".preview-ai-context-strip {",
		"flex-direction: row;",
		"flex-wrap: nowrap;",
		".preview-ai-context-actions {",
		"flex: 0 0 auto;",
		"flex-wrap: nowrap;",
		".preview-ai-context-badge {",
		"flex: 1 1 auto;",
		"text-align: right;",
	} {
		if !strings.Contains(mobileCSS, required) {
			t.Fatalf("editor preview AI mobile context row style missing %q", required)
		}
	}
}

func TestEditorMarkdownAIMobileContextBarStaysOneLine(t *testing.T) {
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	css := string(editorCSS)

	mobileStart := strings.Index(css, "@media (max-width: 640px)")
	if mobileStart == -1 {
		t.Fatalf("editor markdown AI mobile styles missing media query")
	}
	mobileCSS := css[mobileStart:]
	for _, required := range []string{
		".markdown-ai-context-bar {",
		"align-items: center;",
		"flex-direction: row;",
		"flex-wrap: nowrap;",
		".markdown-ai-context-actions {",
		"flex: 0 0 auto;",
		"flex-wrap: nowrap;",
		".markdown-ai-context-status {",
		"flex: 1 1 auto;",
		"text-align: right;",
	} {
		if !strings.Contains(mobileCSS, required) {
			t.Fatalf("editor markdown AI mobile context row style missing %q", required)
		}
	}
}

func TestEditorMarkdownPreviewAIMinimizeMatchesEditorAI(t *testing.T) {
	editorJS, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	editorCSS, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("ReadFile(editor.css) error = %v", err)
	}
	js := string(editorJS)
	css := string(editorCSS)

	for _, required := range []string{
		"preview-ai-toggle",
		"function setPreviewAICollapsed(panel, collapsed, toggleBtn)",
		"_setAIFloatCollapsed(panel, collapsed, toggleBtn)",
		"if (collapsed && panel.classList.contains('preview-ai-maximized')) setPreviewAIMaximized(panel, false, maxBtn);",
		"if (maximized && panel.classList.contains('drawing-ai-collapsed')) setPreviewAICollapsed(panel, false, toggleBtn);",
		"var nextCollapsed = !panel.classList.contains('drawing-ai-collapsed');",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("editor preview AI minimize behavior missing %q", required)
		}
	}

	for _, required := range []string{
		".preview-ai-panel.drawing-ai-collapsed",
		"width: 260px !important;",
		".preview-ai-panel.drawing-ai-collapsed .preview-ai-context-strip,",
		".preview-ai-panel.drawing-ai-collapsed .preview-ai-conversation,",
		".preview-ai-panel.drawing-ai-collapsed .preview-ai-composer",
		"display: none !important;",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("editor preview AI minimize style missing %q", required)
		}
	}
}
