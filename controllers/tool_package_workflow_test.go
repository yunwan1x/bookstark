package controllers_test

import (
	"archive/zip"
	"bookstark/conf"
	"bookstark/internal/toolpackage"
	"bookstark/middleware"
	"bookstark/models"
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
)

type packageWorkflowUpload struct {
	ID      int64              `json:"id"`
	Package models.ToolPackage `json:"package"`
}

type packageWorkflowPublication struct {
	ID       int64               `json:"id"`
	Revision string              `json:"revision"`
	Metadata models.ToolMetadata `json:"metadata"`
}

func initPackageWorkflow(t *testing.T) (http.Handler, string) {
	t.Helper()
	router, token := initAssetControllerTest(t)
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_enabled": "1", "tool_market_login_required": "0", "tool_market_review_required": "0", "tool_market_members_publish": "1"}); err != nil {
		t.Fatal(err)
	}
	if err := models.InitWebDAVDB(filepath.Join(t.TempDir(), "package-files.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if models.WebDAVDB != nil {
			_ = models.WebDAVDB.Close()
			models.WebDAVDB = nil
		}
	})
	return router, token
}

func packageWorkflowZIP(t *testing.T, files map[string][]byte) []byte {
	t.Helper()
	var data bytes.Buffer
	w := zip.NewWriter(&data)
	for name, body := range files {
		f, err := w.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = f.Write(body); err != nil {
			t.Fatal(err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return data.Bytes()
}

func packageWorkflowFiles(entry, version string) map[string][]byte {
	return map[string][]byte{
		"tool.json":              []byte(`{"title":"Packaged terminal","version":"` + version + `","category":"development","entry":"` + entry + `","permissions":{"schema":1,"read_files":true,"save_files":true}}`),
		entry:                    []byte(`<html><head><script type="module" src="./assets/main.js"></script></head><body>Package ` + version + `</body></html>`),
		"assets/main.js":         []byte(`new Worker('./worker.js',{type:'module'});`),
		"assets/worker.js":       []byte(`fetch('./protocol.wasm');`),
		"assets/protocol.wasm":   {'\x00', 'a', 's', 'm', 1, 0, 0, 0},
		"data/unreferenced.json": []byte(`{"preserved":true}`),
	}
}

func packageWorkflowUploadRequest(t *testing.T, router http.Handler, token string, files map[string][]byte, id int64, cookies []*http.Cookie, csrf string) *httptest.ResponseRecorder {
	t.Helper()
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	if id != 0 {
		if err := w.WriteField("tool_id", strconv.FormatInt(id, 10)); err != nil {
			t.Fatal(err)
		}
	}
	f, err := w.CreateFormFile("file", "tool.zip")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.Write(packageWorkflowZIP(t, files)); err != nil {
		t.Fatal(err)
	}
	if err = w.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/api/tool-packages", &body)
	req.Header.Set("Content-Type", w.FormDataContentType())
	if token != "" {
		req.Header.Set("Authorization", "Token "+token)
	}
	for _, cookie := range cookies {
		req.AddCookie(cookie)
	}
	if csrf != "" {
		req.Header.Set("X-CSRF-Token", csrf)
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)
	return response
}

func packageWorkflowUploadOK(t *testing.T, router http.Handler, token string, files map[string][]byte, id int64) packageWorkflowUpload {
	t.Helper()
	w := packageWorkflowUploadRequest(t, router, token, files, id, nil, "")
	var result packageWorkflowUpload
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &result) != nil || result.ID <= 0 || len(result.Package.Token) != 32 {
		t.Fatalf("upload: %d %s", w.Code, w.Body.String())
	}
	return result
}

func packageWorkflowPayload(upload packageWorkflowUpload, version, access string) map[string]any {
	return map[string]any{"title": "Packaged terminal", "description": "Static package with a complete resource tree", "version": version, "category": "development", "access": access, "package": upload.Package.Token, "entry": upload.Package.Entry, "permissions": map[string]any{"schema": 1, "read_files": true, "save_files": true}}
}

func packageWorkflowPublish(t *testing.T, router http.Handler, token string, upload packageWorkflowUpload, version, access string) packageWorkflowPublication {
	t.Helper()
	w := adminAssetRequest(router, token, "POST", "/api/tool-publications/"+strconv.FormatInt(upload.ID, 10), packageWorkflowPayload(upload, version, access))
	var result packageWorkflowPublication
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &result) != nil || result.ID != upload.ID || len(result.Revision) != 64 {
		t.Fatalf("publish: %d %s", w.Code, w.Body.String())
	}
	return result
}

func packageWorkflowGet(router http.Handler, token, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest("GET", path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Token "+token)
	}
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func TestToolPackageWorkflowPublishesInstallsAndUpdatesWithoutArticles(t *testing.T) {
	router, token := initPackageWorkflow(t)
	var articleCount int
	if err := models.DB.QueryRow(`SELECT COUNT(*) FROM md_blogs`).Scan(&articleCount); err != nil {
		t.Fatal(err)
	}
	files := packageWorkflowFiles("index.html", "1.0.0")
	upload := packageWorkflowUploadOK(t, router, token, files, 0)
	source, err := models.GetToolSource(upload.ID)
	if err != nil || source.Kind != "package" || source.BlogID.Valid {
		t.Fatalf("upload has article dependency: %+v %v", source, err)
	}
	page := packageWorkflowGet(router, token, "/market/packages/"+strconv.FormatInt(upload.ID, 10)+"?package="+upload.Package.Token)
	if page.Code != 200 || !strings.Contains(page.Body.String(), "Packaged terminal") {
		t.Fatalf("settings page: %d %s", page.Code, page.Body.String())
	}
	preview := adminAssetRequest(router, token, "POST", "/api/tool-publications/"+strconv.FormatInt(upload.ID, 10)+"?preview=1", packageWorkflowPayload(upload, "1.0.0", "public"))
	if preview.Code != 200 {
		t.Fatalf("preview: %d %s", preview.Code, preview.Body.String())
	}
	var versions int
	if err := models.DB.QueryRow(`SELECT COUNT(*) FROM md_tool_versions WHERE tool_id=?`, upload.ID).Scan(&versions); err != nil || versions != 0 {
		t.Fatalf("preview published: %d %v", versions, err)
	}
	pub := packageWorkflowPublish(t, router, token, upload, "1.0.0", "public")
	if pub.Metadata.Distribution != "files" || pub.Metadata.SourceKind != "package" || pub.Metadata.AssetCount != len(files) {
		t.Fatalf("incomplete package metadata: %+v", pub.Metadata)
	}
	var after int
	if err := models.DB.QueryRow(`SELECT COUNT(*) FROM md_blogs`).Scan(&after); err != nil || after != articleCount {
		t.Fatalf("package publication created article: before=%d after=%d %v", articleCount, after, err)
	}
	var manifest struct {
		models.ToolMetadata
		Files   []toolpackage.File `json:"files"`
		Content string             `json:"content"`
	}
	w := packageWorkflowGet(router, "", "/api/tool-market/"+strconv.FormatInt(upload.ID, 10))
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &manifest) != nil || len(manifest.Files) != len(files) {
		t.Fatalf("manifest lost files: %d %s", w.Code, w.Body.String())
	}
	base := "/api/tool-installs/" + strconv.FormatInt(upload.ID, 10)
	w = adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": pub.Revision, "hash": pub.Metadata.Hash})
	if w.Code != 200 {
		t.Fatalf("install: %d %s", w.Code, w.Body.String())
	}
	first, err := models.GetInstalledTool(1, upload.ID)
	if err != nil {
		t.Fatal(err)
	}
	for name, expected := range files {
		_, _, reader, err := models.ReadDAVFileContext(context.Background(), 1, first.Assets+"/"+name)
		if err != nil {
			t.Fatalf("installed resource missing %s: %v", name, err)
		}
		got, readErr := io.ReadAll(reader)
		reader.Close()
		if readErr != nil || !bytes.Equal(got, expected) {
			t.Fatalf("installed resource changed %s: %q %v", name, got, readErr)
		}
	}
	w = adminAssetRequest(router, token, "POST", base+"/data", map[string]any{"revision": first.Revision, "instance": first.Instance, "op": "set", "key": "progress", "value": "saved"})
	if w.Code != 200 {
		t.Fatalf("save value: %d %s", w.Code, w.Body.String())
	}
	if err := models.PutToolResource(1, upload.ID, first.Revision, first.Instance, "data", "saved.txt", "text/plain", strings.NewReader("user file")); err != nil {
		t.Fatal(err)
	}
	secondUpload := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.1"), upload.ID)
	if secondUpload.ID != upload.ID {
		t.Fatal("upgrade changed tool identity")
	}
	secondPub := packageWorkflowPublish(t, router, token, secondUpload, "1.0.1", "public")
	w = adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": secondPub.Revision, "hash": secondPub.Metadata.Hash, "expected": first.Revision, "instance": first.Instance})
	if w.Code != 200 {
		t.Fatalf("upgrade: %d %s", w.Code, w.Body.String())
	}
	current, err := models.GetInstalledTool(1, upload.ID)
	if err != nil || current.Instance != first.Instance || current.Revision == first.Revision || current.Assets == first.Assets {
		t.Fatalf("invalid upgrade: %+v %v", current, err)
	}
	values, err := models.GetInstalledToolValues(1, upload.ID)
	if err != nil || values["progress"] != "saved" {
		t.Fatalf("upgrade lost values: %v %v", values, err)
	}
	path, err := models.ToolResourcePath(current, "data", "saved.txt")
	if err != nil {
		t.Fatal(err)
	}
	_, _, reader, err := models.ReadDAVFileContext(context.Background(), 1, path)
	if err != nil {
		t.Fatal(err)
	}
	saved, err := io.ReadAll(reader)
	reader.Close()
	if err != nil || string(saved) != "user file" {
		t.Fatalf("upgrade lost saved file: %q %v", saved, err)
	}
}

func TestToolPackageWorkflowArticleIdentityCollision(t *testing.T) {
	router, token := initPackageWorkflow(t)
	upload := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	article := &models.Blog{BlogTitle: "Later article", BlogIdentify: "later-package-collision", MemberID: 1, EditorType: "html", BlogType: "article", BlogContent: "<h1>Article</h1>"}
	if err := article.Insert(); err != nil {
		t.Fatal(err)
	}
	if article.BlogID != upload.ID {
		t.Fatalf("fixture did not create ID collision: blog=%d package=%d", article.BlogID, upload.ID)
	}
	w := adminAssetRequest(router, token, "POST", "/api/blogs/"+strconv.FormatInt(article.BlogID, 10)+"/tool", map[string]any{"version": "1.0.0", "category": "development", "access": "public"})
	var pub packageWorkflowPublication
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &pub) != nil || pub.ID == upload.ID {
		t.Fatalf("article collided with package: %d %s", w.Code, w.Body.String())
	}
	if resolved, err := models.ArticleToolID(article.BlogID); err != nil || resolved != pub.ID {
		t.Fatalf("article mapping incorrect: %d %v", resolved, err)
	}
	if source, err := models.GetToolSource(upload.ID); err != nil || source.Kind != "package" || source.BlogID.Valid {
		t.Fatalf("article replaced package: %+v %v", source, err)
	}
	packageWorkflowPublish(t, router, token, upload, "1.0.0", "public")
	for _, id := range []int64{upload.ID, pub.ID} {
		if w := packageWorkflowGet(router, "", "/api/tool-market/"+strconv.FormatInt(id, 10)); w.Code != 200 {
			t.Fatalf("independent tool unavailable %d: %d %s", id, w.Code, w.Body.String())
		}
	}
}

