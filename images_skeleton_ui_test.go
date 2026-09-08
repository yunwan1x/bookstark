package main

import (
	"os"
	"strings"
	"testing"
)

func TestImagesPageLoadingSkeletonUI(t *testing.T) {
	tpl, err := os.ReadFile("templates/images.html")
	if err != nil {
		t.Fatalf("ReadFile(images.html) error = %v", err)
	}
	js, err := os.ReadFile("static/js/uploads.js")
	if err != nil {
		t.Fatalf("ReadFile(uploads.js) error = %v", err)
	}

	tplText := string(tpl)
	for _, required := range []string{
		`.images-skeleton`,
		`.images-skeleton-card`,
		`.images-skeleton-row`,
		`images-skeleton-shimmer`,
	} {
		if !strings.Contains(tplText, required) {
			t.Fatalf("images template missing skeleton marker %q", required)
		}
	}

	jsText := string(js)
	for _, required := range []string{
		`renderLoadingSkeleton();`,
		`function renderLoadingSkeleton()`,
		`function buildGridSkeleton()`,
		`function buildListSkeleton()`,
		`currentView === 'list' ? buildListSkeleton() : buildGridSkeleton()`,
		`listEl.innerHTML = '';`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("uploads script missing skeleton marker %q", required)
		}
	}
}

func TestImagePreviewDeleteDoesNotCloseBeforeConfirm(t *testing.T) {
	js, err := os.ReadFile("static/js/uploads.js")
	if err != nil {
		t.Fatalf("ReadFile(uploads.js) error = %v", err)
	}

	jsText := string(js)
	badInlineClose := `ImagesPage.deleteImage(' + img.id + ',\'' + escAttr(escJs(img.file_name)) + '\');ImagesPage.closePreview()`
	if strings.Contains(jsText, badInlineClose) {
		t.Fatalf("preview delete closes the shared dialog overlay before confirmation can be used")
	}

	for _, required := range []string{
		`function deleteImageFromPreview(id, name)`,
		`ImagesPage.deleteImageFromPreview(`,
		`deleteImageFromPreview: deleteImageFromPreview`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("uploads script missing preview delete marker %q", required)
		}
	}
}
