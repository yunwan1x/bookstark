package controllers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/conf"
	"bookstark/controllers"
	"bookstark/models"
	"bookstark/routers"
)

var assetControllerTestDBMu sync.Mutex

func initAssetControllerTest(t *testing.T) (*gin.Engine, string) {
	t.Helper()
	assetControllerTestDBMu.Lock()
	conf.LoadDefaults()
	conf.App.AssetSecret = ""
	conf.App.DBPath = filepath.Join(t.TempDir(), "asset-controller.db")
	if models.DB != nil {
		_ = models.DB.Close()
		models.DB = nil
	}
	if err := models.InitDB(conf.App.DBPath); err != nil {
		assetControllerTestDBMu.Unlock()
		t.Fatalf("InitDB() error = %v", err)
	}
	admin, err := models.GetMemberByAccount(conf.App.AdminAccount)
	if err != nil {
		assetControllerTestDBMu.Unlock()
		t.Fatalf("GetMemberByAccount() error = %v", err)
	}
	token, err := models.CreateApiToken(admin.MemberID, "asset-test")
	if err != nil {
		assetControllerTestDBMu.Unlock()
		t.Fatalf("CreateApiToken() error = %v", err)
	}
	wd, err := os.Getwd()
	if err != nil {
		assetControllerTestDBMu.Unlock()
		t.Fatalf("Getwd() error = %v", err)
	}
	if filepath.Base(wd) == "controllers" {
		if err := os.Chdir(".."); err != nil {
			assetControllerTestDBMu.Unlock()
			t.Fatalf("Chdir(repo root) error = %v", err)
		}
	}
	t.Cleanup(func() {
		_ = os.Chdir(wd)
		if models.DB != nil {
			_ = models.DB.Close()
			models.DB = nil
		}
		assetControllerTestDBMu.Unlock()
	})
	return routers.Setup(), token.Token
}

func adminAssetRequest(router http.Handler, token string, method, path string, body any) *httptest.ResponseRecorder {
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Token "+token)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func TestAssetDockerHostPageRoute(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodGet, "/admin/assets/ssh-hosts/123/docker", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET docker host page status = %d, want %d", w.Code, http.StatusOK)
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/assets/ssh-hosts/123/docker", nil)
	w = httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusFound {
		t.Fatalf("unauthenticated GET docker host page status = %d, want %d", w.Code, http.StatusFound)
	}
	if loc := w.Header().Get("Location"); loc != "/login" {
		t.Fatalf("unauthenticated GET docker host page Location = %q, want /login", loc)
	}
}

func TestAssetFilesHostPageRoute(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodGet, "/admin/assets/ssh-hosts/123/files", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET files host page status = %d, want %d", w.Code, http.StatusOK)
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`window.__FILES_HOST_ID__ = "123"`)) {
		t.Fatalf("files host page should expose selected host id")
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/assets/ssh-hosts/123/files", nil)
	w = httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusFound {
		t.Fatalf("unauthenticated GET files host page status = %d, want %d", w.Code, http.StatusFound)
	}
	if loc := w.Header().Get("Location"); loc != "/login" {
		t.Fatalf("unauthenticated GET files host page Location = %q, want /login", loc)
	}
}

func TestAssetWebDAVFilesPageRoute(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodGet, "/admin/assets/webdav-servers/123/files", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET WebDAV files page status = %d, want %d", w.Code, http.StatusOK)
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`window.__WEBDAV_SERVER_ID__ = "123"`)) {
		t.Fatalf("WebDAV files page should expose selected server id")
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/assets/webdav-servers/123/files", nil)
	w = httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusFound {
		t.Fatalf("unauthenticated GET WebDAV files page status = %d, want %d", w.Code, http.StatusFound)
	}
	if loc := w.Header().Get("Location"); loc != "/login" {
		t.Fatalf("unauthenticated GET WebDAV files page Location = %q, want /login", loc)
	}
}

