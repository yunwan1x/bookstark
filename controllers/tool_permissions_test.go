package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestToolPermissionDeclarationsAreExplicitAndVersioned(t *testing.T) {
	raw, err := json.Marshal(models.ToolPermissions{ReadFiles: true})
	if err != nil || string(raw) != `{"read_files":true,"save_files":false,"network":false}` {
		t.Fatal("legacy package hash changed", string(raw), err)
	}
	var p models.ToolPermissions
	for _, input := range []string{`{"schema":2}`, `{"schema":-1}`, `{"camera":"yes"}`, `{"unknown_permission":true}`} {
		if json.Unmarshal([]byte(input), &p) == nil {
			t.Fatal("unrecognized permission accepted", input)
		}
	}
	if err := json.Unmarshal([]byte(`{"schema":1,"camera":true,"clipboard_read":true}`), &p); err != nil {
		t.Fatal(err)
	}
	for _, permissions := range []models.ToolPermissions{p, {}, {Schema: 1, Camera: false, Network: false, Downloads: false}} {
		flags := permissions.Flags()
		for _, spec := range models.ToolPermissionCatalog {
			if !spec.Managed && !flags[spec.Key] {
				t.Fatalf("browser capability not enabled: %s", spec.Key)
			}
			if spec.Managed && flags[spec.Key] {
				t.Fatalf("bridge capability silently granted: %s", spec.Key)
			}
		}
	}
	if !((models.ToolPermissions{ReadFiles: true}).Flags()["read_files"]) {
		t.Fatal("read permission lost")
	}
	if len(models.ToolPermissionCatalog) != 42 {
		t.Fatal("catalog missing capabilities")
	}
}
func TestToolFrameUsesSignedInstallationSpecificOrigin(t *testing.T) {
	router, token := initAssetControllerTest(t)
	tool := models.InstalledTool{ID: 700, Title: "Camera tool", Revision: strings.Repeat("b", 64), Content: "PRIVATE_TOOL_HTML", ToolMetadata: models.ToolMetadata{Permissions: models.ToolPermissions{Schema: 1, Camera: true, ClipboardWrite: true}}}
	if err := models.SaveInstalledTool(1, tool, "", ""); err != nil {
		t.Fatal(err)
	}
	response := adminAssetRequest(router, token, "GET", "http://127.0.0.1:8089/tools/run/700", nil)
	match := regexp.MustCompile(`window.BookStarkToolRuntime=(.*?);window.__I18N_MESSAGES`).FindStringSubmatch(response.Body.String())
	if len(match) != 2 {
		t.Fatal("no frame configuration", response.Body.String())
	}
	var config struct {
		URL    string `json:"url"`
		Origin string `json:"origin"`
	}
	if err := json.Unmarshal([]byte(match[1]), &config); err != nil {
		t.Fatal(err)
	}
	if config.Origin == "" || config.Origin == "http://127.0.0.1:8089" {
		t.Fatal(config)
	}
	if !strings.Contains(response.Header().Get("Permissions-Policy"), `camera=(self "`+config.Origin+`")`) || !strings.Contains(response.Header().Get("Permissions-Policy"), `microphone=(self "`+config.Origin+`")`) {
		t.Fatal(response.Header())
	}
	if response.Header().Get("Content-Security-Policy") != "frame-src "+config.Origin {
		t.Fatal("parent must block frame navigation back to the app")
	}
	frame := httptest.NewRecorder()
	router.ServeHTTP(frame, httptest.NewRequest("GET", config.URL, nil))
	if frame.Code != 200 || frame.Header().Get("X-Frame-Options") != "" {
		t.Fatal(frame.Code, frame.Header(), frame.Body.String())
	}
	policy := frame.Header().Get("Content-Security-Policy")
	if !strings.Contains(policy, "sandbox allow-scripts allow-same-origin ") || !strings.Contains(policy, "frame-ancestors http://127.0.0.1:8089") || !strings.Contains(policy, "allow-popups") || strings.Contains(frame.Body.String(), "PRIVATE_TOOL_HTML") {
		t.Fatal(policy, frame.Body.String())
	}
	for _, suffix := range []string{"/login", "/api/profile", "/static/js/utils.js"} {
		blocked := httptest.NewRecorder()
		router.ServeHTTP(blocked, httptest.NewRequest("GET", config.Origin+suffix, nil))
		if blocked.Code != 404 {
			t.Fatal("app route exposed on sandbox", suffix, blocked.Code)
		}
	}
	tampered, _ := url.Parse(config.URL)
	q := tampered.Query()
	q.Set("signature", strings.Repeat("0", 64))
	tampered.RawQuery = q.Encode()
	blocked := httptest.NewRecorder()
	router.ServeHTTP(blocked, httptest.NewRequest("GET", tampered.String(), nil))
	if blocked.Code != 403 {
		t.Fatal("unsigned frame accepted")
	}
	moved, _ := url.Parse(config.URL)
	moved.Host = "127.0.0.1:8089"
	blocked = httptest.NewRecorder()
	router.ServeHTTP(blocked, httptest.NewRequest("GET", moved.String(), nil))
	if blocked.Code != 403 {
		t.Fatal("frame ran on main origin")
	}
	remote := adminAssetRequest(router, token, "GET", "https://books.example.com/tools/run/700", nil)
	if strings.Contains(remote.Body.String(), "/tools/frame?ticket=") {
		t.Fatal("unconfigured remote origin allowed")
	}
}
func TestToolFileAPIEnforcesPermissionsAndIsolation(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.InitWebDAVDB(filepath.Join(t.TempDir(), "files.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { models.WebDAVDB.Close(); models.WebDAVDB = nil })
	for _, id := range []int64{800, 801} {
		if err := models.SaveInstalledTool(1, models.InstalledTool{ID: id, Title: "Files", Revision: "files-v1", Content: "<h1>files</h1>", ToolMetadata: models.ToolMetadata{Permissions: models.ToolPermissions{Schema: 1, ReadFiles: true, SaveFiles: true}}}, "", ""); err != nil {
			t.Fatal(err)
		}
	}
	current, _ := models.GetInstalledTool(1, 800)
	request := func(op, path, to string, recursive bool, status int) any {
		raw, _ := json.Marshal(models.ToolFileOperation{Op: op, Path: path, To: to, Recursive: recursive})
		req := httptest.NewRequest("POST", "/api/tool-installs/800/files", strings.NewReader(string(raw)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Token "+token)
		req.Header.Set("X-Tool-Revision", current.Revision)
		req.Header.Set("X-Tool-Instance", current.Instance)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		if response.Code != status {
			t.Fatalf("%s %q -> %q: %d %s", op, path, to, response.Code, response.Body.String())
		}
		var result map[string]any
		json.Unmarshal(response.Body.Bytes(), &result)
		return result["result"]
	}
	if got := request("list", "", "", false, 200).([]any); len(got) != 0 {
		t.Fatal(got)
	}
	request("mkdir", "notes/sub", "", true, 200)
	if err := models.PutToolResource(1, 800, current.Revision, current.Instance, "data", "notes/sub/你好.txt", "text/plain", strings.NewReader("hello")); err != nil {
		t.Fatal(err)
	}
	info := request("stat", "notes/sub/你好.txt", "", false, 200).(map[string]any)
	if info["path"] != "notes/sub/你好.txt" || info["size"] != float64(5) {
		t.Fatal(info)
	}
	request("copy", "notes", "backup", false, 200)
	request("rename", "backup/sub/你好.txt", "backup/sub/new.txt", false, 200)
	request("move", "backup/sub/new.txt", "notes/moved.txt", false, 200)
	request("copy", "notes/moved.txt", "notes/moved.txt", false, 400)
	request("remove", "notes", "", false, 409)
	request("remove", "backup", "", true, 200)
	if request("exists", "backup", "", false, 200) != false {
		t.Fatal("deleted directory exists")
	}
	for _, op := range []string{"list", "stat", "mkdir", "remove", "rename", "copy"} {
		request(op, "../other", "stolen", true, 400)
	}
	request("remove", "", "", true, 400)
	request("rename", "notes", "../escaped", false, 400)
	other, _ := models.GetInstalledTool(1, 801)
	if got, err := models.ExecuteToolFileOperation(1, 801, other.Revision, other.Instance, models.ToolFileOperation{Op: "list"}); err != nil || len(got.([]models.ToolFileInfo)) != 0 {
		t.Fatal("another tool data leaked", got, err)
	}
	originalRevision := current.Revision
	current.Revision = "stale"
	request("remove", "notes", "", true, 409)
	current.Revision = originalRevision
	setPermissions := func(read, write bool) {
		tx, _ := models.DB.Begin()
		m := current.ToolMetadata
		m.Permissions = models.ToolPermissions{Schema: 1, ReadFiles: read, SaveFiles: write}
		if err := models.SaveToolMetadata(tx, 1, 800, m); err != nil {
			t.Fatal(err)
		}
		if err := tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}
	setPermissions(true, false)
	request("stat", "notes/moved.txt", "", false, 200)
	request("mkdir", "denied", "", false, 403)
	request("copy", "notes/moved.txt", "copy.txt", false, 403)
	if err := models.PutToolResource(1, 800, current.Revision, current.Instance, "data", "denied.txt", "text/plain", strings.NewReader("no")); err != models.ErrToolPermission {
		t.Fatal("direct write bypassed permissions", err)
	}
	setPermissions(false, true)
	request("mkdir", "allowed", "", false, 200)
	request("list", "", "", false, 403)
	request("copy", "notes/moved.txt", "copy.txt", false, 403)
	// Raw authenticated download endpoints enforce read permission too.
	req := httptest.NewRequest("GET", "/api/tool-installs/800/files/notes/moved.txt", nil)
	req.Header.Set("Authorization", "Token "+token)
	req.Header.Set("X-Tool-Revision", current.Revision)
	req.Header.Set("X-Tool-Instance", current.Instance)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)
	if response.Code != 403 {
		t.Fatal("raw read bypassed permission", response.Code)
	}
	setPermissions(false, false)
	request("remove", "allowed", "", false, 403)
}

func TestRemoteToolRuntimeOriginIsOptionalAndInstallationScoped(t *testing.T) {
	router, token := initAssetControllerTest(t)
	settings := map[string]any{"enabled": true, "name": "Remote tools", "public_url": "https://books.example.com/market", "runtime_origin": "", "socket_proxy": false}
	if response := adminAssetRequest(router, token, "PUT", "/api/tool-market/settings", settings); response.Code != 200 {
		t.Fatal("optional origin rejected", response.Code, response.Body.String())
	}
	for _, invalid := range []string{"https://books.example.com", "https://tools.example.com", "http://{instance}.tools.example.com", "https://user:pass@{instance}.tools.example.com", "https://{instance}.tools.example.com/path", "https://{instance}.tools.example.com?query=1"} {
		settings["runtime_origin"] = invalid
		response := adminAssetRequest(router, token, "PUT", "/api/tool-market/settings", settings)
		if response.Code != 400 {
			t.Fatal("unsafe runtime origin accepted", invalid, response.Code)
		}
	}
	settings["runtime_origin"] = "https://{instance}.tools.example.com"
	if response := adminAssetRequest(router, token, "PUT", "/api/tool-market/settings", settings); response.Code != 200 {
		t.Fatal(response.Code, response.Body.String())
	}
	if err := models.SaveInstalledTool(1, models.InstalledTool{ID: 710, Title: "Remote camera", Revision: "remote-v1", ToolMetadata: models.ToolMetadata{Permissions: models.ToolPermissions{Schema: 1, Camera: true}}}, "", ""); err != nil {
		t.Fatal(err)
	}
	response := adminAssetRequest(router, token, "GET", "https://books.example.com/tools/run/710", nil)
	match := regexp.MustCompile(`window.BookStarkToolRuntime=(.*?);window.__I18N_MESSAGES`).FindStringSubmatch(response.Body.String())
	if len(match) != 2 {
		t.Fatal("no remote frame configuration")
	}
	var config struct {
		URL    string `json:"url"`
		Origin string `json:"origin"`
	}
	if err := json.Unmarshal([]byte(match[1]), &config); err != nil {
		t.Fatal(err)
	}
	tool, _ := models.GetInstalledTool(1, 710)
	if config.Origin != "https://"+tool.Instance+".tools.example.com" {
		t.Fatal(config)
	}
	frame := httptest.NewRecorder()
	router.ServeHTTP(frame, httptest.NewRequest("GET", config.URL, nil))
	if frame.Code != 200 {
		t.Fatal(frame.Code, frame.Body.String())
	}
	other := httptest.NewRecorder()
	router.ServeHTTP(other, httptest.NewRequest("GET", config.Origin+"/api/profile", nil))
	if other.Code != 404 {
		t.Fatal("API exposed on remote tool origin")
	}
}

func TestRemoteToolOriginPrefixCannotExposeApplicationRoutes(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.SaveInstalledTool(1, models.InstalledTool{ID: 720, Title: "Prefixed origin", Revision: "prefix-v1", ToolMetadata: models.ToolMetadata{Permissions: models.ToolPermissions{Schema: 1, Camera: true}}}, "", ""); err != nil {
		t.Fatal(err)
	}
	settings := map[string]any{"enabled": true, "name": "Runtime", "public_url": "https://books.example.com/market", "runtime_origin": "https://instance-tools-{instance}.tools.example.com"}
	if w := adminAssetRequest(router, token, "PUT", "/api/tool-market/settings", settings); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	installed, _ := models.GetInstalledTool(1, 720)
	origin := "https://instance-tools-" + installed.Instance + ".tools.example.com"
	for _, path := range []string{"/api/profile", "/login", "/static/js/utils.js"} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", origin+path, nil))
		if w.Code != 404 {
			t.Fatalf("application route exposed at tool origin: %s => %d", path, w.Code)
		}
	}
}

func TestRuntimeOriginCannotMatchTheMainHostname(t *testing.T) {
	router, token := initAssetControllerTest(t)
	settings := map[string]any{"enabled": true, "name": "Runtime", "public_url": "https://" + strings.Repeat("b", 32) + ".tools.example.com/market", "runtime_origin": "https://{instance}.tools.example.com"}
	if w := adminAssetRequest(router, token, "PUT", "/api/tool-market/settings", settings); w.Code != 400 {
		t.Fatal("runtime template matched main hostname", w.Code, w.Body.String())
	}
}
