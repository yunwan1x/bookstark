package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func TestToolDownloadedResourcesSurviveSourceRemoval(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.InitWebDAVDB(filepath.Join(t.TempDir(), "files.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { models.WebDAVDB.Close(); models.WebDAVDB = nil })
	if _, err := models.EnsureDAVRoot(1); err != nil {
		t.Fatal(err)
	}
	put := func(name, mime, content string) {
		node, _, err := models.PutDAVFile(1, "/"+name, mime, strings.NewReader(content), 20<<20, 100<<20)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = models.CreateOrUpdateDAVPublicAsset(1, node.NodeID, "/"+name); err != nil {
			t.Fatal(err)
		}
	}
	put("image.svg", "image/svg+xml", `<svg xmlns="http://www.w3.org/2000/svg"/>`)
	put("theme.css", "text/css", `body{background-image:url('./image.svg')}`)
	put("app.js", "text/javascript", `window.loadedFromLocal=true;`)
	b := &models.Blog{BlogTitle: "Download", BlogIdentify: "download", MemberID: 1, BlogType: "article", EditorType: "html", Visibility: 1, BlogContent: `<link rel="stylesheet" href="/dav-public/admin/theme.css"><img src="/dav-public/admin/image.svg"><script src="/dav-public/admin/app.js"></script>`}
	if err := b.Insert(); err != nil {
		t.Fatal(err)
	}
	id := strconv.FormatInt(b.BlogID, 10)
	base := "/api/tool-installs/" + id
	publish := func() string {
		w := adminAssetRequest(router, token, "POST", "/api/blogs/"+id+"/tool", nil)
		if w.Code != 200 {
			t.Fatal(w.Body.String())
		}
		var x map[string]any
		json.Unmarshal(w.Body.Bytes(), &x)
		return x["revision"].(string)
	}
	revision := publish()
	// Publishing must not create an installation resource copy.
	var count int
	models.WebDAVDB.QueryRow("SELECT COUNT(*) FROM dav_nodes WHERE path LIKE '/BookStark/tools/%'").Scan(&count)
	if count != 0 {
		t.Fatal("publication copied assets")
	}
	w := adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": revision})
	if w.Code != 200 {
		t.Fatalf("install: %d %s", w.Code, w.Body.String())
	}
	meta, err := models.GetInstalledTool(1, b.BlogID)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := models.GetInstalledToolContent(1, b.BlogID)
	content, _ := models.DecodeContentForType("html", raw)
	if strings.Contains(content, "/dav-public/") {
		t.Fatal("source addresses remain")
	}
	paths := regexp.MustCompile(`/api/tool-assets/[^"\s<>]+`).FindAllString(content, -1)
	if len(paths) != 3 {
		t.Fatalf("assets: %s", content)
	}
	for _, name := range []string{"image.svg", "theme.css", "app.js"} {
		if err := models.DeleteDAVNode(1, "/"+name, true); err != nil {
			t.Fatal(err)
		}
	}
	get := func(p string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", p, nil))
		return w
	}
	for _, p := range paths {
		w := get(p)
		if w.Code != 200 {
			t.Fatalf("installed resource depends on source: %s %d", p, w.Code)
		}
		if w.Header().Get("Access-Control-Allow-Origin") != "*" {
			t.Fatal("sandbox resource blocked")
		}
		if strings.HasSuffix(p, ".css") && !strings.Contains(w.Body.String(), "/api/tool-assets/") {
			t.Fatal("nested CSS not rewritten")
		}
	}
	// Missing resources abort an update and keep the previous working code/files.
	revision2 := publish()
	w = adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": revision2, "expected": meta.Revision, "instance": meta.Instance})
	if w.Code != 422 {
		t.Fatalf("failed download accepted %d", w.Code)
	}
	same, _ := models.GetInstalledTool(1, b.BlogID)
	if same.Revision != revision {
		t.Fatal("failed update replaced installation")
	}
	// Restore sources, update, and confirm obsolete asset URLs are gone.
	put("image.svg", "image/svg+xml", `<svg xmlns="http://www.w3.org/2000/svg"><title>v2</title></svg>`)
	put("theme.css", "text/css", `body{background:url('./image.svg')}`)
	put("app.js", "text/javascript", `window.loadedFromLocal=2;`)
	w = adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": revision2, "expected": meta.Revision, "instance": meta.Instance})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	for _, p := range paths {
		if get(p).Code != 404 {
			t.Fatal("old resource still accessible")
		}
	}
	latest, _ := models.GetInstalledTool(1, b.BlogID)
	w = adminAssetRequest(router, token, "DELETE", base, map[string]any{"revision": latest.Revision, "instance": latest.Instance})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if _, err := models.GetDAVNode(1, latest.Assets); err == nil {
		t.Fatal("uninstall left resources")
	}
	if get("/dav-public/admin/app.js").Code != 200 {
		t.Fatal("uninstall deleted source")
	}
	var pending int
	models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_cleanup").Scan(&pending)
	if pending != 0 {
		t.Fatal("staging cleanup leaked")
	}
}
