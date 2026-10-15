package models

import (
	"fmt"
	"testing"
)

func TestPublicNoteSearchIncludesBodyOnlyForUnprotectedNotes(t *testing.T) {
	initAssetTestDB(t)
	for i, fixture := range []struct {
		kind       string
		visibility int
		password   string
		shared     bool
	}{
		{"note", 1, "", false}, {"note", 1, "", true},
		{"note", 0, "", false}, {"note", 0, "", true},
		{"note", 1, "protected", false}, {"note", 1, "protected", true},
		{"article", 1, "", false}, {"article", 1, "", true},
	} {
		blog := &Blog{BlogTitle: "Unrelated title", BlogIdentify: fmt.Sprintf("body-search-%d", i), MemberID: 1, BlogContent: "**正文专属关键词**", BlogType: fixture.kind, EditorType: "markdown", Visibility: fixture.visibility, Password: fixture.password}
		if err := blog.Insert(); err != nil {
			t.Fatal(err)
		}
		if fixture.shared {
			if _, err := CreateShare("blog", blog.BlogID, 1, ""); err != nil {
				t.Fatal(err)
			}
		}
	}
	for _, filter := range []string{"note", "article", ""} {
		want := int64(2)
		if filter == "article" {
			want = 0
		}
		items, total, err := ListSharesPaged(1, 1, "正文专属关键词", filter, PublicFeedOptions{Sort: "updated"})
		if err != nil {
			t.Fatal(err)
		}
		if total != want || (want > 0 && len(items) != 1) || (want == 0 && len(items) != 0) {
			t.Fatalf("filter=%q total=%d items=%d want=%d", filter, total, len(items), want)
		}
		for _, item := range items {
			if item.HasPassword || item.BlogType != "note" {
				t.Fatalf("body search exposed invalid item: %#v", item)
			}
		}
		if want > 0 {
			second, count, err := ListSharesPaged(2, 1, "正文专属关键词", filter, PublicFeedOptions{Sort: "updated"})
			if err != nil || count != want || len(second) != 1 || second[0].TargetID == items[0].TargetID {
				t.Fatalf("pagination: count=%d items=%#v err=%v", count, second, err)
			}
		}
	}
}

func TestShareBlogUsesManualDescription(t *testing.T) {
	initAssetTestDB(t)

	blog := &Blog{
		BlogTitle:    "HTML share description",
		BlogIdentify: "html-share-description",
		MemberID:     1,
		BlogContent:  "<h1>HTML body should not become preview</h1>",
		BlogDesc:     "分享页文章摘要",
		BlogType:     "article",
		EditorType:   "html",
		Visibility:   1,
	}
	if err := blog.Insert(); err != nil {
		t.Fatalf("Blog.Insert() error = %v", err)
	}
	if _, err := CreateShare("blog", blog.BlogID, blog.MemberID, ""); err != nil {
		t.Fatalf("CreateShare() error = %v", err)
	}

	items, total, err := ListSharesPaged(1, 10, "", "article")
	if err != nil {
		t.Fatalf("ListSharesPaged() error = %v", err)
	}
	if total != 1 || len(items) != 1 {
		t.Fatalf("ListSharesPaged() total=%d len=%d items=%#v", total, len(items), items)
	}
	if items[0].Description != "分享页文章摘要" {
		t.Fatalf("share list Description = %q", items[0].Description)
	}
	if items[0].Content != "分享页文章摘要" {
		t.Fatalf("share list Content preview = %q", items[0].Content)
	}
	items, total, err = ListSharesPaged(1, 10, "文章摘要", "article")
	if err != nil {
		t.Fatalf("ListSharesPaged(keyword) error = %v", err)
	}
	if total != 1 || len(items) != 1 || items[0].TargetID != blog.BlogID {
		t.Fatalf("ListSharesPaged(keyword) total=%d items=%#v", total, items)
	}

	detail, err := GetShareDetailByIdentify(items[0].ShareIdentify)
	if err != nil {
		t.Fatalf("GetShareDetailByIdentify() error = %v", err)
	}
	if detail.Description != "分享页文章摘要" {
		t.Fatalf("share detail Description = %q", detail.Description)
	}
}

func TestPublicBlogShareUsesManualDescription(t *testing.T) {
	initAssetTestDB(t)

	blog := &Blog{
		BlogTitle:    "Public article description",
		BlogIdentify: "public-article-description",
		MemberID:     1,
		BlogContent:  "body fallback",
		BlogDesc:     "公开文章摘要",
		BlogType:     "article",
		EditorType:   "markdown",
		Visibility:   1,
	}
	if err := blog.Insert(); err != nil {
		t.Fatalf("Blog.Insert() error = %v", err)
	}

	items, total, err := ListSharesPaged(1, 10, "", "article")
	if err != nil {
		t.Fatalf("ListSharesPaged() error = %v", err)
	}
	if total != 1 || len(items) != 1 {
		t.Fatalf("ListSharesPaged() total=%d len=%d items=%#v", total, len(items), items)
	}
	if items[0].Description != "公开文章摘要" {
		t.Fatalf("public share list Description = %q", items[0].Description)
	}
	if items[0].Content != "公开文章摘要" {
		t.Fatalf("public share list Content preview = %q", items[0].Content)
	}

	detail, err := GetShareDetailByIdentify(blog.BlogIdentify)
	if err != nil {
		t.Fatalf("GetShareDetailByIdentify(public) error = %v", err)
	}
	if detail.Description != "公开文章摘要" {
		t.Fatalf("public share detail Description = %q", detail.Description)
	}
}

func TestEncryptedShareBlogDoesNotExposeManualDescription(t *testing.T) {
	initAssetTestDB(t)

	blog := &Blog{
		BlogTitle:    "Encrypted article description",
		BlogIdentify: "encrypted-article-description",
		MemberID:     1,
		BlogContent:  "encrypted body",
		BlogDesc:     "不应该泄露的摘要",
		Password:     "secret-hash",
		BlogType:     "article",
		EditorType:   "markdown",
		Visibility:   1,
	}
	if err := blog.Insert(); err != nil {
		t.Fatalf("Blog.Insert() error = %v", err)
	}
	if _, err := CreateShare("blog", blog.BlogID, blog.MemberID, ""); err != nil {
		t.Fatalf("CreateShare() error = %v", err)
	}

	items, total, err := ListSharesPaged(1, 10, "", "article")
	if err != nil {
		t.Fatalf("ListSharesPaged() error = %v", err)
	}
	if total != 1 || len(items) != 1 {
		t.Fatalf("ListSharesPaged() total=%d len=%d items=%#v", total, len(items), items)
	}
	if items[0].Description != "" {
		t.Fatalf("encrypted share list Description = %q", items[0].Description)
	}
	if items[0].Content != "内容已加密" {
		t.Fatalf("encrypted share list Content = %q", items[0].Content)
	}

	detail, err := GetShareDetailByIdentify(items[0].ShareIdentify)
	if err != nil {
		t.Fatalf("GetShareDetailByIdentify() error = %v", err)
	}
	if detail.Description != "" {
		t.Fatalf("encrypted share detail Description = %q", detail.Description)
	}
}
