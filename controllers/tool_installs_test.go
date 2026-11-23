package controllers_test

import (
	"bookstark/conf"
	"bookstark/models"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestToolInstallDatabaseLifecycle(t *testing.T) {
	router, token := initAssetControllerTest(t)
	davPath := filepath.Join(t.TempDir(), "files.db")
	if err := models.InitWebDAVDB(davPath); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { models.WebDAVDB.Close(); models.WebDAVDB = nil })
	blog := &models.Blog{BlogTitle: "Database tool", BlogIdentify: "database-tool", MemberID: 1, BlogType: "article", EditorType: "html", Visibility: 1, BlogContent: "<h1>v1</h1>"}
	if err := blog.Insert(); err != nil {
		t.Fatal(err)
	}
	id := blog.BlogID
	base := "/api/tool-installs/" + strconv.FormatInt(id, 10)
	catalog := func() map[string]any {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", "/api/tool-market/"+strconv.FormatInt(id, 10), nil))
		var pkg map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &pkg); err != nil {
			t.Fatal(err)
		}
		return pkg
	}
	install := func(old *models.InstalledTool) {
		if w := adminAssetRequest(router, token, "POST", "/api/blogs/"+strconv.FormatInt(id, 10)+"/tool", nil); w.Code != 200 {
			t.Fatal(w.Body.String())
		}
		req := map[string]any{"revision": catalog()["revision"]}
		if old != nil {
			req["expected"] = old.Revision
			req["instance"] = old.Instance
		}
		w := adminAssetRequest(router, token, "PUT", base, req)
		if w.Code != 200 {
			t.Fatalf("install %d: %s", w.Code, w.Body.String())
		}
	}
	meta := func() *models.InstalledTool {
		row, err := models.GetInstalledTool(1, id)
		if err != nil {
			t.Fatal(err)
		}
		return row
	}
	guest := httptest.NewRecorder()
	router.ServeHTTP(guest, httptest.NewRequest("GET", "/api/tool-installs", nil))
	if guest.Code != 401 {
		t.Fatalf("guest: %d", guest.Code)
	}
	install(nil)
	first := meta()
	other := &models.Member{Account: "market-other", Password: "test-password", Email: "market-other@example.test", Status: 0, Role: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	otherToken, err := models.CreateApiToken(other.MemberID, "market-test")
	if err != nil {
		t.Fatal(err)
	}
	for _, part := range []string{"", "?part=runtime", "?part=data"} {
		if w := adminAssetRequest(router, otherToken.Token, "GET", base+part, nil); w.Code != 404 {
			t.Fatalf("other account accessed installation: %d", w.Code)
		}
	}

	w := adminAssetRequest(router, token, "POST", base+"/data", map[string]any{"revision": first.Revision, "instance": first.Instance, "op": "set", "key": "progress", "value": "42"})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	put := func(area, name, value string) {
		if err := models.PutToolResource(1, id, first.Revision, first.Instance, area, name, "text/plain", strings.NewReader(value)); err != nil {
			t.Fatal(err)
		}
	}
	put("assets", "old.js", "shared source")
	put("assets", "obsolete.js", "exclusive resource")
	put("data", "save.txt", "user file")
	shared, _ := models.GetDAVNode(1, first.Assets+"/old.js")
	exclusive, _ := models.GetDAVNode(1, first.Assets+"/obsolete.js")
	if _, _, err := models.PutDAVFile(1, "/original.js", "text/plain", strings.NewReader("shared source"), 1<<20, 0); err != nil {
		t.Fatal(err)
	}
	if _, err := models.DB.Exec("UPDATE md_blogs SET blog_content=? WHERE blog_id=?", "<h1>v2</h1>", id); err != nil {
		t.Fatal(err)
	}
	install(first)
	second := meta()
	if second.Revision == first.Revision || second.Instance != first.Instance {
		t.Fatal("bad current revision")
	}
	content, err := models.GetInstalledToolContent(1, id)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := models.DecodeContentForType("html", content)
	if err != nil || !strings.Contains(decoded, "<h1>v2</h1>") {
		t.Fatal("current code not replaced")
	}
	if _, err := models.GetDAVNode(1, first.Assets); !errors.Is(err, models.ErrDAVNotFound) {
		t.Fatalf("old resources remain: %v", err)
	}
	var n int
	if err := models.WebDAVDB.QueryRow("SELECT COUNT(*) FROM dav_blobs WHERE blob_id=?", *exclusive.BlobID).Scan(&n); err != nil || n != 0 {
		t.Fatal("unused blob not released")
	}
	if err := models.WebDAVDB.QueryRow("SELECT ref_count FROM dav_blobs WHERE blob_id=?", *shared.BlobID).Scan(&n); err != nil || n != 1 {
		t.Fatal("shared blob damaged")
	}
	values, err := models.GetInstalledToolValues(1, id)
	if err != nil || values["progress"] != "42" {
		t.Fatal("update lost user data")
	}
	dataPath, err := models.ToolResourcePath(second, "data", "save.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = models.GetDAVNode(1, dataPath); err != nil {
		t.Fatal("update lost data file")
	}
	if _, err = models.GetInstalledTool(2, id); err == nil {
		t.Fatal("account isolation failed")
	}
	for _, name := range []string{"../original.js", "a/../../original.js", "/../original.js"} {
		if _, err := models.ToolResourcePath(second, "data", name); err == nil {
			t.Fatal("path traversal accepted")
		}
	}
	dbPath := conf.App.DBPath
	if err := models.DB.Close(); err != nil {
		t.Fatal(err)
	}
	if err := models.InitDB(dbPath); err != nil {
		t.Fatal(err)
	}
	if row := meta(); row.Revision != second.Revision {
		t.Fatal("installation did not survive restart")
	}
	if values, err := models.GetInstalledToolValues(1, id); err != nil || values["progress"] != "42" {
		t.Fatal("data did not survive restart")
	}
	// Both stores must survive a retry when resource cleanup is temporarily unavailable.
	if err = models.WebDAVDB.Close(); err != nil {
		t.Fatal(err)
	}
	w = adminAssetRequest(router, token, "DELETE", base, map[string]string{"revision": second.Revision, "instance": second.Instance})
	if w.Code != 503 || !strings.Contains(w.Body.String(), "cleanup_pending") {
		t.Fatalf("cleanup failure hidden: %d %s", w.Code, w.Body.String())
	}
	if _, err := models.GetInstalledTool(1, id); err == nil {
		t.Fatal("uninstall retained code/data")
	}
	if err = models.InitWebDAVDB(davPath); err != nil {
		t.Fatal(err)
	}
	w = adminAssetRequest(router, token, "GET", "/api/tool-installs", nil)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if _, err := models.GetDAVNode(1, dataPath); !errors.Is(err, models.ErrDAVNotFound) {
		t.Fatal("uninstall retained files")
	}
	if _, err := models.GetDAVNode(1, "/original.js"); err != nil {
		t.Fatal("deleted source resource")
	}
	if err := models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_cleanup").Scan(&n); err != nil || n != 0 {
		t.Fatal("cleanup queue not cleared")
	}
	install(nil)
	third := meta()
	if third.Instance == first.Instance {
		t.Fatal("installation instance reused")
	}
	values, err = models.GetInstalledToolValues(1, id)
	if err != nil || len(values) != 0 {
		t.Fatal("reinstall restored deleted data")
	}
	w = adminAssetRequest(router, token, "DELETE", base, map[string]string{"revision": third.Revision, "instance": first.Instance})
	if w.Code != 409 {
		t.Fatal("stale uninstall removed fresh install")
	}
	w = adminAssetRequest(router, token, "DELETE", base, map[string]string{"revision": third.Revision, "instance": third.Instance})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
}
