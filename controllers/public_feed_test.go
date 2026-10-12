package controllers_test

import (
	"bookstark/models"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPublicFeedPrivacyFiltersAndRendering(t *testing.T) {
	router, _ := initAssetControllerTest(t)
	for i, name := range []string{"公开文章一", "公开速记二", "PRIVATE_SENTINEL", "加密文章"} {
		kind := "article"
		if i == 1 {
			kind = "note"
		}
		b := &models.Blog{BlogTitle: name, BlogIdentify: "public-test-" + string(rune('a'+i)), MemberID: 1, BlogType: kind, BlogContent: "正文内容，记录知识与思考。", Visibility: 1}
		if i == 2 {
			b.Visibility = 0
		}
		if i == 3 {
			b.Password = "secret"
			b.BlogContent = "PROTECTED_SENTINEL"
		}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
		if err := models.BindLabelsFromNames(b.BlogID, "blog", []string{"教育", "心理", "PRIVATE_LABEL", "PROTECTED_LABEL"}[i]); err != nil {
			t.Fatal(err)
		}
		if _, err := models.DB.Exec("UPDATE md_blogs SET create_time=?,modify_time=? WHERE blog_id=?", time.Date(2026, 1, i+1, 0, 0, 0, 0, time.UTC), time.Date(2026, 2, 4-i, 0, 0, 0, 0, time.UTC), b.BlogID); err != nil {
			t.Fatal(err)
		}
	}
	book := &models.Book{BookName: "公开书籍", Identify: "public-book", MemberID: 1, Description: "测试书籍简介", CreateTime: time.Now()}
	if err := book.Insert(); err != nil {
		t.Fatal(err)
	}
	if _, err := models.CreateShare("book", book.BookID, 1, ""); err != nil {
		t.Fatal(err)
	}
	for _, pub := range []bool{true, false} {
		name := "PUBLIC_BOOKMARK"
		if !pub {
			name = "PRIVATE_BOOKMARK"
		}
		b := &models.Bookmark{Title: name, URL: "https://example.com/" + name, MemberID: 1, IsPublic: pub}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
		if err := models.BindLabelsFromNames(b.BookmarkID, "bookmark", name+"_LABEL"); err != nil {
			t.Fatal(err)
		}
	}
	for _, path := range []string{"/", "/shares", "/?sort=updated", "/?label=教育", "/?type=note", "/?type=book", "/?type=bookmark", "/?type=bookmark&sort=updated", "/?type=bookmark&keyword=nomatch", "/?type=bookmark&label=PRIVATE_BOOKMARK_LABEL", "/?keyword=不存在", "/?page=2", "/?label=%27%20OR%201=1--"} {
		w := adminAssetRequest(router, "", "GET", path, nil)
		if w.Code != 200 {
			t.Fatalf("%s: %d %s", path, w.Code, w.Body.String())
		}
		html := w.Body.String()
		if strings.Contains(html, `>PRIVATE_BOOKMARK<`) || strings.Contains(html, `>PRIVATE_BOOKMARK_LABEL<`) {
			t.Fatal("private bookmark leaked")
		}
		if path == "/?type=bookmark" && (!strings.Contains(html, `class="bm-row"`) || !strings.Contains(html, `target="_blank"`)) {
			t.Fatal("missing public bookmark row")
		}
		for _, private := range []string{"PRIVATE_SENTINEL", "PRIVATE_LABEL", "PROTECTED_SENTINEL", "PROTECTED_LABEL"} {
			if strings.Contains(html, private) {
				t.Fatalf("%s leaked %s", path, private)
			}
		}
		if !strings.Contains(html, "public-layout") || !strings.Contains(w.Header().Get("Cache-Control"), "no-store") {
			t.Fatal("missing visitor layout/cache policy")
		}
		if path == "/?type=note" && strings.Contains(html, "公开文章一") {
			t.Fatal("type filter failed")
		}
		if path == "/?label=教育" && strings.Contains(html, "公开速记二") {
			t.Fatal("label filter failed")
		}
		if path == "/?sort=updated" && strings.Index(html, "公开文章一") > strings.Index(html, "加密文章") {
			t.Fatal("updated sort failed")
		}
		if path == "/" && strings.Index(html, "公开文章一") < strings.Index(html, "加密文章") {
			t.Fatal("published sort failed")
		}
		if path == "/" && (strings.Contains(html, `public-note-card`) || !strings.Contains(html, `public-content-type`)) {
			t.Fatal("default must be typed articles")
		}
		if path == "/?type=note" && (!strings.Contains(html, `public-note-card`) || strings.Contains(html, `<h2><a href="/shares/public-test-b"`)) {
			t.Fatal("notes should be body-first")
		}
		if path == "/?type=note" && strings.Contains(html, `public-read-link`) {
			t.Fatal("note list should not show redundant detail link")
		}
		if path == "/?type=book" && !strings.Contains(html, `public-book-cover`) {
			t.Fatal("missing bookshelf")
		}
	}
	if dir := os.Getenv("PUBLIC_FEED_SNAPSHOT_DIR"); dir != "" {
		for _, lang := range []string{"zh", "en"} {
			for _, kind := range []string{"article", "note", "book", "bookmark"} {
				req := httptest.NewRequest("GET", "/?type="+kind, nil)
				req.AddCookie(&http.Cookie{Name: "lang", Value: lang})
				w := httptest.NewRecorder()
				router.ServeHTTP(w, req)
				if err := os.WriteFile(filepath.Join(dir, "public-feed-"+lang+"-"+kind+".html"), w.Body.Bytes(), 0600); err != nil {
					t.Fatal(err)
				}
			}
		}
	}
}

func TestPublicTagsAdminSettings(t *testing.T) {
	router, token := initAssetControllerTest(t)
	values := map[string]string{"public_feed_tags_article": `{"mode":"manual","labels":[]}`}
	if w := adminAssetRequest(router, "", "PUT", "/api/admin/settings", values); w.Code != 401 {
		t.Fatal("anonymous update allowed", w.Code)
	}
	if w := adminAssetRequest(router, token, "PUT", "/api/admin/settings", values); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if models.GetPublicTagConfig("article").Mode != "manual" {
		t.Fatal("not persisted")
	}
	values["public_feed_tags_article"] = `{"mode":"bad"}`
	if w := adminAssetRequest(router, token, "PUT", "/api/admin/settings", values); w.Code != 400 {
		t.Fatal("invalid settings accepted", w.Code)
	}
	if models.GetPublicTagConfig("article").Mode != "manual" {
		t.Fatal("invalid save changed state")
	}
	w := adminAssetRequest(router, token, "GET", "/admin/system", nil)
	if w.Code != 200 || strings.Count(w.Body.String(), `class="public-tag-editor"`) != 4 {
		t.Fatal("settings panel missing", w.Code)
	}
	if dir := os.Getenv("PUBLIC_FEED_SNAPSHOT_DIR"); dir != "" {
		if err := os.WriteFile(filepath.Join(dir, "public-tag-settings.html"), w.Body.Bytes(), 0600); err != nil {
			t.Fatal(err)
		}
	}
}
