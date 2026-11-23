//go:build wails && !dev

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"bookstark/models"
)

func TestNativeExternalURL(t *testing.T) {
	for _, address := range []string{"https://example.com/path?q=中文#section", "http://127.0.0.1:8080/page"} {
		if got, ok := nativeExternalURL("bookstark:open-external:" + address); !ok || got == "" {
			t.Errorf("web URL rejected: %q", address)
		}
	}
	for _, message := range []string{
		"https://example.com", "bookstark:other:https://example.com",
		"bookstark:open-external:javascript:alert(1)", "bookstark:open-external:file:///etc/passwd",
		"bookstark:open-external:data:text/html,hello", "bookstark:open-external:cmd:calc",
		"bookstark:open-external:/relative", "bookstark:open-external:https://",
		"bookstark:open-external:https://user:pass@example.com", "bookstark:open-external:https://example.com/\n",
		"bookstark:open-external:https://example.com/" + strings.Repeat("a", 16384),
	} {
		if got, ok := nativeExternalURL(message); ok {
			t.Errorf("unsafe/unknown message accepted: %q -> %q", message, got)
		}
	}
}

func TestNativeWorkspaces(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	t.Cleanup(func() {
		if models.DB != nil {
			_ = models.DB.Close()
		}
		_ = models.CloseShareCommentDB()
		_ = os.Chdir(cwd)
	})
	l, listener, err := newLauncher(dir)
	if err != nil {
		t.Fatal(err)
	}
	server := newLauncherServer(l)
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Close() })

	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar}
	base := "http://" + l.addr
	read := func(response *http.Response, err error, expected int) string {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		data, err := io.ReadAll(response.Body)
		if err != nil {
			t.Fatal(err)
		}
		if response.StatusCode != expected {
			t.Fatalf("status %d, expected %d: %.400s", response.StatusCode, expected, data)
		}
		return string(data)
	}
	response, err := client.Get(base + "/__bookstark/")
	read(response, err, http.StatusForbidden)
	start, _ := http.NewRequest(http.MethodGet, l.startURL(), nil)
	start.Header.Set("Sec-Fetch-Site", "cross-site")
	response, err = client.Do(start)
	if data := read(response, err, http.StatusOK); !strings.Contains(data, "本地工作区") || !strings.Contains(data, "远程服务器") {
		t.Fatal("launcher is missing a mode")
	}
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := r.Cookie("bookstark_native"); err == nil {
			t.Error("local access cookie was sent to the remote server")
		}
		w.Write([]byte("remote test workspace"))
	}))
	defer remote.Close()
	remoteURL := strings.Replace(remote.URL, "127.0.0.1", "localhost", 1)
	response, err = client.PostForm(base+"/__bookstark/remote", url.Values{"address": {remoteURL}})
	if got := read(response, err, http.StatusOK); got != "remote test workspace" {
		t.Fatal("remote workspace did not load")
	}
	if _, err := os.Stat(filepath.Join(dir, "local")); !os.IsNotExist(err) {
		t.Fatal("remote mode unexpectedly initialized local data")
	}
	response, err = client.Get(base + "/__bookstark/")
	if data := read(response, err, http.StatusOK); !strings.Contains(data, remoteURL) {
		t.Fatal("remote address was not retained")
	}
	request, _ := http.NewRequest(http.MethodPost, base+"/__bookstark/local", nil)
	request.Header.Set("Origin", remoteURL)
	response, err = client.Do(request)
	read(response, err, http.StatusForbidden)

	for _, values := range []url.Values{
		{"password": {"short"}, "confirm_password": {"short"}},
		{"password": {"Local-Admin-2026!"}, "confirm_password": {"different"}},
	} {
		response, err = client.PostForm(base+"/__bookstark/local", values)
		read(response, err, http.StatusBadRequest)
		if _, err := os.Stat(filepath.Join(dir, "local", "bookstark.db")); !os.IsNotExist(err) {
			t.Fatal("invalid setup initialized a database")
		}
	}
	chosenPassword := defaultLocalAdminPassword
	response, err = client.PostForm(base+"/__bookstark/local", url.Values{})
	if data := read(response, err, http.StatusOK); l.initialPassword != chosenPassword || !strings.Contains(data, chosenPassword) || !strings.Contains(data, `id="copyPassword"`) {
		t.Fatal("first login screen did not supply initial credentials")
	}
	response, err = client.Get(base + "/__bookstark/launcher.js")
	read(response, err, http.StatusOK)
	response, err = client.Get(base + "/__bookstark/")
	if data := read(response, err, http.StatusOK); strings.Contains(data, `name="confirm_password"`) {
		t.Fatal("existing workspace asks for initialization again")
	}
	response, err = client.Get(base + "/login")
	if data := read(response, err, http.StatusOK); !strings.Contains(data, "BookStark") {
		t.Fatal("embedded login page did not load")
	}
	credentials, _ := json.Marshal(map[string]string{"account": "admin", "password": l.initialPassword})
	response, err = client.Post(base+"/api/login", "application/json", strings.NewReader(string(credentials)))
	read(response, err, http.StatusOK)
	if _, err := os.Stat(filepath.Join(dir, "local", "bookstark.db")); err != nil {
		t.Fatal("database was not created in the workspace:", err)
	}
	admin, err := models.GetMemberByAccount("admin")
	if err != nil {
		t.Fatal(err)
	}
	// A browser extension has no native or login cookie. Its API token must
	// support the full bookmark flow, without opening other native routes.
	apiToken, err := models.CreateApiToken(admin.MemberID, "browser extension test")
	if err != nil {
		t.Fatal(err)
	}
	extensionRequest := func(method, path, body, token string, expected int) string {
		t.Helper()
		req, _ := http.NewRequest(method, base+path, strings.NewReader(body))
		req.Header.Set("Origin", "chrome-extension://test-extension")
		req.Header.Set("Sec-Fetch-Site", "cross-site")
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Token "+token)
		}
		// A stale browser login must not override the valid API token.
		req.AddCookie(&http.Cookie{Name: "token", Value: "expired-browser-session"})
		resp, err := http.DefaultClient.Do(req)
		return read(resp, err, expected)
	}
	extensionRequest("GET", "/api/bookmarks/", "", "", http.StatusForbidden)
	extensionRequest("GET", "/api/bookmarks/", "", "invalid", http.StatusUnauthorized)
	extensionRequest("GET", "/api/tags/", "", apiToken.Token, http.StatusOK)
	extensionRequest("GET", "/api/bookmarks/check/?url=https://example.org", "", apiToken.Token, http.StatusOK)
	created := extensionRequest("POST", "/api/bookmarks/", `{"url":"https://example.org/native-extension","title":"Native extension bookmark","tag_names":["native-test"],"unread":true}`, apiToken.Token, http.StatusCreated)
	var bookmark struct {
		ID int64 `json:"id"`
	}
	if err := json.Unmarshal([]byte(created), &bookmark); err != nil || bookmark.ID <= 0 {
		t.Fatalf("invalid bookmark response: %s (%v)", created, err)
	}
	path := fmt.Sprintf("/api/bookmarks/%d/", bookmark.ID)
	extensionRequest("GET", path, "", apiToken.Token, http.StatusOK)
	extensionRequest("PATCH", path, `{"title":"Updated by extension"}`, apiToken.Token, http.StatusOK)
	if got := extensionRequest("GET", "/api/bookmarks/?q=Updated", "", apiToken.Token, http.StatusOK); !strings.Contains(got, "Updated by extension") {
		t.Fatal("extension could not search its saved bookmark")
	}
	extensionRequest("DELETE", path, "", apiToken.Token, http.StatusNoContent)
	for _, path := range []string{"/profile", "/api/api-tokens", "/api/bookmarks", "/__bookstark/local", "/__bookstark/remote"} {
		extensionRequest("POST", path, `{}`, apiToken.Token, http.StatusForbidden)
	}
	response, err = client.Get(base + "/api/csrf-token")
	read(response, err, http.StatusOK)
	revoke, _ := http.NewRequest(http.MethodDelete, fmt.Sprintf("%s/api/api-tokens/%d", base, apiToken.TokenID), nil)
	baseURL, _ := url.Parse(base)
	for _, cookie := range jar.Cookies(baseURL) {
		if cookie.Name == "csrf_token" {
			revoke.Header.Set("X-CSRF-Token", cookie.Value)
		}
	}
	response, err = client.Do(revoke)
	read(response, err, http.StatusOK)
	extensionRequest("GET", "/api/bookmarks/", "", apiToken.Token, http.StatusUnauthorized)
	if err := models.UpdateMemberPassword(admin.MemberID, "a-changed-test-password"); err != nil {
		t.Fatal(err)
	}
	response, err = client.PostForm(base+"/__bookstark/local", url.Values{"password": {"must-not-reset-existing"}, "confirm_password": {"must-not-reset-existing"}})
	if data := read(response, err, http.StatusOK); strings.Contains(data, l.initialPassword) {
		t.Fatal("launcher exposed the old password")
	}
	admin, err = models.GetMemberByAccount("admin")
	if err != nil || !admin.VerifyPassword("a-changed-test-password") {
		t.Fatal("existing admin password was replaced")
	}
	// Reopen the persisted workspace: a supplied setup password must not reset it.
	_ = models.DB.Close()
	_ = models.CloseShareCommentDB()
	reopened := &launcher{dir: dir}
	if password, err := reopened.startLocal("must-not-reset-existing", "must-not-reset-existing"); err != nil || password != "" {
		t.Fatalf("reopen: password disclosed=%v err=%v", password != "", err)
	}
	admin, err = models.GetMemberByAccount("admin")
	if err != nil || !admin.VerifyPassword("a-changed-test-password") {
		t.Fatal("reopen replaced the existing password")
	}
}

