package main

import (
	"os"
	"strings"
	"testing"
)

func TestBookMobileUsesFabForCreate(t *testing.T) {
	data, err := os.ReadFile("templates/index.html")
	if err != nil {
		t.Fatalf("ReadFile(index.html) error = %v", err)
	}
	html := string(data)

	for _, required := range []string{
		".book-mobile-fab { display: none;",
		".book-create-inline, .book-empty-create-inline { display: none !important; }",
		".book-mobile-fab { display: flex; bottom: 12px; width: 44px; height: 44px; font-size: 18px; }",
		`class="book-mobile-fab" onclick="openBookModal()"`,
		`class="book-search-row flex gap-2"`,
		`class="book-create-inline px-4 py-2 `,
		`class="book-empty-create-inline text-blue-600`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("book mobile create UI missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`class="px-4 py-2.5 bg-blue-600`,
		`class="book-create-inline px-4 py-2.5`,
	} {
		if strings.Contains(html, forbidden) {
			t.Fatalf("book search controls should match notes height, found %q", forbidden)
		}
	}
}

func TestBookMobileSearchControlsMatchBookmarksHeight(t *testing.T) {
	data, err := os.ReadFile("templates/index.html")
	if err != nil {
		t.Fatalf("ReadFile(index.html) error = %v", err)
	}
	html := string(data)

	for _, required := range []string{
		`<input id="book-search" type="text" class="search-input"`,
		`<button onclick="doBookSearch()" class="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm hover:bg-blue-700 whitespace-nowrap"`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("book search controls should reuse the same base structure as bookmarks, missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`.book-search-row .search-input { padding: 6px 10px; font-size: 12px; }`,
		`.book-search-row button { padding: 6px 10px; font-size: 12px; }`,
	} {
		if strings.Contains(html, forbidden) {
			t.Fatalf("book mobile search controls should not shrink below bookmark search height, found %q", forbidden)
		}
	}
}