func TestCreateListAndUseAssetWebDAVServer(t *testing.T) {
	router, token := initAssetControllerTest(t)
	dav := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PROPFIND" {
			t.Fatalf("WebDAV method = %s, want PROPFIND", r.Method)
		}
		if r.URL.Path != "/dav/root" {
			t.Fatalf("WebDAV path = %q, want /dav/root", r.URL.Path)
		}
		user, pass, _ := r.BasicAuth()
		if user != "dav-user" || pass != "dav-secret" {
			t.Fatalf("WebDAV auth = %q/%q, want dav-user/dav-secret", user, pass)
		}
		w.WriteHeader(207)
		_, _ = w.Write([]byte(`<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/root/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/root/readme.md</d:href><d:propstat><d:prop><d:displayname>readme.md</d:displayname><d:getcontentlength>7</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>`))
	}))
	defer dav.Close()

	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/credentials", map[string]any{
		"name":       "dav-login",
		"username":   "dav-user",
		"auth_type":  "password",
		"credential": "dav-secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create credential status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var credentialResp struct {
		Data struct {
			ID int64 `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &credentialResp); err != nil {
		t.Fatalf("decode credential response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/webdav-servers", map[string]any{
		"name":          "docs-dav",
		"url":           dav.URL + "/dav",
		"root_path":     "/root",
		"credential_id": credentialResp.Data.ID,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create WebDAV status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var serverResp struct {
		Data struct {
			ID int64 `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &serverResp); err != nil {
		t.Fatalf("decode WebDAV response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/webdav-servers?q=docs", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list WebDAV status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"name":"docs-dav"`)) || !bytes.Contains(w.Body.Bytes(), []byte(`"credential_name":"dav-login"`)) {
		t.Fatalf("list response missing WebDAV details: %s", w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/webdav-servers/"+strconv.FormatInt(serverResp.Data.ID, 10)+"/files?path=.", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list WebDAV files status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"name":"readme.md"`)) {
		t.Fatalf("files response missing readme.md: %s", w.Body.String())
	}
}

func TestCreateAssetWebDAVServerRejectsKeyCredential(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/credentials", map[string]any{
		"name":       "dav-key",
		"username":   "dav",
		"auth_type":  "key",
		"credential": "private-key",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create key credential status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var credentialResp struct {
		Data struct {
			ID int64 `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &credentialResp); err != nil {
		t.Fatalf("decode credential response: %v", err)
	}
	w = adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/webdav-servers", map[string]any{
		"name":          "bad-dav",
		"url":           "https://example.com/dav",
		"root_path":     "/",
		"credential_id": credentialResp.Data.ID,
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("create WebDAV with key credential status = %d, want 400; body=%s", w.Code, w.Body.String())
	}
}

func TestCreateAssetSSHHostValidation(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":      "",
		"host":      "10.0.1.21",
		"port":      22,
		"username":  "root",
		"auth_type": "password",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400; body=%s", w.Code, w.Body.String())
	}
}

func TestCreateAndListAssetSSHHost(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "prod-web-01",
		"host":       "10.0.1.21",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts?q=prod", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"credential":"secret"`)) {
		t.Fatalf("list response missing plaintext credential: %s", w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte("prod-web-01")) {
		t.Fatalf("list response missing created host: %s", w.Body.String())
	}
}

func TestAssetCredentialPlaintextStorageWhenSecretEmpty(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "plain-host",
		"host":       "10.0.1.22",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "plain-secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	hosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "plain-host"})
	if err != nil || len(hosts) != 1 {
		t.Fatalf("ListAssetSSHHosts() = %d, %v", len(hosts), err)
	}
	if hosts[0].CredentialCipher != "plain-secret" {
		t.Fatalf("stored credential = %q, want plaintext", hosts[0].CredentialCipher)
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts?q=plain", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"credential":"plain-secret"`)) {
		t.Fatalf("list response missing plaintext credential: %s", w.Body.String())
	}
}

func TestCreateAssetSSHHostWithManagedCredential(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/credentials", map[string]any{
		"name":       "prod-root",
		"username":   "root",
		"auth_type":  "password",
		"credential": "managed-secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create credential status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var credentialResp struct {
		Code int `json:"code"`
		Data struct {
			ID         int64  `json:"id"`
			Name       string `json:"name"`
			Username   string `json:"username"`
			AuthType   string `json:"auth_type"`
			Credential string `json:"credential"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &credentialResp); err != nil {
		t.Fatalf("decode credential response: %v", err)
	}
	if credentialResp.Data.ID <= 0 {
		t.Fatalf("credential id = %d, want > 0", credentialResp.Data.ID)
	}
	if credentialResp.Data.Credential != "managed-secret" {
		t.Fatalf("credential response credential = %q, want managed-secret", credentialResp.Data.Credential)
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":          "managed-host",
		"host":          "10.0.1.25",
		"port":          22,
		"credential_id": credentialResp.Data.ID,
		"shell":         "/bin/bash",
		"cwd":           "/srv/app",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create host status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts?q=managed", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"credential_id":`+strconv.FormatInt(credentialResp.Data.ID, 10))) {
		t.Fatalf("list response missing credential_id: %s", w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"credential_name":"prod-root"`)) {
		t.Fatalf("list response missing credential_name: %s", w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"username":"root"`)) {
		t.Fatalf("list response missing credential username: %s", w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"shell":"/bin/bash"`)) {
		t.Fatalf("list response missing host shell: %s", w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"cwd":"/srv/app"`)) {
		t.Fatalf("list response missing host cwd: %s", w.Body.String())
	}
}