func TestToolPackageWorkflowAuthorizationValidationAndCSRF(t *testing.T) {
	router, adminToken := initPackageWorkflow(t)
	files := packageWorkflowFiles("index.html", "1.0.0")
	if w := packageWorkflowUploadRequest(t, router, "", files, 0, nil, ""); w.Code != 401 {
		t.Fatalf("guest upload: %d %s", w.Code, w.Body.String())
	}
	jwt, err := middleware.GenerateToken(1, conf.App.AdminAccount, middleware.RoleAdmin)
	if err != nil {
		t.Fatal(err)
	}
	cookies := []*http.Cookie{{Name: "token", Value: jwt}, {Name: "csrf_token", Value: "upload-csrf"}}
	if w := packageWorkflowUploadRequest(t, router, "", files, 0, cookies, ""); w.Code != 403 || !strings.Contains(w.Body.String(), "csrf_error") {
		t.Fatalf("cookie upload missing CSRF accepted: %d %s", w.Code, w.Body.String())
	}
	w := packageWorkflowUploadRequest(t, router, "", files, 0, cookies, "upload-csrf")
	var upload packageWorkflowUpload
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &upload) != nil {
		t.Fatalf("cookie upload with CSRF failed: %d %s", w.Code, w.Body.String())
	}
	other := &models.Member{Account: "other-package-owner", Password: "password", Email: "other-package-owner@example.test", Role: 1, Status: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	apiToken, err := models.CreateApiToken(other.MemberID, "package-test")
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"/api/tool-packages/" + upload.Package.Token, "/api/tool-publications/" + strconv.FormatInt(upload.ID, 10) + "?package=" + upload.Package.Token, "/market/packages/" + strconv.FormatInt(upload.ID, 10) + "?package=" + upload.Package.Token} {
		want := http.StatusForbidden
		if strings.HasPrefix(path, "/market/") {
			want = http.StatusFound // Existing forbidden-page behavior redirects to home.
		}
		if w := packageWorkflowGet(router, apiToken.Token, path); w.Code != want || (want == http.StatusFound && w.Header().Get("Location") != "/") {
			t.Fatalf("other owner read %s: %d %s", path, w.Code, w.Body.String())
		}
	}
	if w := packageWorkflowUploadRequest(t, router, apiToken.Token, files, upload.ID, nil, ""); w.Code != 403 {
		t.Fatalf("other owner replaced tool: %d %s", w.Code, w.Body.String())
	}
	if w := adminAssetRequest(router, apiToken.Token, "POST", "/api/tool-publications/"+strconv.FormatInt(upload.ID, 10), packageWorkflowPayload(upload, "1.0.0", "public")); w.Code != 403 {
		t.Fatalf("other owner published tool: %d %s", w.Code, w.Body.String())
	}
	for _, tc := range []struct {
		name  string
		files map[string][]byte
		want  string
	}{
		{name: "missing entry", files: map[string][]byte{"main.js": []byte("export default 1")}, want: "missing_entry"},
		{name: "unsafe path", files: map[string][]byte{"index.html": []byte("<h1>Tool</h1>"), "../escape.js": nil}, want: "unsafe_archive_path"},
		{name: "invalid manifest", files: map[string][]byte{"index.html": nil, "tool.json": []byte(`{"entry":`)}, want: "invalid_tool_manifest"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if w := packageWorkflowUploadRequest(t, router, adminToken, tc.files, 0, nil, ""); w.Code != 422 || !strings.Contains(w.Body.String(), tc.want) {
				t.Fatalf("invalid upload: %d %s", w.Code, w.Body.String())
			}
		})
	}
	payload := packageWorkflowPayload(upload, "1.0.0", "public")
	payload["entry"] = "missing.html"
	if w := adminAssetRequest(router, adminToken, "POST", "/api/tool-publications/"+strconv.FormatInt(upload.ID, 10), payload); w.Code != 422 || !strings.Contains(w.Body.String(), "invalid_entry") {
		t.Fatalf("invalid entry published: %d %s", w.Code, w.Body.String())
	}
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_members_publish": "0"}); err != nil {
		t.Fatal(err)
	}
	if w := packageWorkflowUploadRequest(t, router, apiToken.Token, files, 0, nil, ""); w.Code != 403 {
		t.Fatalf("disabled member publishing allowed upload: %d %s", w.Code, w.Body.String())
	}
}