func TestValidateServerURL(t *testing.T) {
	for _, value := range []string{"https://example.com/bookstark", "http://192.168.50.1:8089", "http://nas.local", "http://100.64.0.1", "http://[::1]:8089"} {
		if _, err := validateServerURL(value); err != nil {
			t.Errorf("valid server address rejected %s: %v", value, err)
		}
	}
	for _, value := range []string{"foo", "file:///tmp/page", "https://user:pass@example.org", "http://example.org", "https://example.com/?token=example", "https://example.com/#private", "http://127.0.0.1:8089", "https://127.1:8089", "https://2130706433:8089"} {
		if _, err := validateServerURL(value); err == nil {
			t.Errorf("invalid server address accepted %s", value)
		}
	}
}

func TestValidateLocalPassword(t *testing.T) {
	for _, password := range []string{"abcdefgh", "密码安全测试八个", strings.Repeat("x", 72), "  keep spaces  "} {
		if err := validateLocalPassword(password, password); err != nil {
			t.Errorf("valid password rejected: %v", err)
		}
	}
	for _, password := range []string{"", "1234567", strings.Repeat("x", 73), strings.Repeat("密", 25), "        "} {
		if err := validateLocalPassword(password, password); err == nil {
			t.Error("invalid password accepted")
		}
	}
	if validateLocalPassword("abcdefgh", "abcdefgi") != errLocalPasswordMismatch {
		t.Fatal("mismatch accepted")
	}
}

func TestNativeLauncherBrowser(t *testing.T) {
	if os.Getenv("BOOKSTARK_BROWSER_TEST") != "1" {
		t.Skip("set BOOKSTARK_BROWSER_TEST=1")
	}
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	l, listener, err := newLauncher(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	server := newLauncherServer(l)
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() {
		_ = server.Close()
		if models.DB != nil {
			_ = models.DB.Close()
		}
		_ = models.CloseShareCommentDB()
		_ = os.Chdir(cwd)
	})
	cmd := exec.Command("node", filepath.Join(cwd, "tests/browser/native_launcher_browser_test.cjs"))
	cmd.Env = append(os.Environ(), "NATIVE_START_URL="+l.startURL())
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("native browser: %v\n%s", err, output)
	} else {
		t.Log(string(output))
	}
}