func TestAssetCredentialEncryptedStorageWhenSecretConfigured(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPut, "/api/admin/assets/settings", map[string]any{
		"default_shell":                 "/bin/sh",
		"terminal_idle_timeout_seconds": 1800,
		"credential_secret":             "12345678901234567890123456789012",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("settings status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "encrypted-host",
		"host":       "10.0.1.23",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "encrypted-secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	hosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "encrypted-host"})
	if err != nil || len(hosts) != 1 {
		t.Fatalf("ListAssetSSHHosts() = %d, %v", len(hosts), err)
	}
	if hosts[0].CredentialCipher == "encrypted-secret" {
		t.Fatalf("stored credential leaked plaintext")
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts?q=encrypted", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"credential":"encrypted-secret"`)) {
		t.Fatalf("list response missing decrypted credential: %s", w.Body.String())
	}
}

func TestAssetSettingsIncludesTerminalScrollback(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/settings", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("settings status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"terminal_scrollback_lines":5000`)) {
		t.Fatalf("settings response missing default scrollback: %s", w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPut, "/api/admin/assets/settings", map[string]any{
		"terminal_idle_timeout_seconds": 1800,
		"terminal_scrollback_lines":     12000,
		"credential_secret":             "",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("update settings status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"terminal_scrollback_lines":12000`)) {
		t.Fatalf("settings response missing updated scrollback: %s", w.Body.String())
	}
}