func TestToolPackageWorkflowSourceVisibilityAndWithdrawal(t *testing.T) {
	router, token := initPackageWorkflow(t)
	first := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	firstPub := packageWorkflowPublish(t, router, token, first, "1.0.0", "public")
	firstURL := "/api/tool-package-assets/" + first.Package.Token + "/assets/protocol.wasm?revision=" + firstPub.Revision
	if w := packageWorkflowGet(router, "", firstURL); w.Code != 200 || w.Header().Get("Content-Type") != "application/wasm" {
		t.Fatalf("public source: %d %s", w.Code, w.Body.String())
	}
	second := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.1"), first.ID)
	secondPub := packageWorkflowPublish(t, router, token, second, "1.0.1", "login")
	secondURL := "/api/tool-package-assets/" + second.Package.Token + "/assets/protocol.wasm?revision=" + secondPub.Revision
	// Superseded package version is pruned immediately on new publish.
	if w := packageWorkflowGet(router, token, firstURL); w.Code != 404 {
		t.Fatalf("superseded package still downloadable: %d %s", w.Code, w.Body.String())
	}
	if w := packageWorkflowGet(router, "", secondURL); w.Code != 401 {
		t.Fatalf("latest policy bypassed %s: %d %s", secondURL, w.Code, w.Body.String())
	}
	if w := packageWorkflowGet(router, token, secondURL); w.Code != 200 {
		t.Fatalf("authorized source denied %s: %d %s", secondURL, w.Code, w.Body.String())
	}
	third := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.2"), first.ID)
	thirdPub := packageWorkflowPublish(t, router, token, third, "1.0.2", "public")
	thirdURL := "/api/tool-package-assets/" + third.Package.Token + "/assets/protocol.wasm?revision=" + thirdPub.Revision
	if w := packageWorkflowGet(router, token, secondURL); w.Code != 404 {
		t.Fatalf("superseded private package still downloadable: %d %s", w.Code, w.Body.String())
	}
	if w := packageWorkflowGet(router, "", thirdURL); w.Code != 200 {
		t.Fatalf("latest public source unavailable: %d %s", w.Code, w.Body.String())
	}
	if w := adminAssetRequest(router, token, "DELETE", "/api/tool-publications/"+strconv.FormatInt(first.ID, 10), nil); w.Code != 200 {
		t.Fatalf("withdrawal: %d %s", w.Code, w.Body.String())
	}
	for _, path := range []string{firstURL, secondURL, thirdURL} {
		if w := packageWorkflowGet(router, token, path); w.Code != 404 {
			t.Fatalf("withdrawn source still downloadable %s: %d %s", path, w.Code, w.Body.String())
		}
	}
}

