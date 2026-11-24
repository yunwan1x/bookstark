package controllers_test

import (
	"bookstark/i18n"
	"bookstark/models"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func TestToolSourceDeletionRequiresWithdrawal(t *testing.T) {
	router, adminToken := initAssetControllerTest(t)
	member := &models.Member{Account: "guard-publisher", Password: "guard-password", Email: "guard@example.test", Role: 1, Status: 1}
	if err := member.Insert(); err != nil {
		t.Fatal(err)
	}
	token, err := models.CreateApiToken(member.MemberID, "guard-test")
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name          string
		member        int64
		token, status string
	}{
		{"published", 1, adminToken, "published"},
		{"pending", member.MemberID, token.Token, "pending"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b := &models.Blog{BlogTitle: tc.name, BlogIdentify: "source-guard-" + tc.name, BlogType: "article", EditorType: "html", MemberID: tc.member, BlogContent: "<h1>Protected source</h1>"}
			if err := b.Insert(); err != nil {
				t.Fatal(err)
			}
			id := strconv.FormatInt(b.BlogID, 10)
			publication := "/api/blogs/" + id + "/tool"
			w := adminAssetRequest(router, tc.token, "POST", publication, nil)
			if w.Code != 200 || !strings.Contains(w.Body.String(), tc.status) {
				t.Fatalf("publish %d %s", w.Code, w.Body.String())
			}
			for _, lang := range []string{"zh", "en"} {
				r := httptest.NewRequest("DELETE", "/api/blogs/"+id, nil)
				r.Header.Set("Authorization", "Token "+tc.token)
				r.AddCookie(&http.Cookie{Name: "lang", Value: lang})
				w := httptest.NewRecorder()
				router.ServeHTTP(w, r)
				translated := i18n.MakeT(lang)("market.source_delete_blocked")
				if translated == "market.source_delete_blocked" {
					t.Fatalf("missing %s deletion guidance", lang)
				}
				if w.Code != 409 || !strings.Contains(w.Body.String(), translated) {
					t.Fatalf("%s delete %d %s", lang, w.Code, w.Body.String())
				}
			}
			if err := models.DeleteBlog(b.BlogID); !errors.Is(err, models.ErrBlogUsedByTool) {
				t.Fatalf("model bypassed guard: %v", err)
			}
			if _, err := models.DB.Exec("DELETE FROM md_blogs WHERE blog_id=?", b.BlogID); err == nil || !strings.Contains(err.Error(), models.ErrBlogUsedByTool.Error()) {
				t.Fatalf("direct SQL bypassed guard: %v", err)
			}
			var trash int
			if err := models.DB.QueryRow("SELECT COUNT(*) FROM md_trash").Scan(&trash); err != nil || trash != 0 {
				t.Fatalf("blocked deletion wrote trash: %d %v", trash, err)
			}
			if w := adminAssetRequest(router, tc.token, "DELETE", publication, nil); w.Code != 200 {
				t.Fatal(w.Body.String())
			}
			if tc.status == "pending" {
				var status string
				if err := models.DB.QueryRow("SELECT status FROM md_tool_versions WHERE tool_id=?", b.BlogID).Scan(&status); err != nil || status != "withdrawn" {
					t.Fatalf("pending version not withdrawn: %s %v", status, err)
				}
			}
			if w := adminAssetRequest(router, tc.token, "DELETE", "/api/blogs/"+id, nil); w.Code != 200 {
				t.Fatalf("withdrawn source cannot be deleted: %d %s", w.Code, w.Body.String())
			}
			var remaining int
			if err := models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_versions WHERE tool_id=?", b.BlogID).Scan(&remaining); err != nil || remaining != 0 {
				t.Fatalf("withdrawn history left behind: %d %v", remaining, err)
			}
			// The next subtest must start with no recycle-bin entries.
			if _, err := models.DB.Exec("DELETE FROM md_trash"); err != nil {
				t.Fatal(err)
			}
		})
	}
}
