package main

import (
	"os"
	"strings"
	"testing"
)

func TestBookSkeletonMatchesSelectedView(t *testing.T) {
	templateData, err := os.ReadFile("templates/index.html")
	if err != nil {
		t.Fatalf("ReadFile(index.html) error = %v", err)
	}
	cssData, err := os.ReadFile("static/css/books.css")
	if err != nil {
		t.Fatalf("ReadFile(books.css) error = %v", err)
	}
	html := string(templateData)
	css := string(cssData)

	for _, required := range []string{
		"var bookLoading = false;",
		"function renderBookSkeleton(mode)",
		"function showBookSkeleton()",
		"if (mode === 'compact')",
		"book-skeleton-shelf-item",
		"book-skeleton-compact-row",
		"listEl.className = 'book-list book-view-' + bookViewMode + ' book-list-loading';",
		"listEl.setAttribute('aria-busy', 'true');",
		"if (bookLoading) showBookSkeleton();",
	} {
		if !strings.Contains(html, required) {
			t.Errorf("book loading skeleton behavior missing %q", required)
		}
	}

	for _, forbidden := range []string{
		"var bookSkeletonHtml",
		`id="book-loading"`,
		"skeleton-card",
	} {
		if strings.Contains(html, forbidden) {
			t.Errorf("book page still contains legacy card skeleton marker %q", forbidden)
		}
	}

	for _, required := range []string{
		".book-list-loading {",
		".book-skeleton-cover {",
		".book-skeleton-mini-cover {",
		".book-skeleton-shimmer {",
		"@keyframes book-skeleton-shimmer",
		`[data-theme="dark"] .book-list-loading`,
		".book-skeleton-shimmer { animation: none; }",
	} {
		if !strings.Contains(css, required) {
			t.Errorf("book loading skeleton style missing %q", required)
		}
	}
}
