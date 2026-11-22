//go:build wails && !dev

package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"bookstark/models"
)

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

	response, err = client.PostForm(base+"/__bookstark/local", nil)
	if data := read(response, err, http.StatusOK); l.initialPassword == "" || !strings.Contains(data, l.initialPassword) {
		t.Fatal("first login screen did not supply initial credentials")
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
	if err := models.UpdateMemberPassword(admin.MemberID, "a-changed-test-password"); err != nil {
		t.Fatal(err)
	}
	response, err = client.PostForm(base+"/__bookstark/local", nil)
	if data := read(response, err, http.StatusOK); strings.Contains(data, l.initialPassword) {
		t.Fatal("launcher exposed the old password")
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
