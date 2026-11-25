package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func TestToolMarketPublicPackages(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_login_required": "0"}); err != nil {
		t.Fatal(err)
	}
	var publicID int64
	for i, kind := range []string{"public", "private", "password", "markdown", "note"} {
		b := &models.Blog{BlogTitle: kind, BlogIdentify: "market-" + kind, MemberID: 1, BlogType: "article", EditorType: "html", Visibility: 1, BlogContent: "<h1>TOOL_" + kind + "</h1>"}
		if kind == "private" {
			b.Visibility = 0
		}
		if kind == "password" {
			b.Password = "secret"
		}
		if kind == "markdown" {
			b.EditorType = "markdown"
		}
		if kind == "note" {
			b.BlogType = "note"
		}
		encoded, err := models.EncodeHTMLContent(b.BlogContent)
		if err != nil {
			t.Fatal(err)
		}
		b.BlogContent = encoded
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
		before := httptest.NewRecorder()
		router.ServeHTTP(before, httptest.NewRequest("GET", "/api/tool-market/"+strconv.FormatInt(b.BlogID, 10), nil))
		if before.Code != 404 {
			t.Fatal("unpublished article listed")
		}
		pub := adminAssetRequest(router, token, "POST", "/api/blogs/"+strconv.FormatInt(b.BlogID, 10)+"/tool", nil)
		if i <= 1 && pub.Code != 200 {
			t.Fatal(pub.Body.String())
		}
		if i > 1 && pub.Code != 422 {
			t.Fatalf("invalid publication: %d", pub.Code)
		}
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", "/api/tool-market/"+strconv.FormatInt(b.BlogID, 10), nil))
		if i <= 1 {
			publicID = b.BlogID
			if w.Code != 200 || !strings.Contains(w.Body.String(), "TOOL_"+kind) || strings.Contains(w.Body.String(), "CMP:v1") {
				t.Fatalf("package %d: %s", w.Code, w.Body.String())
			}
		} else if w.Code != 404 {
			t.Fatalf("%s leaked: %d", kind, w.Code)
		}
	}
	get := func(path string) string {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 {
			t.Fatalf("%s: %d", path, w.Code)
		}
		return w.Body.String()
	}
	var catalog struct {
		Tools []struct {
			ID       int64  `json:"id"`
			Revision string `json:"revision"`
			Content  string `json:"content"`
		}
	}
	if err := json.Unmarshal([]byte(get("/api/tool-market")), &catalog); err != nil {
		t.Fatal(err)
	}
	if len(catalog.Tools) != 2 || catalog.Tools[0].ID != publicID || catalog.Tools[0].Content != "" {
		t.Fatalf("catalog %#v", catalog)
	}
	old := catalog.Tools[0].Revision
	if _, err := models.DB.Exec("UPDATE md_blogs SET blog_content=? WHERE blog_id=?", "<h1>updated</h1>", publicID); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(get("/api/tool-market"), old) {
		t.Fatal("draft changed publication")
	}
	if w := adminAssetRequest(router, token, "POST", "/api/blogs/"+strconv.FormatInt(publicID, 10)+"/tool", nil); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if strings.Contains(get("/api/tool-market"), old) {
		t.Fatal("republish did not change revision")
	}
	if _, err := models.DB.Exec("UPDATE md_blogs SET visibility=0 WHERE blog_id=?", publicID); err != nil {
		t.Fatal(err)
	}
	if len(get("/api/tool-market")) < 20 {
		t.Fatal("private source unexpectedly unpublished tool")
	}
	if w := adminAssetRequest(router, token, "DELETE", "/api/blogs/"+strconv.FormatInt(publicID, 10)+"/tool", nil); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	get("/shares?type=tool")
}
