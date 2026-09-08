package models

import "testing"

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
