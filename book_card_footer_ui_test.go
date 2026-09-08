package main

import (
	"os"
	"strings"
	"testing"
)

func TestBookShelfAndCompactModesPreserveBookActions(t *testing.T) {
	data, err := os.ReadFile("templates/index.html")
	if err != nil {
		t.Fatalf("ReadFile(index.html) error = %v", err)
	}
	html := string(data)
	cssData, err := os.ReadFile("static/css/books.css")
	if err != nil {
		t.Fatalf("ReadFile(books.css) error = %v", err)
	}
	css := string(cssData)

	for _, required := range []string{
		`/static/css/books.css?v={{assetVer "/static/css/books.css"}}`,
		`data-book-view="shelf"`,
		`data-book-view="compact"`,
		"var BOOK_VIEW_STORAGE_KEY = 'bookstark:book-view:v1';",
		"function bookNameHash(name)",
		"function getBookCoverTheme(name)",
		"function getBookCoverTitleClass(name)",
		"function renderShelfBook(book)",
		"function renderCompactBook(book)",
		"function switchBookView(mode)",
		"var shareIcon = isShared ? 'fa-eye' : 'fa-eye-slash';",
		`<i class="fa-solid ' + shareIcon + '"></i>`,
		`data-book-share="' + book.book_id + '"`,
		"function syncBookShareActions(id, isShared)",
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("book view behavior missing %q", required)
		}
	}

	for _, required := range []string{
		".book-list.book-view-shelf",
		".book-cover-link:hover .book-object",
		".book-list.book-view-compact",
		".book-compact-row",
		"@media (max-width: 768px)",
		"@media (prefers-reduced-motion: reduce)",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("book view styles missing %q", required)
		}
	}

	if strings.Contains(html, `fa-share-nodes`) {
		t.Fatalf("book card share action should use the same eye icon pattern as notes, not fa-share-nodes")
	}
	if strings.Contains(html, `charColor(b.book_name)`) {
		t.Fatalf("book cover color should use the stable full-name hash, not first-character color")
	}
}

func TestBookShelfCoverUsesMeaningfulMetadataAndAdaptiveTypography(t *testing.T) {
	htmlData, err := os.ReadFile("templates/index.html")
	if err != nil {
		t.Fatalf("ReadFile(index.html) error = %v", err)
	}
	cssData, err := os.ReadFile("static/css/books.css")
	if err != nil {
		t.Fatalf("ReadFile(books.css) error = %v", err)
	}
	html := string(htmlData)
	css := string(cssData)

	for _, required := range []string{
		"if (length <= 16) return ' latin latin-short';",
		"if (length <= 30) return ' latin latin-medium';",
		"if (length <= 50) return ' latin latin-long';",
		"return ' latin latin-extra-long';",
		"function getBookCoverLabel(book)",
		"function getBookCoverDate(book)",
		`var titleLang = titleClass ? ' lang="en"' : '';`,
		`class="book-cover-link" title="' + escAttr(book.book_name) + '"`,
		`<span class="book-cover-kicker">' + escHtml(coverLabel) + '</span><span class="book-cover-rule"></span>`,
		`<span class="book-cover-foot"><time>' + escHtml(coverDate) + '</time><span>'`,
	} {
		if !strings.Contains(html, required) {
			t.Errorf("adaptive shelf title behavior missing %q", required)
		}
	}
	for _, forbidden := range []string{"getBookCoverKicker", "BOOKSTARK · LIBRARY", "<span>BOOKSTARK</span>"} {
		if strings.Contains(html, forbidden) {
			t.Errorf("shelf cover should not retain decorative top content %q", forbidden)
		}
	}

	for _, required := range []string{
		".book-cover-title.latin-short { font-size: 23px; }",
		".book-cover-title.latin-medium { font-size: 18px; }",
		".book-cover-title.latin-long { font-size: 15px; }",
		".book-cover-title.latin-extra-long { font-size: 13px; }",
		"-webkit-line-clamp: 6;",
		"overflow-wrap: anywhere;",
		"hyphens: auto;",
		".book-cover-kicker {",
		".book-cover-rule {",
	} {
		if !strings.Contains(css, required) {
			t.Errorf("adaptive shelf title style missing %q", required)
		}
	}
}
