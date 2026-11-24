package controllers_test

import (
	"bookstark/conf"
	"bookstark/models"
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestToolMarketplacePublishingAccessAndReview(t *testing.T) {
	router, adminToken := initAssetControllerTest(t)
	req := func(method, path, token string, body any) *httptest.ResponseRecorder {
		var data []byte
		if body != nil {
			data, _ = json.Marshal(body)
		}
		r := httptest.NewRequest(method, path, bytes.NewReader(data))
		r.Header.Set("Content-Type", "application/json")
		if token != "" {
			r.Header.Set("Authorization", token)
		}
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		return w
	}
	admin := "Token " + adminToken
	assertArticleTool := func(id int64, token string, want bool) {
		t.Helper()
		response := req("GET", "/api/blogs?type=article", token, nil)
		var list struct {
			Data []models.BlogWithLabels `json:"data"`
		}
		if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &list) != nil {
			t.Fatalf("article list: %d %s", response.Code, response.Body.String())
		}
		for _, article := range list.Data {
			if article.BlogID == id {
				if article.IsTool != want {
					t.Fatalf("article %d tool status = %t, want %t", id, article.IsTool, want)
				}
				return
			}
		}
		t.Fatalf("article %d missing from list", id)
	}
	post := func(id int64, token, version string) *httptest.ResponseRecorder {
		return req("POST", "/api/blogs/"+strconv.FormatInt(id, 10)+"/tool", token, map[string]any{"version": version, "title": "Published tool title", "category": "document", "permissions": map[string]bool{"read_files": true, "save_files": true}})
	}
	source := &models.Blog{BlogTitle: "Private source", BlogIdentify: "private-market-source", BlogType: "article", EditorType: "html", MemberID: 1, Visibility: 0, BlogContent: "<h1>Published HTML</h1>"}
	if err := source.Insert(); err != nil {
		t.Fatal(err)
	}
	assertArticleTool(source.BlogID, admin, false)
	preview := req("POST", "/api/blogs/"+strconv.FormatInt(source.BlogID, 10)+"/tool?preview=1", admin, map[string]any{"version": "1.0.0", "category": "document"})
	if preview.Code != 200 || !strings.Contains(preview.Body.String(), "metadata") {
		t.Fatalf("preview %d %s", preview.Code, preview.Body.String())
	}
	var previewVersions int
	if err := models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_versions WHERE tool_id=?", source.BlogID).Scan(&previewVersions); err != nil || previewVersions != 0 {
		t.Fatalf("package preview published a version: %d %v", previewVersions, err)
	}
	assertArticleTool(source.BlogID, admin, false)
	p := post(source.BlogID, admin, "1.0.0")
	if p.Code != 200 {
		t.Fatalf("publish %d %s", p.Code, p.Body.String())
	}
	assertArticleTool(source.BlogID, admin, true)
	var result struct {
		Revision string `json:"revision"`
	}
	json.Unmarshal(p.Body.Bytes(), &result)
	b, _ := models.GetBlogByID(source.BlogID)
	if b.Visibility != 0 {
		t.Fatal("tool publication made source article public")
	}
	path := "/api/tool-market/" + strconv.FormatInt(source.BlogID, 10)
	if w := req("GET", path, "", nil); w.Code != 401 {
		t.Fatalf("anonymous package %d %s", w.Code, w.Body.String())
	}
	if w := req("GET", "/api/tool-market", "", nil); w.Code != 200 || !strings.Contains(w.Body.String(), "Published tool title") {
		t.Fatal("public catalog not available")
	}
	login := req("POST", "/market/login", "", map[string]string{"account": conf.App.AdminAccount, "password": conf.App.AdminPassword})
	if login.Code != 200 {
		t.Fatal(login.Body.String())
	}
	if login.Header().Get("Set-Cookie") != "" {
		t.Fatal("market login changed workspace session")
	}
	var session struct {
		Token string `json:"token"`
	}
	json.Unmarshal(login.Body.Bytes(), &session)
	if w := req("GET", path, "Market "+session.Token, nil); w.Code != 200 || !strings.Contains(w.Body.String(), "Published HTML") {
		t.Fatalf("market credential %d %s", w.Code, w.Body.String())
	}
	if w := req("GET", "/market/versions/"+result.Revision, "Market "+session.Token, nil); w.Code != 200 || !strings.HasPrefix(w.Header().Get("Content-Type"), "application/json") {
		t.Fatal("reference manifest unavailable")
	}
	if w := req("GET", "/market/packages/"+result.Revision, admin, nil); w.Code == 200 {
		t.Fatal("removed archive download endpoint is still exposed")
	}
	if w := post(source.BlogID, admin, "1.0.0"); w.Code != 409 {
		t.Fatal("immutable version overwritten")
	}
	member := &models.Member{Account: "market-publisher", Password: "market-test-password", Email: "market-publisher@example.test", Role: 1, Status: 1}
	if err := member.Insert(); err != nil {
		t.Fatal(err)
	}
	token, err := models.CreateApiToken(member.MemberID, "publisher")
	if err != nil {
		t.Fatal(err)
	}
	own := &models.Blog{BlogTitle: "Review source", BlogIdentify: "pending-market-source", BlogType: "article", EditorType: "html", MemberID: member.MemberID, Visibility: 0, BlogContent: "<h1>Reviewed snapshot</h1>"}
	if err := own.Insert(); err != nil {
		t.Fatal(err)
	}
	pending := post(own.BlogID, "Token "+token.Token, "1.0.0")
	if pending.Code != 200 || !strings.Contains(pending.Body.String(), "pending") {
		t.Fatalf("member publication %d %s", pending.Code, pending.Body.String())
	}
	assertArticleTool(own.BlogID, "Token "+token.Token, false)
	var pendingResult struct {
		Revision string `json:"revision"`
	}
	json.Unmarshal(pending.Body.Bytes(), &pendingResult)
	if w := req("GET", "/api/tool-market/"+strconv.FormatInt(own.BlogID, 10), admin, nil); w.Code != 404 {
		t.Fatal("unreviewed tool downloadable")
	}
	if w := req("GET", "/api/tool-market/settings", "Token "+token.Token, nil); w.Code != 403 {
		t.Fatal("member accessed server market settings")
	}
	if _, err := models.DB.Exec("UPDATE md_blogs SET blog_title='Edited after submission' WHERE blog_id=?", own.BlogID); err != nil {
		t.Fatal(err)
	}
	if w := req("POST", "/api/tool-market/reviews", admin, map[string]any{"revision": pendingResult.Revision, "approve": true}); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	assertArticleTool(own.BlogID, "Token "+token.Token, true)
	if w := req("GET", "/api/tool-market/"+strconv.FormatInt(own.BlogID, 10), admin, nil); w.Code != 200 || !strings.Contains(w.Body.String(), "Published tool title") || strings.Contains(w.Body.String(), "Edited after submission") {
		t.Fatal("review did not publish the submitted snapshot")
	}
	if err := models.UpdateMemberPassword(1, "new-market-password"); err != nil {
		t.Fatal(err)
	}
	if w := req("GET", path, "Market "+session.Token, nil); w.Code != 401 {
		t.Fatal("market token survived password change")
	}
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_login_required": "0"}); err != nil {
		t.Fatal(err)
	}
	if w := req("GET", path, "", nil); w.Code != 200 {
		t.Fatal("public package policy ignored")
	}
	if w := req("DELETE", "/api/blogs/"+strconv.FormatInt(source.BlogID, 10)+"/tool", admin, nil); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	assertArticleTool(source.BlogID, admin, false)
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_enabled": "0"}); err != nil {
		t.Fatal(err)
	}
	if w := req("GET", "/api/tool-market", "", nil); w.Code != 503 {
		t.Fatal("disabled market remained available")
	}
	if w := req("GET", "/market/index.json", "", nil); w.Code != 503 {
		t.Fatal("disabled discovery remained available")
	}
	if w := req("POST", "/api/tool-market/client/test", admin, map[string]any{"url": "http://example.com/market"}); w.Code != 503 {
		t.Fatalf("connection test accepted a disabled local market: %d %s", w.Code, w.Body.String())
	}
}