func TestAssetCredentialSecretRotationRewrapsExistingHosts(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "rotate-host",
		"host":       "10.0.1.24",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "rotate-secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPut, "/api/admin/assets/settings", map[string]any{
		"default_shell":                 "/bin/sh",
		"terminal_idle_timeout_seconds": 1800,
		"credential_secret":             "12345678901234567890123456789012",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("enable secret status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	encryptedHosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "rotate-host"})
	if err != nil || len(encryptedHosts) != 1 {
		t.Fatalf("ListAssetSSHHosts(encrypted) = %d, %v", len(encryptedHosts), err)
	}
	if encryptedHosts[0].CredentialCipher == "rotate-secret" {
		t.Fatalf("credential was not encrypted during rotation")
	}
	w = adminAssetRequest(router, token, http.MethodPut, "/api/admin/assets/settings", map[string]any{
		"default_shell":                 "/bin/sh",
		"terminal_idle_timeout_seconds": 1800,
		"credential_secret":             "abcdefghijklmnopabcdefghijklmnop",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("rotate secret status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts?q=rotate", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list after rotate status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"credential":"rotate-secret"`)) {
		t.Fatalf("list response missing credential after rotate: %s", w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPut, "/api/admin/assets/settings", map[string]any{
		"default_shell":                 "/bin/sh",
		"terminal_idle_timeout_seconds": 1800,
		"credential_secret":             "",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("clear secret status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	plainHosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "rotate-host"})
	if err != nil || len(plainHosts) != 1 {
		t.Fatalf("ListAssetSSHHosts(plain) = %d, %v", len(plainHosts), err)
	}
	if plainHosts[0].CredentialCipher != "rotate-secret" {
		t.Fatalf("credential after clearing secret = %q, want plaintext", plainHosts[0].CredentialCipher)
	}
}

func TestAssetSSHStatusIsSystemOwned(t *testing.T) {
	router, token := initAssetControllerTest(t)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "prod-web-01",
		"host":       "10.0.1.21",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "secret",
		"status":     "online",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	hosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "prod-web-01"})
	if err != nil || len(hosts) != 1 {
		t.Fatalf("ListAssetSSHHosts() = %d, %v", len(hosts), err)
	}
	if hosts[0].Status != models.AssetStatusUnknown {
		t.Fatalf("created Status = %q, want %q", hosts[0].Status, models.AssetStatusUnknown)
	}
	checkedAt := time.Now()
	if err := models.UpdateAssetSSHHostStatus(hosts[0].HostID, models.AssetStatusOnline, checkedAt); err != nil {
		t.Fatalf("UpdateAssetSSHHostStatus() error = %v", err)
	}
	w = adminAssetRequest(router, token, http.MethodPut, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hosts[0].HostID, 10), map[string]any{
		"name":      "prod-web-02",
		"host":      "10.0.1.22",
		"port":      22,
		"username":  "root",
		"auth_type": "password",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("update status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	updated, err := models.GetAssetSSHHost(hosts[0].HostID)
	if err != nil {
		t.Fatalf("GetAssetSSHHost() error = %v", err)
	}
	if updated.Status != models.AssetStatusOnline {
		t.Fatalf("updated Status = %q, want preserved %q", updated.Status, models.AssetStatusOnline)
	}
}

func TestAssetDockerStatusIsSystemOwned(t *testing.T) {
	t.Skip("Docker 容器已改为 SSH 主机实时扫描，不再持久化状态")
}

func TestListAssetDockerContainersUsesRealtimeSSHScan(t *testing.T) {
	router, token := initAssetControllerTest(t)
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			return "{\"ID\":\"8f3d2f1a7b4c\",\"Image\":\"nginx:1.27-alpine\",\"Command\":\"nginx -g 'daemon off;'\",\"Names\":\"nginx-edge\",\"Ports\":\"0.0.0.0:80->80/tcp\",\"State\":\"running\",\"Status\":\"Up 2 hours\"}\n", nil
		},
	)
	t.Cleanup(restore)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "docker-host",
		"host":       "10.0.1.30",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create host status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	hosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "docker-host"})
	if err != nil || len(hosts) != 1 {
		t.Fatalf("ListAssetSSHHosts() = %d, %v", len(hosts), err)
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hosts[0].HostID, 10)+"/docker-containers", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("docker list status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"id":"8f3d2f1a7b4c"`)) {
		t.Fatalf("docker list response missing container id: %s", w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"status":"running"`)) {
		t.Fatalf("docker list response missing normalized status: %s", w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"command":"nginx -g 'daemon off;'"`)) {
		t.Fatalf("docker list response missing command: %s", w.Body.String())
	}
}

func TestListAssetDockerContainersPropagatesSSHCommandErrors(t *testing.T) {
	router, token := initAssetControllerTest(t)
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			return "", errors.New("docker not found")
		},
	)
	t.Cleanup(restore)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "docker-host",
		"host":       "10.0.1.30",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create host status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	hosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "docker-host"})
	if err != nil || len(hosts) != 1 {
		t.Fatalf("ListAssetSSHHosts() = %d, %v", len(hosts), err)
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hosts[0].HostID, 10)+"/docker-containers", nil)
	if w.Code != http.StatusBadGateway {
		t.Fatalf("docker list status = %d, want 502; body=%s", w.Code, w.Body.String())
	}
}

