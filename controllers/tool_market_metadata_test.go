package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func TestToolMarketMetadataDoesNotReadHTMLBeforeAuthorization(t *testing.T) {
	router, token := initAssetControllerTest(t)
	b := &models.Blog{BlogTitle: "Metadata only", BlogIdentify: "metadata-only", BlogType: "article", EditorType: "html", MemberID: 1, BlogContent: "<h1>Referenced content</h1>"}
	if err := b.Insert(); err != nil {
		t.Fatal(err)
	}
	id := strconv.FormatInt(b.BlogID, 10)
	w := adminAssetRequest(router, token, "POST", "/api/blogs/"+id+"/tool", map[string]any{"version": "1.0.0"})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	// Metadata and permission checks must not load the HTML body. Oversized HTML
	// makes an accidental body read observable.
	if _, err := models.DB.Exec("UPDATE md_tool_versions SET content=? WHERE blog_id=?", strings.Repeat("x", (20<<20)+1), b.BlogID); err != nil {
		t.Fatal(err)
	}
	path := "/api/tool-market/" + id
	for _, suffix := range []string{"", "?metadata=1"} {
		anonymous := httptest.NewRecorder()
		router.ServeHTTP(anonymous, httptest.NewRequest("GET", path+suffix, nil))
		if anonymous.Code != 401 {
			t.Fatalf("anonymous HTML inspected before authorization: %d %s", anonymous.Code, anonymous.Body.String())
		}
	}
	manifest := adminAssetRequest(router, token, "GET", path+"?metadata=1", nil)
	if manifest.Code != 200 {
		t.Fatalf("metadata depended on the HTML body: %d %s", manifest.Code, manifest.Body.String())
	}
	var metadata map[string]any
	if err := json.Unmarshal(manifest.Body.Bytes(), &metadata); err != nil {
		t.Fatal(err)
	}
	if metadata["version"] != "1.0.0" || metadata["distribution"] != "references" || metadata["content"] != nil || metadata["resources"] != nil {
		t.Fatalf("unexpected manifest: %#v", metadata)
	}
	if full := adminAssetRequest(router, token, "GET", path, nil); full.Code != 404 {
		t.Fatalf("oversized HTML was not rejected: %d", full.Code)
	}
	if _, err := models.DB.Exec(`UPDATE md_tool_versions SET metadata=json_set(metadata,'$.access','members','$.members',json('[999999]')) WHERE blog_id=?`, b.BlogID); err != nil {
		t.Fatal(err)
	}
	install := adminAssetRequest(router, token, "PUT", "/api/tool-installs/"+id, map[string]any{"revision": metadata["revision"]})
	if install.Code != 403 {
		t.Fatalf("install inspected HTML before member policy: %d %s", install.Code, install.Body.String())
	}
}
