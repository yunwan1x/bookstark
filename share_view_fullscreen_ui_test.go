package main

import (
	"os"
	"strings"
	"testing"
)

func TestShareViewHasImmersiveFullscreenReaderControls(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`id="share-reader-fullscreen-btn"`,
		`{{call .T "share_view.reader.fullscreen"}}`,
		`onclick="enterShareReaderFullscreen()"`,
		`id="share-reader-exit-btn"`,
		`share-reader-exit-btn`,
		`{{call .T "share_view.reader.exit_fullscreen"}}`,
		`onclick="exitShareReaderFullscreen()"`,
		`fa-compress`,
		`body.share-reader-fullscreen #sidebar`,
		`transition: width 0.22s ease`,
		`body.share-reader-fullscreen .share-topbar`,
		`body.share-reader-fullscreen #content-scroll`,
		`body.share-reader-fullscreen .share-reader-exit-btn`,
		`function enterShareReaderFullscreen()`,
		`function exitShareReaderFullscreen()`,
		`document.addEventListener('keydown'`,
		`ev.key === 'Escape'`,
		"body.share-reader-fullscreen #preview-wrap {\n            max-width: none !important;\n            padding: 0 !important;",
		`document.body.classList.add('share-reader-fullscreen')`,
		`document.body.classList.remove('share-reader-fullscreen')`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share view fullscreen reader support missing %q", required)
		}
	}

	if strings.Contains(text, `id="share-reader-restore"`) {
		t.Fatalf("share view should use the compact floating exit button instead of the old dropdown restore control")
	}
}

func TestShareViewPersistsReaderLayoutPreference(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`SHARE_LAYOUT_STORAGE_KEY = 'bookstark:share-view-layout:v1'`,
		`function readShareLayoutState()`,
		`function writeShareLayoutState(patch)`,
		`function setShareSidebarCollapsed(collapsed, persist)`,
		`function applyShareLayoutState()`,
		`writeShareLayoutState({ readerFullscreen: true });`,
		`writeShareLayoutState({ readerFullscreen: false });`,
		`setShareSidebarCollapsed(!_sidebarCollapsed, true);`,
		`setShareSidebarCollapsed(false, false);`,
		`applyShareLayoutState();`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share view should persist reader layout preference, missing %q", required)
		}
	}

	if strings.Contains(text, `localStorage.setItem('bookstark:share-view-layout:v1'`) {
		t.Fatalf("share view layout persistence should use helper with guarded localStorage access")
	}
}

func TestShareReaderCapabilitiesFollowRenderedContent(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatal(err)
	}
	for _, required := range []string{
		`state.readerShare = shareIdentify;`,
		`_shareReaderDocType === 'markdown' && state.readerShare === shareIdentify`,
		`if (_shareReaderDocType !== 'markdown') return;`,
		`button.hidden = _shareReaderDocType !== 'markdown'`,
		`setShareOutlineAvailable(_shareHeadings.length > 0);`,
		`if (tab === 'outline' && !_shareOutlineAvailable) tab = 'meta';`,
		`if (tab === 'outline' && !_shareOutlineAvailable) tab = 'tree';`,
		`if (renderVersion !== _shareRenderVersion) return;`,
		`loadVersion !== _shareRenderVersion`,
		`.share-view-shell [hidden], #share-reader-exit-btn[hidden] { display: none !important; }`,
	} {
		if !strings.Contains(string(tpl), required) {
			t.Fatalf("missing reader capability guard: %s", required)
		}
	}
}

func TestShareViewFullscreenExitButtonIsDraggable(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`touch-action: none;`,
		`.share-reader-exit-btn.is-dragging`,
		`function clampShareReaderExitPosition(left, top, rect)`,
		`function initShareReaderExitDrag()`,
		`var _shareReaderExitDragSuppressClick = false;`,
		`btn.addEventListener('pointerdown', function(ev)`,
		`document.addEventListener('pointermove', function(ev)`,
		`document.addEventListener('pointerup', endDrag);`,
		`btn.setPointerCapture(ev.pointerId);`,
		`ev.stopImmediatePropagation();`,
		`initShareReaderExitDrag();`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share view fullscreen exit button drag support missing %q", required)
		}
	}
}

func TestShareViewHTMLPreviewFillsAvailableHeight(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`#content-scroll.html-mode { overflow: hidden !important; }`,
		`#content-scroll.html-mode #preview-wrap,`,
		`#content-scroll.html-mode #preview-area,`,
		`#content-scroll.html-mode #html-preview-container,`,
		`#content-scroll.html-mode .html-preview-iframe`,
		`height: 100% !important;`,
		`min-height: 0 !important;`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share view HTML preview should fill available height, missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`#content-scroll.html-mode { overflow-y: auto !important; }`,
		`#content-scroll.html-mode #preview-wrap {
            max-width: none !important;
            padding: 0 !important;
            margin: 0 !important;
            height: auto !important;
        }`,
		`#content-scroll.html-mode #preview-area {
            height: auto !important;`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("share view HTML preview should not leave auto-height outer wrappers, found %q", forbidden)
		}
	}
}

func TestShareViewCompactHTMLToolsPrioritizeIframeWorkspace(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`function isCompactShareViewport()`,
		`window.innerWidth <= 960 && window.innerHeight <= 520`,
		`setShareSidebarCollapsed(true, false);`,
		`#content-scroll.html-mode + #share-footer`,
		`display: none !important;`,
		`@media (max-width: 960px) and (max-height: 520px)`,
		`share-html-tool-mode`,
		`share-main`,
		`body.share-html-tool-mode:not(.share-reader-fullscreen) .share-topbar`,
		`position: absolute;`,
		`height: 32px !important;`,
		`document.body.classList.toggle('share-html-tool-mode', type === 'html');`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("compact HTML share workspace support missing %q", required)
		}
	}
}