func TestListAssetDockerNetworksRunsSSHCommand(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var command string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, cmd string) (string, error) {
			command = cmd
			return "{\"Name\":\"bridge\",\"Driver\":\"bridge\",\"Scope\":\"local\"}\n{\"Name\":\"custom_net\",\"Driver\":\"bridge\",\"Scope\":\"local\"}\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-networks", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("networks status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if command != "docker network ls --format '{{json .}}'" {
		t.Fatalf("network command = %q", command)
	}
	body := w.Body.Bytes()
	if !bytes.Contains(body, []byte(`"name":"bridge"`)) || !bytes.Contains(body, []byte(`"name":"custom_net"`)) {
		t.Fatalf("network response = %s", w.Body.String())
	}
}

func TestListAssetDockerNetworksPropagatesSSHCommandErrors(t *testing.T) {
	router, token := initAssetControllerTest(t)
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			return "", errors.New("docker not found")
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-networks", nil)
	if w.Code != http.StatusBadGateway {
		t.Fatalf("networks status = %d, want 502; body=%s", w.Code, w.Body.String())
	}
}

func TestCreateAssetDockerContainerRunsCommand(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var command string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, cmd string) (string, error) {
			command = cmd
			return "new-container\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers", map[string]any{
		"image":              "nginx:1.27-alpine",
		"name":               "web-edge",
		"command":            "nginx -g daemon off;",
		"start_after_create": true,
		"restart_policy":     "unless-stopped",
		"ports": []map[string]any{
			{"host_ip": "0.0.0.0", "host_port": "8080", "container_port": "80", "protocol": "tcp"},
		},
		"volumes": []map[string]any{
			{"host_path": "/srv/nginx", "container_path": "/usr/share/nginx/html", "mode": "ro"},
		},
		"env": []map[string]any{
			{"key": "APP_ENV", "value": "prod"},
		},
		"network":    "bridge",
		"privileged": true,
		"memory":     "256m",
		"cpus":       "0.5",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create docker status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	want := "docker run -d --name 'web-edge' --restart unless-stopped -p '0.0.0.0:8080:80/tcp' -v '/srv/nginx:/usr/share/nginx/html:ro' -e 'APP_ENV=prod' --network 'bridge' --privileged -m '256m' --cpus '0.5' 'nginx:1.27-alpine' 'nginx -g daemon off;'"
	if command != want {
		t.Fatalf("create command = %q, want %q", command, want)
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"start_after_create":true`)) {
		t.Fatalf("create response = %s", w.Body.String())
	}
}

func TestCreateAssetDockerContainerCanCreateWithoutStart(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var command string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, cmd string) (string, error) {
			command = cmd
			return "created\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers", map[string]any{
		"image":              "redis:7",
		"start_after_create": false,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create docker status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if command != "docker create 'redis:7'" {
		t.Fatalf("create command = %q", command)
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"start_after_create":false`)) {
		t.Fatalf("create response = %s", w.Body.String())
	}
}