func TestToolPackageWorkflowHTMEntryInstalls(t *testing.T) {
	router, token := initPackageWorkflow(t)
	upload := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("tool.htm", "1.0.0"), 0)
	pub := packageWorkflowPublish(t, router, token, upload, "1.0.0", "public")
	if w := adminAssetRequest(router, token, "PUT", "/api/tool-installs/"+strconv.FormatInt(upload.ID, 10), map[string]any{"revision": pub.Revision, "hash": pub.Metadata.Hash}); w.Code != 200 {
		t.Fatalf("accepted HTM entry cannot install: %d %s", w.Code, w.Body.String())
	}
}

func TestToolPackageWorkflowResourceURLsBindExactVersionAndMembership(t *testing.T) {
	router, token := initPackageWorkflow(t)
	upload := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	fileURL := "/api/tool-package-assets/" + upload.Package.Token + "/assets/protocol.wasm"
	if w := packageWorkflowGet(router, token, fileURL); w.Code != 404 {
		t.Fatalf("unpublished package was downloadable: %d %s", w.Code, w.Body.String())
	}
	member := &models.Member{Account: "package-resource-member", Password: "password", Email: "package-resource-member@example.test", Role: 1, Status: 1}
	if err := member.Insert(); err != nil {
		t.Fatal(err)
	}
	memberToken, err := models.CreateApiToken(member.MemberID, "resource-member")
	if err != nil {
		t.Fatal(err)
	}
	path := "/api/tool-publications/" + strconv.FormatInt(upload.ID, 10)
	privatePayload := packageWorkflowPayload(upload, "1.0.0", "members")
	privatePayload["member_accounts"] = []string{member.Account}
	w := adminAssetRequest(router, token, "POST", path, privatePayload)
	var private packageWorkflowPublication
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &private) != nil {
		t.Fatalf("members publication: %d %s", w.Code, w.Body.String())
	}
	privateURL := fileURL + "?revision=" + private.Revision
	for _, tc := range []struct {
		token string
		want  int
	}{{"", 401}, {token, 403}, {memberToken.Token, 200}} {
		if w := packageWorkflowGet(router, tc.token, privateURL); w.Code != tc.want {
			t.Fatalf("members resource authorization: got=%d want=%d %s", w.Code, tc.want, w.Body.String())
		}
	}
	// Reuse the exact same staged bytes in a new public version. Revision-qualified
	// URLs must avoid whichever-version-happened-to-be-first policy selection.
	public := packageWorkflowPublish(t, router, token, upload, "1.0.1", "public")
	publicURL := fileURL + "?revision=" + public.Revision
	if w := packageWorkflowGet(router, "", publicURL); w.Code != 200 {
		t.Fatalf("current public reuse denied by historical private policy: %d %s", w.Code, w.Body.String())
	}
	if w := packageWorkflowGet(router, "", privateURL); w.Code != 401 {
		t.Fatalf("private history policy lost after public update: %d %s", w.Code, w.Body.String())
	}
	for _, invalid := range []string{fileURL, fileURL + "?revision=" + strings.Repeat("f", 64)} {
		if w := packageWorkflowGet(router, token, invalid); w.Code != 404 {
			t.Fatalf("unbound source request accepted: %s %d", invalid, w.Code)
		}
	}
	other := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	otherPub := packageWorkflowPublish(t, router, token, other, "1.0.0", "public")
	if w := packageWorkflowGet(router, token, fileURL+"?revision="+otherPub.Revision); w.Code != 404 {
		t.Fatalf("revision from another tool unlocked package: %d %s", w.Code, w.Body.String())
	}
}

