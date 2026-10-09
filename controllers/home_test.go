package controllers_test

import (
	"bookstark/conf"
	"bookstark/models"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHomeSummaryIsolationOrderAndLinks(t *testing.T) {
	router, token := initAssetControllerTest(t)
	admin, _ := models.GetMemberByAccount(conf.App.AdminAccount)
	other := &models.Member{Account: "home-other", Password: "test-only", Role: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	otherToken, err := models.CreateApiToken(other.MemberID, "home-test")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 12; i++ {
		b := &models.Blog{BlogTitle: fmt.Sprintf("note-%02d", i), BlogIdentify: fmt.Sprintf("home-note-%d", i), BlogType: "note", MemberID: admin.MemberID, BlogContent: "NEVER_RETURN_CONTENT"}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
		created := time.Date(2026, 1, i+1, 12, 0, 0, 0, time.UTC)
		modified := time.Date(2026, 2, 12-i, 12, 0, 0, 0, time.UTC)
		if _, err := models.DB.Exec("UPDATE md_blogs SET create_time=?,modify_time=? WHERE blog_id=?", created, modified, b.BlogID); err != nil {
			t.Fatal(err)
		}
	}
	private := &models.Blog{BlogTitle: "OTHER_PRIVATE", BlogIdentify: "other-private", BlogType: "note", MemberID: other.MemberID}
	if err := private.Insert(); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct{ order, title string }{{"updated", "note-00"}, {"created", "note-11"}} {
		w := adminAssetRequest(router, token, "GET", "/api/home?order="+test.order, nil)
		if w.Code != 200 {
			t.Fatalf("summary: %d %s", w.Code, w.Body.String())
		}
		if !strings.Contains(w.Header().Get("Cache-Control"), "no-store") {
			t.Fatal("missing cache policy")
		}
		if strings.Contains(w.Body.String(), "OTHER_PRIVATE") || strings.Contains(w.Body.String(), "NEVER_RETURN_CONTENT") {
			t.Fatal("private content leaked")
		}
		var data struct {
			Sections []models.HomeSection `json:"sections"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &data); err != nil {
			t.Fatal(err)
		}
		if len(data.Sections) != 9 {
			t.Fatalf("admin sections %d", len(data.Sections))
		}
		notes := data.Sections[0]
		if notes.Total != 12 || len(notes.Items) != 10 || notes.Items[0].Title != test.title {
			t.Fatalf("bad pagination/sort: %+v", notes)
		}
		if !strings.HasPrefix(notes.Items[0].URL, "/notes?tab=notes&id=") || notes.Items[0].Date == "" {
			t.Fatalf("invalid row %+v", notes.Items[0])
		}
	}
	w := adminAssetRequest(router, otherToken.Token, "GET", "/api/home", nil)
	if w.Code != 200 || strings.Contains(w.Body.String(), `"key":"assets"`) || strings.Contains(w.Body.String(), "note-00") {
		t.Fatalf("nonadmin isolation: %d %s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, "GET", "/api/home?order=unsafe", nil)
	if w.Code != 400 {
		t.Fatal("invalid order accepted")
	}
	for path, want := range map[string]int{"/home": 302, "/api/home": 401} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
		if w.Code != want {
			t.Fatalf("anonymous %s = %d", path, w.Code)
		}
	}
}
