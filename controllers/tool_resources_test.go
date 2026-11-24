package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"net/http/httptest"
	"net/url"
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
	preview := adminAssetRequest(router, token, "POST", "/api/blogs/"+id+"/tool?preview=1", nil)
	var report struct {
		Metadata  models.ToolMetadata `json:"metadata"`
		Resources []struct {
			URL     string `json:"url"`
			Kind    string `json:"kind"`
			Size    int64  `json:"size"`
			Account string `json:"account"`
			Path    string `json:"webdav_path"`
		} `json:"resources"`
	}
	if preview.Code != 200 || json.Unmarshal(preview.Body.Bytes(), &report) != nil || len(report.Resources) != 3 || report.Metadata.AssetCount != 3 {
		t.Fatalf("preview: %d %s", preview.Code, preview.Body.String())
	}
	seen := map[string]bool{}
	decoded, err := models.DecodeContentForType("html", b.BlogContent)
	if err != nil {
		t.Fatal(err)
	}
	total := int64(len(decoded))
	for _, resource := range report.Resources {
		u, err := url.Parse(resource.URL)
		if err != nil || !strings.HasPrefix(u.Path, "/dav-public/admin/") || resource.Kind != "webdav" || resource.Account != "admin" || resource.Path != "/"+strings.TrimPrefix(u.Path, "/dav-public/admin/") || resource.Size <= 0 || seen[resource.URL] {
			t.Fatalf("incorrect preview resource: %+v", resource)
		}
		seen[resource.URL] = true
		total += resource.Size
	}
	if total != report.Metadata.Size {
		t.Fatalf("preview total: %d != %d", total, report.Metadata.Size)
	}
	var previewCount int
	if err := models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_versions WHERE blog_id=?", b.BlogID).Scan(&previewCount); err != nil || previewCount != 0 {
		t.Fatalf("preview created a publication: %d %v", previewCount, err)
	}
	revision := publish()
	var referencedHTML, resourceBase string
	if err := models.DB.QueryRow("SELECT content,resource_base FROM md_tool_versions WHERE blog_id=?", b.BlogID).Scan(&referencedHTML, &resourceBase); err != nil || !strings.Contains(referencedHTML, "/dav-public/admin/app.js") || resourceBase == "" {
		t.Fatalf("publication lost original references: html=%s base=%s err=%v", referencedHTML, resourceBase, err)
	}
	// Installation reads the original resource as it exists at installation time.
	put("app.js", "text/javascript", `window.loadedFromLocal="changed-after-publication";`)
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
	for _, p := range paths {
		if strings.HasSuffix(p, ".js") {
			resource := httptest.NewRecorder()
			router.ServeHTTP(resource, httptest.NewRequest("GET", p, nil))
			if !strings.Contains(resource.Body.String(), "changed-after-publication") {
				t.Fatal("installer read a frozen resource copy")
			}
		}
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
	// Dependency failure aborts publication, keeping the installed and published versions intact.
	failed := adminAssetRequest(router, token, "POST", "/api/blogs/"+id+"/tool", nil)
	if failed.Code != 422 {
		t.Fatalf("missing dependencies published: %d", failed.Code)
	}
	same, _ := models.GetInstalledTool(1, b.BlogID)
	if same.Revision != revision {
		t.Fatal("failed publication changed installed version")
	}
	// Restore sources, update, and confirm obsolete asset URLs are gone.
	put("image.svg", "image/svg+xml", `<svg xmlns="http://www.w3.org/2000/svg"><title>v2</title></svg>`)
	put("theme.css", "text/css", `body{background:url('./image.svg')}`)
	put("app.js", "text/javascript", `window.loadedFromLocal=2;`)
	revision2 := publish()
	if err := models.DeleteDAVNode(1, "/app.js", true); err != nil {
		t.Fatal(err)
	}
	failedUpdate := adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": revision2, "expected": meta.Revision, "instance": meta.Instance})
	if failedUpdate.Code != 422 {
		t.Fatalf("missing original resource installed: %d %s", failedUpdate.Code, failedUpdate.Body.String())
	}
	unchanged, _ := models.GetInstalledTool(1, b.BlogID)
	if unchanged.Revision != meta.Revision || unchanged.Assets != meta.Assets {
		t.Fatal("failed download replaced the working installation")
	}
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