func TestToolUninstallCanKeepDataWithoutRevivingOldInstance(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.InitWebDAVDB(filepath.Join(t.TempDir(), "tools.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { models.WebDAVDB.Close(); models.WebDAVDB = nil })
	b := &models.Blog{BlogTitle: "Retained", BlogIdentify: "retained-tool", BlogType: "article", EditorType: "html", MemberID: 1, Visibility: 0, BlogContent: "<h1>Retained</h1>"}
	if err := b.Insert(); err != nil {
		t.Fatal(err)
	}
	id := b.BlogID
	path := "/api/tool-installs/" + strconv.FormatInt(id, 10)
	w := adminAssetRequest(router, token, "POST", "/api/blogs/"+strconv.FormatInt(id, 10)+"/tool", nil)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	var p struct {
		Revision string `json:"revision"`
	}
	json.Unmarshal(w.Body.Bytes(), &p)
	if w := adminAssetRequest(router, token, "PUT", path, map[string]any{"revision": p.Revision}); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	first, _ := models.GetInstalledTool(1, id)
	if err := models.WriteInstalledToolValue(1, id, first.Revision, first.Instance, "set", "saved", "yes"); err != nil {
		t.Fatal(err)
	}
	if err := models.PutToolResource(1, id, first.Revision, first.Instance, "data", "kept.txt", "text/plain", strings.NewReader("kept bytes")); err != nil {
		t.Fatal(err)
	}
	if w := adminAssetRequest(router, token, "DELETE", path, map[string]any{"revision": first.Revision, "instance": first.Instance, "keep_data": true}); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if _, err := models.GetInstalledTool(1, id); err == nil {
		t.Fatal("uninstalled tool still runnable")
	}
	if w := adminAssetRequest(router, token, "PUT", path, map[string]any{"revision": p.Revision}); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	second, _ := models.GetInstalledTool(1, id)
	if second.Instance == first.Instance {
		t.Fatal("reinstall revived stale instance")
	}
	values, _ := models.GetInstalledToolValues(1, id)
	if values["saved"] != "yes" {
		t.Fatal("retained structured data lost")
	}
	filePath, err := models.ToolResourcePath(second, "data", "kept.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, _, reader, err := models.ReadDAVFileContext(t.Context(), 1, filePath); err != nil {
		t.Fatal("retained file lost", err)
	} else {
		reader.Close()
	}
	if w := adminAssetRequest(router, token, "DELETE", path, map[string]any{"revision": second.Revision, "instance": second.Instance, "keep_data": false}); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if _, _, reader, err := models.ReadDAVFileContext(t.Context(), 1, filePath); err == nil {
		reader.Close()
		t.Fatal("explicit data deletion retained old files")
	}
}
