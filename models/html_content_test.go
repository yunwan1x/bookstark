package models

import (
	"testing"
	"time"
)

func TestGlobalSearchSkipsHTMLContent(t *testing.T) {
	initAssetTestDB(t)

	book := &Book{
		BookName:   "Search skip html book",
		Identify:   "search-skip-html-book",
		MemberID:   1,
		CreateTime: time.Now(),
	}
	if err := book.Insert(); err != nil {
		t.Fatalf("Book.Insert() error = %v", err)
	}

	doc := &Document{
		DocumentName: "HTML document title",
		Identify:     "html-document-title",
		BookID:       book.BookID,
		DocType:      "html",
		Markdown:     "<h1>hidden-html-doc-keyword</h1>",
		MemberID:     1,
	}
	if err := doc.Insert(); err != nil {
		t.Fatalf("Document.Insert() error = %v", err)
	}

	blog := &Blog{
		BlogTitle:    "HTML blog title",
		BlogIdentify: "html-blog-title",
		MemberID:     1,
		BlogContent:  "<p>hidden-html-blog-keyword</p>",
		BlogDesc:     "searchable-html-description",
		BlogType:     "article",
		EditorType:   "html",
	}
	if err := blog.Insert(); err != nil {
		t.Fatalf("Blog.Insert() error = %v", err)
	}

	result, err := GlobalSearch(1, "hidden-html")
	if err != nil {
		t.Fatalf("GlobalSearch() error = %v", err)
	}
	if result.Counts["documents"] != 0 || len(result.Documents) != 0 {
		t.Fatalf("HTML document content should not be searchable, got %#v", result.Documents)
	}
	if result.Counts["blogs"] != 0 || len(result.Blogs) != 0 {
		t.Fatalf("HTML blog content should not be searchable, got %#v", result.Blogs)
	}

	result, err = GlobalSearch(1, "searchable-html-description")
	if err != nil {
		t.Fatalf("GlobalSearch(desc) error = %v", err)
	}
	if result.Counts["blogs"] != 1 || len(result.Blogs) != 1 {
		t.Fatalf("HTML blog description should be searchable, got %#v", result.Blogs)
	}
	if result.Blogs[0].Snippet != "searchable-html-description" {
		t.Fatalf("HTML blog description snippet = %q", result.Blogs[0].Snippet)
	}
}