func TestCreateAssetDockerContainerRejectsInvalidInput(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var commands []string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			commands = append(commands, command)
			return "ok\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	cases := []map[string]any{
		{},
		{"image": "nginx", "restart_policy": "always; rm -rf /"},
		{"image": "nginx", "ports": []map[string]any{{"host_port": "8080", "container_port": "80", "protocol": "icmp"}}},
		{"image": "nginx", "volumes": []map[string]any{{"host_path": "/tmp"}}},
		{"image": "nginx", "env": []map[string]any{{"key": "BAD=KEY", "value": "1"}}},
	}
	for _, body := range cases {
		w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers", body)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("invalid create status = %d, want 400; body=%s", w.Code, w.Body.String())
		}
	}
	if len(commands) != 0 {
		t.Fatalf("commands = %#v, want none", commands)
	}
}

func TestInspectAssetDockerContainerReturnsKeyDetails(t *testing.T) {
	router, token := initAssetControllerTest(t)
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			if command != "docker inspect 'nginx-edge'" {
				t.Fatalf("inspect command = %q", command)
			}
			return `[{"Id":"8f3d2f1a7b4c","Name":"/nginx-edge","Created":"2026-05-20T09:30:00Z","Config":{"Hostname":"8f3d2f1a7b4c","Image":"nginx:1.27-alpine","Cmd":["nginx","-g","daemon off;"]},"State":{"Status":"running","Running":true,"ExitCode":0,"StartedAt":"2026-05-20T09:31:00Z","FinishedAt":"0001-01-01T00:00:00Z"},"HostConfig":{"RestartPolicy":{"Name":"unless-stopped"}},"NetworkSettings":{"IPAddress":"172.17.0.2"}}]`, nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/nginx-edge/inspect", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("inspect status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	body := w.Body.Bytes()
	for _, want := range [][]byte{
		[]byte(`"name":"nginx-edge"`),
		[]byte(`"image":"nginx:1.27-alpine"`),
		[]byte(`"raw_status":"running"`),
		[]byte(`"ip_address":"172.17.0.2"`),
		[]byte(`"restart_policy":"unless-stopped"`),
	} {
		if !bytes.Contains(body, want) {
			t.Fatalf("inspect response missing %s: %s", want, w.Body.String())
		}
	}
}