func TestToolPackageWorkflowReplacementHydratesNewManifestVersionAndPermissions(t *testing.T) {
	router, token := initPackageWorkflow(t)
	first := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	packageWorkflowPublish(t, router, token, first, "1.0.0", "public")
	files := packageWorkflowFiles("index.html", "2.0.0")
	files["tool.json"] = []byte(`{"title":"Updated terminal","version":"2.0.0","category":"development","entry":"index.html","permissions":{"schema":1,"socket_tcp":true,"camera":true,"read_files":true,"save_files":true}}`)
	next := packageWorkflowUploadOK(t, router, token, files, first.ID)
	url := "/api/tool-publications/" + strconv.FormatInt(first.ID, 10) + "?package=" + next.Package.Token
	w := packageWorkflowGet(router, token, url)
	var result struct {
		Metadata           models.ToolMetadata `json:"metadata"`
		ManifestVersion    string              `json:"manifest_version"`
		PermissionsChanged bool                `json:"permissions_changed"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &result) != nil {
		t.Fatalf("replacement metadata: %d %s", w.Code, w.Body.String())
	}
	if result.Metadata.Version != "2.0.0" || result.ManifestVersion != "2.0.0" || result.Metadata.Title != "Updated terminal" || !result.Metadata.Permissions.SocketTCP || !result.Metadata.Permissions.Camera || !result.PermissionsChanged {
		t.Fatalf("replacement reused stale manifest: %+v", result)
	}
	page := packageWorkflowGet(router, token, "/market/packages/"+strconv.FormatInt(first.ID, 10)+"?package="+next.Package.Token)
	if page.Code != 200 {
		t.Fatalf("replacement settings page: %d %s", page.Code, page.Body.String())
	}
	for _, expected := range []string{`id="publishVersion" name="version" type="text" value="2.0.0"`, `data-tool-permission="socket_tcp" checked`} {
		if !strings.Contains(page.Body.String(), expected) {
			t.Fatalf("new manifest setting not visible %q: %s", expected, page.Body.String())
		}
	}
}

func TestToolPackageWorkflowFailedIdentitySaveDiscardsUploadedFiles(t *testing.T) {
	router, token := initPackageWorkflow(t)
	if _, err := models.DB.Exec(`CREATE TRIGGER fail_tool_identity BEFORE INSERT ON md_tools BEGIN SELECT RAISE(ABORT,'simulated identity failure'); END`); err != nil {
		t.Fatal(err)
	}
	w := packageWorkflowUploadRequest(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0, nil, "")
	if w.Code != 500 {
		t.Fatalf("simulated save failure: %d %s", w.Code, w.Body.String())
	}
	var count int
	if err := models.DB.QueryRow(`SELECT COUNT(*) FROM md_tool_packages`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("identity failure leaked package metadata: %d %v", count, err)
	}
	if err := models.WebDAVDB.QueryRow(`SELECT COUNT(*) FROM dav_nodes WHERE is_dir=0`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("identity failure leaked package files: %d %v", count, err)
	}
}

func TestToolPackageWorkflowInstallsRemotePackageWithCompleteVerifiedTree(t *testing.T) {
	router, token := initPackageWorkflow(t)
	var mu sync.Mutex
	downloads := map[string]int{}
	var revision string
	market := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/tool-package-assets/") {
			mu.Lock()
			downloads[r.URL.Path]++
			mu.Unlock()
			if r.URL.Query().Get("revision") != revision {
				t.Errorf("remote resource was not bound to consented revision: %s", r.URL.String())
			}
			if r.Header.Get("Cookie") != "" {
				t.Error("workspace cookie leaked to remote resource server")
			}
		}
		router.ServeHTTP(w, r)
	}))
	t.Cleanup(market.Close)
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_public_url": market.URL, "tool_market_login_required": "0"}); err != nil {
		t.Fatal(err)
	}
	files := packageWorkflowFiles("index.html", "1.0.0")
	upload := packageWorkflowUploadOK(t, router, token, files, 0)
	publication := packageWorkflowPublish(t, router, token, upload, "1.0.0", "public")
	revision = publication.Revision
	w := adminAssetRequest(router, token, "POST", "/api/tool-sources", map[string]any{"server": market.URL + "/market"})
	var catalog struct {
		Tools []struct {
			ID int64 `json:"id"`
		} `json:"tools"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &catalog) != nil || len(catalog.Tools) != 1 || catalog.Tools[0].ID >= 0 {
		t.Fatalf("remote catalog ID mapping: %d %s", w.Code, w.Body.String())
	}
	remoteID := catalog.Tools[0].ID
	w = packageWorkflowGet(router, token, "/api/tool-sources/"+strconv.FormatInt(remoteID, 10))
	var manifest struct {
		models.ToolMetadata
		ID       int64              `json:"id"`
		Revision string             `json:"revision"`
		Files    []toolpackage.File `json:"files"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &manifest) != nil || manifest.ID != remoteID || manifest.Distribution != "files" || manifest.Revision != revision || len(manifest.Files) != len(files) {
		t.Fatalf("remote file manifest: %d %s", w.Code, w.Body.String())
	}
	for _, file := range manifest.Files {
		original, ok := files[file.Name]
		if !ok || file.Size != int64(len(original)) || file.Hash != fmt.Sprintf("%x", sha256.Sum256(original)) {
			t.Fatalf("remote file digest differs from published bytes: %+v", file)
		}
	}
	mu.Lock()
	readBeforeInstall := len(downloads)
	mu.Unlock()
	if readBeforeInstall != 0 {
		t.Fatal("remote catalog or manifest request eagerly downloaded resources")
	}
	base := "/api/tool-installs/" + strconv.FormatInt(remoteID, 10)
	w = adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": manifest.Revision, "hash": manifest.Hash})
	if w.Code != 200 {
		t.Fatalf("remote package installation: %d %s", w.Code, w.Body.String())
	}
	installed, err := models.GetInstalledTool(1, remoteID)
	if err != nil || installed.ID != remoteID || installed.Distribution != "files" || installed.Revision != revision {
		t.Fatalf("remote installation metadata changed: %+v %v", installed, err)
	}
	for name, original := range files {
		_, _, reader, err := models.ReadDAVFileContext(context.Background(), 1, installed.Assets+"/"+name)
		if err != nil {
			t.Fatalf("remote installed file missing %s: %v", name, err)
		}
		actual, readErr := io.ReadAll(reader)
		reader.Close()
		if readErr != nil || !bytes.Equal(actual, original) {
			t.Fatalf("remote installed bytes changed %s: %v", name, readErr)
		}
		mu.Lock()
		reads := downloads["/api/tool-package-assets/"+upload.Package.Token+"/"+name]
		mu.Unlock()
		if reads != 1 {
			t.Fatalf("remote file %s downloaded %d times, want once", name, reads)
		}
	}
	w = adminAssetRequest(router, token, "POST", base+"/data", map[string]any{"revision": installed.Revision, "instance": installed.Instance, "op": "set", "key": "remote-save", "value": "preserved"})
	if w.Code != 200 {
		t.Fatalf("remote installed storage bridge: %d %s", w.Code, w.Body.String())
	}
	values, err := models.GetInstalledToolValues(1, remoteID)
	if err != nil || values["remote-save"] != "preserved" {
		t.Fatalf("remote stored value missing: %v %v", values, err)
	}
}

func TestToolPackageWorkflowDraftFilesRequireOwner(t *testing.T) {
	router, token := initPackageWorkflow(t)
	upload := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	path := "/api/tool-packages/" + upload.Package.Token + "/files/index.html"
	w := packageWorkflowGet(router, token, path)
	if w.Code != 200 || w.Header().Get("Content-Disposition") != "attachment" || w.Header().Get("Content-Security-Policy") != "sandbox" {
		t.Fatalf("draft file %d %v", w.Code, w.Header())
	}
	if w := packageWorkflowGet(router, "", path); w.Code == 200 {
		t.Fatal("anonymous draft file exposed")
	}
}

func TestToolPublicationPatchUpdatesMetadataWithoutVersionBump(t *testing.T) {
	router, token := initPackageWorkflow(t)
	market := httptest.NewServer(router)
	t.Cleanup(market.Close)
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_public_url": "https://old-domain.example", "tool_market_login_required": "0"}); err != nil {
		t.Fatal(err)
	}
	upload := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	pub := packageWorkflowPublish(t, router, token, upload, "1.0.0", "login")
	idStr := strconv.FormatInt(upload.ID, 10)
	// Switch marketplace public URL to the live test server; PATCH should refresh resource_base and hash too.
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_public_url": market.URL}); err != nil {
		t.Fatal(err)
	}

	// Before PATCH: access=login blocks anonymous install even when market allows login-free installs.
	if w := packageWorkflowGet(router, "", "/api/tool-market/"+idStr+"?metadata=1"); w.Code != 401 {
		t.Fatalf("expected 401 before patch, got %d %s", w.Code, w.Body.String())
	}
	// Publish page shows Save Info button when viewing currently published package.
	if page := packageWorkflowGet(router, token, "/market/packages/"+idStr); page.Code != 200 || !strings.Contains(page.Body.String(), "toolPublishSaveInfo") {
		t.Fatalf("expected save-info button on published package page: %d", page.Code)
	}

	// PATCH metadata & access without version bump.
	patchBody := map[string]any{
		"title":       "Packaged terminal updated",
		"description": "Updated description without bumping version",
		"category":    "productivity",
		"icon":        "terminal",
		"icon_style":  "solid",
		"icon_color":  "#2563eb",
		"access":      "inherit",
		"notes":       "Updated release notes in place",
		"package":     upload.Package.Token,
		"entry":       upload.Package.Entry,
		"permissions": map[string]any{"schema": 1, "read_files": true, "save_files": true},
	}
	w := adminAssetRequest(router, token, "PATCH", "/api/tool-publications/"+idStr, patchBody)
	var patched struct {
		OK             bool                `json:"ok"`
		Revision       string              `json:"revision"`
		UpdatedInPlace bool                `json:"updated_in_place"`
		Metadata       models.ToolMetadata `json:"metadata"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &patched) != nil || !patched.OK || !patched.UpdatedInPlace {
		t.Fatalf("patch failed: %d %s", w.Code, w.Body.String())
	}
	if patched.Revision != pub.Revision || patched.Metadata.Version != "1.0.0" || patched.Metadata.Access != "inherit" || patched.Metadata.Title != "Packaged terminal updated" {
		t.Fatalf("unexpected patched state: rev=%s/%s meta=%+v", patched.Revision, pub.Revision, patched.Metadata)
	}
	var versionCount int
	if err := models.DB.QueryRow(`SELECT COUNT(*) FROM md_tool_versions WHERE tool_id=?`, upload.ID).Scan(&versionCount); err != nil || versionCount != 1 {
		t.Fatalf("expected 1 version row, got %d err=%v", versionCount, err)
	}

	// After PATCH: remote client without market login can fetch catalog, manifest (verifies referenceDigest!), and install completely.
	w = adminAssetRequest(router, token, "POST", "/api/tool-sources", map[string]any{"server": market.URL + "/market"})
	var catalog struct {
		Tools []struct {
			ID     int64  `json:"id"`
			Title  string `json:"title"`
			Access string `json:"access"`
		} `json:"tools"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &catalog) != nil || len(catalog.Tools) != 1 || catalog.Tools[0].Access != "inherit" || catalog.Tools[0].Title != "Packaged terminal updated" {
		t.Fatalf("remote catalog after patch: %d %s", w.Code, w.Body.String())
	}
	remoteID := catalog.Tools[0].ID
	w = packageWorkflowGet(router, token, "/api/tool-sources/"+strconv.FormatInt(remoteID, 10))
	var manifest struct {
		models.ToolMetadata
		Revision string `json:"revision"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &manifest) != nil || manifest.Revision != pub.Revision || manifest.Hash != patched.Metadata.Hash {
		t.Fatalf("remote manifest after patch: %d %s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, "PUT", "/api/tool-installs/"+strconv.FormatInt(remoteID, 10), map[string]any{"revision": manifest.Revision, "hash": manifest.Hash})
	if w.Code != 200 {
		t.Fatalf("remote install without market login after patch failed: %d %s", w.Code, w.Body.String())
	}

	// Attempting to change runtime permissions via PATCH must be rejected with version_bump_required.
	badPerm := map[string]any{
		"title":       "Packaged terminal updated",
		"description": "Updated description",
		"category":    "productivity",
		"access":      "inherit",
		"package":     upload.Package.Token,
		"entry":       upload.Package.Entry,
		"permissions": map[string]any{"schema": 1, "read_files": true, "save_files": true, "socket_tcp": true},
	}
	if w := adminAssetRequest(router, token, "PATCH", "/api/tool-publications/"+idStr, badPerm); w.Code != 409 || !strings.Contains(w.Body.String(), "version_bump_required") {
		t.Fatalf("expected 409 version_bump_required for permission change, got %d %s", w.Code, w.Body.String())
	}

	// Uploading a replacement package hides Save Info button and blocks PATCH with new package token.
	next := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.1"), upload.ID)
	if page := packageWorkflowGet(router, token, "/market/packages/"+idStr+"?package="+next.Package.Token); page.Code != 200 || strings.Contains(page.Body.String(), "toolPublishSaveInfo") {
		t.Fatalf("save-info button should be hidden when package is replaced: %d", page.Code)
	}
	badPkg := map[string]any{
		"title":       "Packaged terminal updated",
		"description": "Updated description",
		"category":    "productivity",
		"access":      "inherit",
		"package":     next.Package.Token,
		"entry":       next.Package.Entry,
		"permissions": map[string]any{"schema": 1, "read_files": true, "save_files": true},
	}
	if w := adminAssetRequest(router, token, "PATCH", "/api/tool-publications/"+idStr, badPkg); w.Code != 409 || !strings.Contains(w.Body.String(), "version_bump_required") {
		t.Fatalf("expected 409 version_bump_required for package replacement, got %d %s", w.Code, w.Body.String())
	}
}

func TestToolPackageWorkflowPublishPrunesSupersededPackage(t *testing.T) {
	router, token := initPackageWorkflow(t)
	first := packageWorkflowUploadOK(t, router, token, packageWorkflowFiles("index.html", "1.0.0"), 0)
	packageWorkflowPublish(t, router, token, first, "1.0.0", "public")

	nextFiles := packageWorkflowFiles("index.html", "1.0.1")
	nextFiles["app.js"] = []byte(`console.log("v1.0.1");`)
	next := packageWorkflowUploadOK(t, router, token, nextFiles, first.ID)
	pub2 := packageWorkflowPublish(t, router, token, next, "1.0.1", "public")

	if _, err := models.GetToolPackage(first.Package.Token); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("superseded package metadata retained: %v", err)
	}
	if _, err := models.GetDAVNode(1, "/BookStark/tool-packages/"+first.Package.Token); !errors.Is(err, models.ErrDAVNotFound) {
		t.Fatalf("superseded package files retained: %v", err)
	}
	var versionCount int
	if err := models.DB.QueryRow(`SELECT COUNT(*) FROM md_tool_versions WHERE tool_id=?`, first.ID).Scan(&versionCount); err != nil || versionCount != 1 {
		t.Fatalf("expected only latest 1 published version row, got %d err=%v", versionCount, err)
	}
	if _, err := models.GetToolPackage(next.Package.Token); err != nil {
		t.Fatalf("latest published package missing: %v", err)
	}
	if w := packageWorkflowGet(router, "", "/api/tool-package-assets/"+next.Package.Token+"/app.js?revision="+pub2.Revision); w.Code != 200 {
		t.Fatalf("latest published asset unreadable: %d %s", w.Code, w.Body.String())
	}
}
