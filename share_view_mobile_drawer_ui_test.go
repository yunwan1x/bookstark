package main

import (
	"os"
	"strings"
	"testing"
)

func TestShareViewMobileDrawerKeepsSidebarAboveOverlay(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`@media (max-width: 768px)`,
		`<div class="flex flex-1 overflow-hidden share-view-shell"`,
		`<div class="drawer-overlay" id="drawerOverlay" onclick="closeMobileDrawer()"></div>`,
		`.share-view-shell #sidebar.drawer-open`,
		`z-index: 120;`,
		`pointer-events: auto;`,
		`#drawerOverlay.active`,
		`z-index: 110;`,
		`left: 0;`,
		`@media (min-width: 769px)`,
		`#drawerOverlay`,
		`display: none !important;`,
		`pointer-events: none !important;`,
		`window.addEventListener('resize'`,
		`window.innerWidth > 768`,
		`closeMobileDrawer();`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share view mobile drawer overlay layering missing %q", required)
		}
	}

	overlayIndex := strings.Index(text, `<div class="drawer-overlay" id="drawerOverlay" onclick="closeMobileDrawer()"></div>`)
	shellIndex := strings.Index(text, `<div class="flex flex-1 overflow-hidden share-view-shell"`)
	sidebarIndex := strings.Index(text, `<div id="sidebar"`)
	if overlayIndex == -1 || shellIndex == -1 || sidebarIndex == -1 {
		t.Fatal("share view mobile drawer structure missing shell, overlay, or sidebar")
	}
	if !(shellIndex < overlayIndex && overlayIndex < sidebarIndex) {
		t.Fatal("share view mobile overlay must be inside shell before sidebar so it does not cover the drawer")
	}
}

func TestShareViewMobileFullscreenKeepsSidebarOffCanvas(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`@media (max-width: 768px)`,
		`body.share-reader-fullscreen #sidebar`,
		`transform: translateX(-100%) !important;`,
		`transition: none !important;`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share view mobile fullscreen should keep sidebar off-canvas without flash, missing %q", required)
		}
	}
}