func TestAssetDockerLogsRunsTailCommand(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var command string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, cmd string) (string, error) {
			command = cmd
			return "line 1\nline 2\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/"+url.PathEscape("app'one")+"/logs?tail=50", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("logs status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if command != "docker logs --tail 50 'app'\\''one'" {
		t.Fatalf("logs command = %q", command)
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"tail":50`)) || !bytes.Contains(w.Body.Bytes(), []byte("line 1")) {
		t.Fatalf("logs response = %s", w.Body.String())
	}
}

func TestAssetDockerLogStreamRunsFollowCommand(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var command string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, cmd string) (string, error) {
			return "", nil
		},
		func(ctx context.Context, host *models.AssetSSHHost, credential string, cmd string, onChunk func([]byte) error) error {
			command = cmd
			return onChunk([]byte("line 1\n"))
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/"+url.PathEscape("app'one")+"/logs/stream?tail=25", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("stream logs status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if command != "docker logs --tail 25 -f 'app'\\''one'" {
		t.Fatalf("stream logs command = %q", command)
	}
	body := w.Body.String()
	if !strings.Contains(body, "event: log") || !strings.Contains(body, "line 1") {
		t.Fatalf("stream logs response = %s", body)
	}
}

func TestAssetDockerLogsRejectsInvalidTail(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var commands []string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			commands = append(commands, command)
			return "logs\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/app/logs?tail=0", nil)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("invalid tail status = %d, want 400; body=%s", w.Code, w.Body.String())
	}
	if len(commands) != 0 {
		t.Fatalf("commands = %#v, want none", commands)
	}
}

func TestOperateAssetDockerContainerRunsSSHCommand(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var commands []string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			commands = append(commands, command)
			return "ok\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	containerID := url.PathEscape("app'one")
	cases := []struct {
		action string
		want   string
	}{
		{action: "start", want: "docker start 'app'\\''one'"},
		{action: "stop", want: "docker stop 'app'\\''one'"},
		{action: "restart", want: "docker restart 'app'\\''one'"},
		{action: "delete", want: "docker rm 'app'\\''one'"},
	}
	for _, tt := range cases {
		w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/"+containerID+"/"+tt.action, nil)
		if w.Code != http.StatusOK {
			t.Fatalf("%s status = %d, want 200; body=%s", tt.action, w.Code, w.Body.String())
		}
		if got := commands[len(commands)-1]; got != tt.want {
			t.Fatalf("%s command = %q, want %q", tt.action, got, tt.want)
		}
	}
}

func TestOperateAssetDockerContainerUpdatesRestartPolicy(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var command string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, cmd string) (string, error) {
			command = cmd
			return "ok\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	containerID := url.PathEscape("app'one")
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/"+containerID+"/restart-policy", map[string]any{
		"policy": "unless-stopped",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("restart-policy status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if command != "docker update --restart unless-stopped 'app'\\''one'" {
		t.Fatalf("restart-policy command = %q", command)
	}
}

func TestOperateAssetDockerContainerRejectsInvalidRestartPolicy(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var commands []string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			commands = append(commands, command)
			return "ok\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/app/restart-policy", map[string]any{
		"policy": "always; rm -rf /",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("invalid restart-policy status = %d, want 400; body=%s", w.Code, w.Body.String())
	}
	if len(commands) != 0 {
		t.Fatalf("commands = %#v, want none", commands)
	}
}

func TestOperateAssetDockerContainerRejectsUnsupportedAction(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var commands []string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			commands = append(commands, command)
			return "ok\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker-containers/app/prune", nil)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("unsupported action status = %d, want 400; body=%s", w.Code, w.Body.String())
	}
	if len(commands) != 0 {
		t.Fatalf("commands = %#v, want none", commands)
	}
}

func TestPruneAssetDockerRunsSSHCommand(t *testing.T) {
	router, token := initAssetControllerTest(t)
	var commands []string
	restore := controllers.SetAssetSSHRunnerForTest(
		func(host *models.AssetSSHHost, credential string) error { return nil },
		func(host *models.AssetSSHHost, credential string, command string) (string, error) {
			commands = append(commands, command)
			return "Deleted\n", nil
		},
	)
	t.Cleanup(restore)

	hostID := createAssetDockerHostForTest(t, router, token)
	cases := []struct {
		resource string
		want     string
	}{
		{resource: "containers", want: "docker container prune -f"},
		{resource: "networks", want: "docker network prune -f"},
		{resource: "volumes", want: "docker volume prune -f"},
		{resource: "images", want: "docker image prune -f"},
	}
	for _, tt := range cases {
		w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts/"+strconv.FormatInt(hostID, 10)+"/docker/"+tt.resource+"/prune", nil)
		if w.Code != http.StatusOK {
			t.Fatalf("%s prune status = %d, want 200; body=%s", tt.resource, w.Code, w.Body.String())
		}
		if got := commands[len(commands)-1]; got != tt.want {
			t.Fatalf("%s prune command = %q, want %q", tt.resource, got, tt.want)
		}
	}
}

func createAssetDockerHostForTest(t *testing.T, router *gin.Engine, token string) int64 {
	t.Helper()
	w := adminAssetRequest(router, token, http.MethodPost, "/api/admin/assets/ssh-hosts", map[string]any{
		"name":       "docker-action-host",
		"host":       "10.0.1.31",
		"port":       22,
		"username":   "root",
		"auth_type":  "password",
		"credential": "secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("create host status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	hosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{Query: "docker-action-host"})
	if err != nil || len(hosts) != 1 {
		t.Fatalf("ListAssetSSHHosts() = %d, %v", len(hosts), err)
	}
	return hosts[0].HostID
}
