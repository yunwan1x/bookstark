package main

import (
	"os"
	"strings"
	"testing"
)

func TestSearchToolbarParentsExposePageBackground(t *testing.T) {
	baseBytes, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("read base template: %v", err)
	}
	shareBytes, err := os.ReadFile("static/css/public-feed.css")
	if err != nil {
		t.Fatalf("read shares template: %v", err)
	}
	assetCSSBytes, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("read assets css: %v", err)
	}
	notesCSSBytes, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("read notes css: %v", err)
	}

	base := string(baseBytes)
	shares := string(shareBytes)
	assetCSS := string(assetCSSBytes)
	notesCSS := string(notesCSSBytes)

	if !strings.Contains(base, `.page-sticky-header { position: sticky; top: 40px; z-index: 10; background: transparent;`) {
		t.Fatalf("shared search/header wrapper should default to transparent")
	}
	if strings.Contains(base, `.page-sticky-header { position: sticky; top: 40px; z-index: 10; background: var(--color-bg);`) {
		t.Fatalf("shared search/header wrapper should not paint a page-colored slab by default")
	}
	if strings.Contains(notesCSS, `.page-sticky-header { position: sticky; top: 48px; z-index: 10; background: var(--color-bg`) {
		t.Fatalf("notes page sticky header should not override the shared transparent default")
	}

	if !strings.Contains(shares, `.public-search { display: flex;`) || strings.Contains(shares, `.sh-search-wrap`) {
		t.Fatal("unified reading search must live in the header, not the removed sticky toolbar")
	}

	assertCSSRuleContains(t, assetCSS, "#panel-ssh,\n#panel-webdav", "background: transparent;")
	assertCSSRuleContains(t, assetCSS, "#panel-ssh,\n#panel-webdav", "border: 0;")
	assertCSSRuleContains(t, assetCSS, "#panel-ssh .asset-panel-head,\n#panel-webdav .asset-panel-head", "background: transparent;")
	assertCSSRuleContains(t, assetCSS, "#panel-ssh .asset-panel-head,\n#panel-webdav .asset-panel-head", "border-bottom: 0;")
	assertCSSRuleContains(t, assetCSS, "#panel-ssh .asset-table-wrap,\n#panel-webdav .asset-table-wrap", "background: var(--color-bg-card);")
	assertCSSRuleContains(t, assetCSS, "#panel-ssh .asset-table-wrap,\n#panel-webdav .asset-table-wrap", "border: 1px solid var(--color-border);")
}

func TestStickySearchToolbarsPaintOnlyWhenStuck(t *testing.T) {
	baseBytes, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("read base template: %v", err)
	}
	stickyJSBytes, err := os.ReadFile("static/js/sticky-bg.js")
	if err != nil {
		t.Fatalf("read sticky bg script: %v", err)
	}
	sharesBytes, err := os.ReadFile("static/css/public-feed.css")
	if err != nil {
		t.Fatalf("read shares template: %v", err)
	}
	assetCSSBytes, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("read assets css: %v", err)
	}

	base := string(baseBytes)
	stickyJS := string(stickyJSBytes)
	shares := string(sharesBytes)
	assetCSS := string(assetCSSBytes)

	if !strings.Contains(base, `/static/js/sticky-bg.js`) {
		t.Fatalf("base template should load the shared sticky background script")
	}
	assertCSSRuleContains(t, base, ".page-sticky-header.is-stuck", "background: var(--color-bg);")
	assertCSSRuleContains(t, base, ".page-sticky-header.is-stuck", "border-bottom: 1px solid var(--color-border);")
	assertCSSRuleContains(t, base, ".page-sticky-header.is-stuck", "box-shadow:")
	assertCSSRuleContains(t, shares, ".public-header", "background: var(--color-bg-card);")
	assertCSSRuleContains(t, assetCSS, "#panel-ssh .asset-panel-head.is-stuck,\n#panel-webdav .asset-panel-head.is-stuck", "background: var(--color-bg);")

	for _, want := range []string{
		".page-sticky-header",
		".sh-search-wrap",
		"#panel-ssh .asset-panel-head",
		"#panel-webdav .asset-panel-head",
		"is-stuck",
		"getComputedStyle",
	} {
		if !strings.Contains(stickyJS, want) {
			t.Fatalf("sticky bg script should contain %q", want)
		}
	}
}
