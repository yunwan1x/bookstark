package main

import (
	"os"
	"strings"
	"testing"
)

func TestBSDialogConfirmMobileOutsideClickCancels(t *testing.T) {
	src, err := os.ReadFile("static/js/bs-dialog.js")
	if err != nil {
		t.Fatalf("ReadFile(bs-dialog.js) error = %v", err)
	}
	js := string(src)
	for _, required := range []string{
		`var _activeCancel = null;`,
		`window.matchMedia('(max-width: 640px)').matches`,
		`function onOverlayClick(e)`,
		`e.target === overlay && isSmallScreen()`,
		`finish(false)`,
		`overlay.addEventListener('click', onOverlayClick)`,
		`overlay.removeEventListener('click', onOverlayClick)`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("BSDialog mobile confirm outside-cancel missing %q", required)
		}
	}
}

func TestBSDialogToastAvoidsSmallScreenTopSheets(t *testing.T) {
	src, err := os.ReadFile("static/js/bs-dialog.js")
	if err != nil {
		t.Fatalf("ReadFile(bs-dialog.js) error = %v", err)
	}
	js := string(src)
	for _, required := range []string{
		`function _hasSmallScreenModalOpen()`,
		`.asset-modal-backdrop.open, .asset-modal-backdrop.active, .editor-overlay.active, .bs-dialog-form-overlay.active`,
		`function _positionToastContainer()`,
		`container.style.top = 'auto';`,
		`container.style.bottom = '16px';`,
		`container.style.flexDirection = 'column-reverse';`,
		`container.style.top = '52px';`,
		`container.style.bottom = 'auto';`,
		`_positionToastContainer();`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("BSDialog toast should avoid covering small-screen top sheets, missing %q", required)
		}
	}
}
