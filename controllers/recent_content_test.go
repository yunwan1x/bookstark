package controllers_test

import (
	"bookstark/conf"
	"bookstark/models"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
)

func TestHomeRecentContentAccountSyncAndAuthorization(t *testing.T) {
	router, token := initAssetControllerTest(t)
	owner, _ := models.GetMemberByAccount(conf.App.AdminAccount)
	other := &models.Member{Account: "recent-other", Password: "test-only", Role: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	otherToken, err := models.CreateApiToken(other.MemberID, "recent-test")
	if err != nil {
		t.Fatal(err)
	}
	private := &models.Blog{BlogTitle: "Private note", BlogIdentify: "recent-private", BlogType: "note", MemberID: owner.MemberID, BlogContent: "SECRET_BODY"}
	public := &models.Blog{BlogTitle: "Public article", BlogIdentify: "recent-public", BlogType: "article", MemberID: owner.MemberID, Visibility: 1}
	for _, blog := range []*models.Blog{private, public} {
		if err := blog.Insert(); err != nil {
			t.Fatal(err)
		}
	}
	readRecent := func(auth, query string) []models.RecentContent {
		t.Helper()
		w := adminAssetRequest(router, auth, "GET", "/api/home"+query, nil)
		var data struct {
			Recent []models.RecentContent `json:"recent"`
		}
		if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &data) != nil {
			t.Fatal(w.Code, w.Body.String())
		}
		if strings.Contains(w.Body.String(), "SECRET_BODY") {
			t.Fatal("history leaked content")
		}
		return data.Recent
	}
	if len(readRecent(token, "")) != 0 {
		t.Fatal("history must start empty, not seeded from updates")
	}
	// Anonymous public reads and rejected authenticated reads do not create history.
	adminAssetRequest(router, "", "GET", "/shares/recent-public", nil)
	w := adminAssetRequest(router, otherToken.Token, "GET", fmt.Sprintf("/api/blogs/%d", private.BlogID), nil)
	if w.Code != 403 {
		t.Fatal(w.Code)
	}
	if len(readRecent(otherToken.Token, "")) != 0 {
		t.Fatal("unauthorized read recorded")
	}
	for i := 0; i < 2; i++ {
		w = adminAssetRequest(router, token, "GET", fmt.Sprintf("/api/blogs/%d", private.BlogID), nil)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	items := readRecent(token, "?end=2000-01-01&month=2000-01&order=created")
	if len(items) != 1 || items[0].Title != private.BlogTitle || items[0].Type != "note" || items[0].URL != "/blogs/recent-private/edit" {
		t.Fatal(items)
	}
	// Another request/device for the same authenticated account sees the same row.
	if len(readRecent(token, "")) != 1 || len(readRecent(otherToken.Token, "")) != 0 {
		t.Fatal("account isolation/sync failed")
	}
	w = adminAssetRequest(router, otherToken.Token, "GET", "/shares/recent-public", nil)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	items = readRecent(otherToken.Token, "")
	if len(items) != 1 || items[0].URL != "/shares/recent-public" {
		t.Fatal(items)
	}
	if _, err := models.DB.Exec("UPDATE md_blogs SET visibility=0 WHERE blog_id=?", public.BlogID); err != nil {
		t.Fatal(err)
	}
	if len(readRecent(otherToken.Token, "")) != 0 {
		t.Fatal("unpublished content remains visible")
	}
	if _, err := models.DB.Exec("UPDATE md_blogs SET member_id=? WHERE blog_id=?", other.MemberID, private.BlogID); err != nil {
		t.Fatal(err)
	}
	// A non-admin who no longer owns a private resource cannot see stale titles.
	if err := models.RecordRecentContent(owner.MemberID, "blog", private.BlogID, ""); err != nil {
		t.Fatal(err)
	}
	filtered, err := models.ListRecentContent(owner.MemberID, false)
	if err != nil || len(filtered) != 0 {
		t.Fatal(filtered, err)
	}
	w = adminAssetRequest(router, token, "DELETE", "/api/home/recent", nil)
	if w.Code != 200 || len(readRecent(token, "")) != 0 {
		t.Fatal(w.Code, w.Body.String())
	}
	var remaining int
	models.DB.QueryRow("SELECT COUNT(*) FROM md_recent_content WHERE member_id=?", other.MemberID).Scan(&remaining)
	if remaining != 1 {
		t.Fatal("clearing one account deleted another's history")
	}
}

func TestHomeRecentBooksChaptersAndBound(t *testing.T) {
	router, token := initAssetControllerTest(t)
	book := &models.Book{BookName: "Recent book", Identify: "recent-book", MemberID: 1}
	if err := book.Insert(); err != nil {
		t.Fatal(err)
	}
	doc := &models.Document{DocumentName: "Recent chapter", Identify: "recent-chapter", BookID: book.BookID, MemberID: 1, Markdown: "SECRET_CHAPTER", DocType: "markdown"}
	if err := doc.Insert(); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"/books/recent-book/edit", fmt.Sprintf("/api/docs/%d", doc.DocumentID)} {
		w := adminAssetRequest(router, token, "GET", path, nil)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	items, err := models.ListRecentContent(1, false)
	if err != nil || len(items) != 2 {
		t.Fatal(items, err)
	}
	found := false
	for _, item := range items {
		if item.Type == "document" {
			found = true
			if item.Context != book.BookName || item.URL != fmt.Sprintf("/books/recent-book/edit?doc=%d", doc.DocumentID) {
				t.Fatal(item)
			}
		}
	}
	if !found {
		t.Fatal("missing chapter")
	}
	if _, err := models.DB.Exec("DELETE FROM md_documents WHERE document_id=?", doc.DocumentID); err != nil {
		t.Fatal(err)
	}
	items, err = models.ListRecentContent(1, false)
	if err != nil || len(items) != 1 {
		t.Fatal(items, err)
	}
	for id := int64(1); id <= 110; id++ {
		if err := models.RecordRecentContent(1, "blog", id, ""); err != nil {
			t.Fatal(err)
		}
	}
	var total int
	models.DB.QueryRow("SELECT COUNT(*) FROM md_recent_content WHERE member_id=1").Scan(&total)
	if total != 100 {
		t.Fatalf("history unbounded: %d", total)
	}
}
