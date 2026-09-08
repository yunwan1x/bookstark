package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestPresentationEditorLifecycleIsWired(t *testing.T) {
	requiredByFile := map[string][]string{
		"controllers/content_type.go": {
			"models.PresentationType",
			"models.ValidatePresentation(content)",
		},
		"models/document.go": {
			"d.DocType == PresentationType",
			"DefaultPresentation(d.DocumentName)",
		},
		"models/blog.go": {
			"b.EditorType == PresentationType",
			"DefaultPresentation(b.BlogTitle)",
		},
		"templates/editor.html": {
			`id="presentation-container"`,
			`id="pptist-editor"`,
		},
		"templates/editor_common.html": {
			"/static/js/pptist-adapter.js",
			"/static/css/pptist-adapter.css",
		},
		"static/js/editor.js": {
			"function renderPresentationContent()",
			"BookStarkPPTist.getContent()",
			"BookStarkPPTist.setContent(content)",
			`data-type="presentation"`,
		},
		"static/js/editor-common.js": {
			"docType === 'presentation'",
			"BookStarkPPTist.mount",
		},
		"static/js/pptist-adapter.js": {
			"function readFrameContent()",
			"frame.contentWindow.BookStarkPPTistBridge",
			"doc.addEventListener('pointerup', syncFromFrame, true)",
			"global.BookStarkPPTistUploadImage = uploadImageFile",
			"global.computeFileHash(file)",
			"global.checkUploadByHash(hash)",
			"formData.append('category', 'editor')",
			"bookstark-pptist-mobile-backdrop",
			"aria-expanded",
			"editor.presentation.mobile.slides",
		},
		"templates/share_view.html": {
			"shareEditDocType === 'presentation'",
			`id="share-presentation-editor"`,
			`uploadURL: '/api/shares/' + shareIdentify + '/edit/uploads?token='`,
		},
		"templates/notes.html": {
			`data-editor-type="presentation"`,
		},
		"static/js/resource-create.js": {
			"['presentation', 'fa-display'",
		},
	}
	for path, required := range requiredByFile {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		content := string(data)
		for _, needle := range required {
			if !strings.Contains(content, needle) {
				t.Fatalf("%s missing presentation lifecycle hook %q", path, needle)
			}
		}
	}
}

func TestPPTistAssetsArePinnedAndExcludedFromPrecache(t *testing.T) {
	for _, path := range []string{
		"static/pptist/index.html",
		"static/pptist/app.html",
		"static/pptist/LICENSE",
		"static/pptist/BOOKSTARK-INTEGRATION.md",
		"tools/pptist-bookstark.patch",
		"tools/build-pptist.sh",
		"tools/generate-pptist-academic-templates.py",
		"static/pptist/mocks/template_quantum_blue.json",
		"static/pptist/mocks/template_data_night.json",
		"static/pptist/imgs/template_quantum_blue.webp",
		"static/pptist/imgs/template_data_night.webp",
	} {
		info, err := os.Stat(path)
		if err != nil || info.Size() == 0 {
			t.Fatalf("PPTist integration asset missing or empty: %s", path)
		}
	}
	buildData, err := os.ReadFile("build.py")
	if err != nil {
		t.Fatalf("ReadFile(build.py) error = %v", err)
	}
	if !strings.Contains(string(buildData), "rel.startswith('static/pptist/')") {
		t.Fatal("PPTist bundle must be excluded from install-time PWA precache")
	}
	notice, _ := os.ReadFile("static/pptist/BOOKSTARK-INTEGRATION.md")
	if !strings.Contains(string(notice), "2bfd88fef0d721b24b3a97bd5e3c8a36cabff0c6") {
		t.Fatal("PPTist upstream commit is not pinned in integration notice")
	}
	bridgePatch, _ := os.ReadFile("tools/pptist-bookstark.patch")
	if !strings.Contains(string(bridgePatch), "BookStarkPPTistBridge") {
		t.Fatal("PPTist build patch must expose the presentation snapshot bridge")
	}
	if !strings.Contains(string(bridgePatch), "BookStarkPPTistUploadImage") {
		t.Fatal("PPTist build patch must route local images through the BookStark upload bridge")
	}
	adapter, err := os.ReadFile("static/js/pptist-adapter.js")
	if err != nil {
		t.Fatalf("read PPTist adapter: %v", err)
	}
	if !strings.Contains(string(adapter), "/static/pptist/app.html?bookstark=1") {
		t.Fatal("PPTist adapter must use the non-index static entry to avoid Go index redirects")
	}

	localFonts, err := filepath.Glob("static/pptist/assets/*.woff2")
	if err != nil {
		t.Fatalf("glob PPTist fonts: %v", err)
	}
	if len(localFonts) != 0 {
		t.Fatalf("PPTist fonts must be externalized to the pinned CDN, found %d local files", len(localFonts))
	}
	stylesheets, err := filepath.Glob("static/pptist/assets/*.css")
	if err != nil || len(stylesheets) == 0 {
		t.Fatalf("find PPTist stylesheet: %v", err)
	}
	css, err := os.ReadFile(stylesheets[0])
	if err != nil {
		t.Fatalf("read PPTist stylesheet: %v", err)
	}
	const fontBase = "/dav-public/admin/pptist/2bfd88fef0d721b24b3a97bd5e3c8a36cabff0c6/fonts/"
	if !strings.Contains(string(css), fontBase+"SourceHanSans.woff2") {
		t.Fatal("PPTist stylesheet must use the versioned BookStark WebDAV path for optional fonts")
	}
	if count := strings.Count(string(css), fontBase); count != 21 {
		t.Fatalf("PPTist stylesheet must externalize all 21 fonts, found %d WebDAV references", count)
	}
	if regexp.MustCompile(`url\(\./[^)]*\.woff2\)`).Match(css) {
		t.Fatal("PPTist stylesheet still references a bundled font")
	}

	generator, err := os.ReadFile("tools/generate-pptist-academic-templates.py")
	if err != nil {
		t.Fatalf("read PPTist academic template generator: %v", err)
	}
	for _, marker := range []string{
		"量子蓝·学术报告",
		"数据夜·学术报告",
		"template_quantum_blue",
		"template_data_night",
	} {
		if !strings.Contains(string(generator), marker) {
			t.Fatalf("PPTist academic template generator missing %q", marker)
		}
	}
	for _, name := range []string{"template_quantum_blue", "template_data_night"} {
		data, err := os.ReadFile(filepath.Join("static/pptist/mocks", name+".json"))
		if err != nil {
			t.Fatalf("read PPTist academic template %s: %v", name, err)
		}
		var document struct {
			Width  float64 `json:"width"`
			Height float64 `json:"height"`
			Slides []struct {
				Type     string            `json:"type"`
				Elements []json.RawMessage `json:"elements"`
			} `json:"slides"`
		}
		if err := json.Unmarshal(data, &document); err != nil {
			t.Fatalf("decode PPTist academic template %s: %v", name, err)
		}
		if document.Width != 1000 || document.Height != 562.5 {
			t.Fatalf("PPTist academic template %s must use a 16:9 1000x562.5 canvas", name)
		}
		if len(document.Slides) != 7 {
			t.Fatalf("PPTist academic template %s must contain 7 slides, found %d", name, len(document.Slides))
		}
		if document.Slides[0].Type != "cover" || document.Slides[len(document.Slides)-1].Type != "end" {
			t.Fatalf("PPTist academic template %s must include cover and end slide types", name)
		}
		for index, slide := range document.Slides {
			if len(slide.Elements) == 0 {
				t.Fatalf("PPTist academic template %s slide %d is empty", name, index+1)
			}
		}
	}
}
