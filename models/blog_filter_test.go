package models

import "testing"

func TestListBlogsPagedWithLabelsFiltersNotesWithMarkdownCode(t *testing.T) {
	initAssetTestDB(t)

	fixtures := []Blog{
		{
			BlogTitle:    "fenced note",
			BlogIdentify: "note-code-fenced",
			MemberID:     1,
			BlogContent:  "before\n```go\nfmt.Println(1)\n```\nafter",
			BlogType:     "note",
			EditorType:   "markdown",
		},
		{
			BlogTitle:    "inline note",
			BlogIdentify: "note-code-inline",
			MemberID:     1,
			BlogContent:  "Use `fmt.Println` inline.",
			BlogType:     "note",
			EditorType:   "markdown",
		},
		{
			BlogTitle:    "plain note",
			BlogIdentify: "note-no-code",
			MemberID:     1,
			BlogContent:  "plain note without markdown code",
			BlogType:     "note",
			EditorType:   "markdown",
		},
		{
			BlogTitle:    "article with code",
			BlogIdentify: "article-code",
			MemberID:     1,
			BlogContent:  "article has `code`",
			BlogType:     "article",
			EditorType:   "markdown",
		},
	}
	for i := range fixtures {
		if err := fixtures[i].Insert(); err != nil {
			t.Fatalf("Insert(%s) error = %v", fixtures[i].BlogIdentify, err)
		}
	}

	blogs, total, err := ListBlogsPagedWithLabels(1, 1, 20, "", "", "", "note", "", "", "", "", "", "1")
	if err != nil {
		t.Fatalf("ListBlogsPagedWithLabels() error = %v", err)
	}
	if total != 2 {
		t.Fatalf("total = %d, want 2; blogs=%v", total, blogs)
	}
	got := map[string]bool{}
	for _, blog := range blogs {
		got[blog.BlogIdentify] = true
	}
	for _, want := range []string{"note-code-fenced", "note-code-inline"} {
		if !got[want] {
			t.Fatalf("missing code note %q in result: %#v", want, got)
		}
	}
	if got["note-no-code"] || got["article-code"] {
		t.Fatalf("plain note or article leaked into code-filtered note result: %#v", got)
	}
}
