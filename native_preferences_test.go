//go:build wails && !dev

package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

func TestClientPreferencesAndCredentialIsolation(t *testing.T) {
	l := &launcher{dir: t.TempDir(), addr: "127.0.0.1:12345", token: "native"}
	local := "http://" + l.addr
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("server")) }))
	defer remote.Close()
	remoteAddress := strings.Replace(remote.URL, "127.0.0.1", "localhost", 1)
	if _, err := l.clientAction(clientRequest{Origin: local, Operation: "credentials-save", Account: "admin", Password: "password"}); err == nil {
		t.Fatal("credential writes must require main-document handshake")
	}
	tokens := map[string]string{}
	action := func(target *launcher, request clientRequest) (any, error) {
		key := target.dir + "|" + request.Origin
		// Each launcher instance has its own handshake; refresh on every call.
		info, err := target.clientAction(clientRequest{Origin: request.Origin, Operation: "info"})
		if err != nil {
			return nil, err
		}
		tokens[key] = info.(map[string]any)["bridgeToken"].(string)
		request.BridgeToken = tokens[key]
		return target.clientAction(request)
	}

	// A failed connection must not replace the last successful workspace.
	if err := l.rememberWorkspace("local", "", nil); err != nil {
		t.Fatal(err)
	}
	if err := probeWorkspace(remoteAddress); err != nil {
		t.Fatal(err)
	}
	if err := l.rememberWorkspace("remote", remoteAddress, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := action(l, clientRequest{Origin: local, Operation: "save", Ask: true}); err != nil {
		t.Fatal(err)
	}
	reopened := &launcher{dir: l.dir, addr: l.addr}
	p, err := reopened.preferences()
	if err != nil || p.Last != "remote" || p.Remote != remoteAddress || !p.Ask {
		t.Fatalf("preferences not persisted: %+v %v", p, err)
	}
	for origin, password := range map[string]string{local: "local-secret", remoteAddress: "remote-secret"} {
		if _, err := action(l, clientRequest{Origin: origin, Operation: "credentials-save", Account: "admin", Password: password}); err != nil {
			t.Fatal(err)
		}
		value, err := action(reopened, clientRequest{Origin: origin, Operation: "credentials-load"})
		if err != nil || value.(*savedCredential).Password != password {
			t.Fatal("credentials not retained across restart")
		}
	}
	files, _ := filepath.Glob(filepath.Join(l.dir, "credentials", "*.enc"))
	for _, file := range files {
		data, _ := os.ReadFile(file)
		if bytes.Contains(data, []byte("secret")) || bytes.Contains(data, []byte("admin")) {
			t.Fatal("credentials stored in plaintext")
		}
		info, _ := os.Stat(file)
		if info.Mode().Perm()&0077 != 0 {
			t.Fatal("vault file readable by other users")
		}
	}
	if _, err := action(l, clientRequest{Origin: "https://other.example", Operation: "credentials-load"}); err == nil {
		t.Fatal("untrusted origin read credentials")
	}
	if _, err := action(l, clientRequest{Origin: local, Operation: "credentials-clear"}); err != nil {
		t.Fatal(err)
	}
	if saved, err := l.credential(local, nil, false); err != nil || saved != nil {
		t.Fatal("forget left saved credentials")
	}
	if saved, err := l.credential(remoteAddress, nil, false); err != nil || saved.Password != "remote-secret" {
		t.Fatal("forget cleared another workspace")
	}
	// Unavailable saved remote returns a recoverable error and retains preferences.
	remote.Close()
	w := httptest.NewRecorder()
	l.resumeWorkspace(w, httptest.NewRequest("POST", "http://"+l.addr+"/__bookstark/resume", nil))
	if w.Code != 503 {
		t.Fatalf("failed resume returned %d", w.Code)
	}
	after, _ := l.preferences()
	if after != p {
		t.Fatal("failed resume changed workspace selection")
	}
	// Cross-site calls cannot use the credential endpoint, even with a native cookie.
	body, _ := json.Marshal(clientRequest{Origin: local, Operation: "credentials-load"})
	r := httptest.NewRequest("POST", "http://"+l.addr+"/__bookstark/client", bytes.NewReader(body))
	r.AddCookie(&http.Cookie{Name: "bookstark_native", Value: l.token})
	r.Header.Set("Origin", "https://other.example")
	w = httptest.NewRecorder()
	l.ServeHTTP(w, r)
	if w.Code != 403 {
		t.Fatal("cross-site access bypassed launcher protection")
	}
}

func TestCredentialVaultDetectsTampering(t *testing.T) {
	l := &launcher{dir: t.TempDir()}
	if _, err := l.credential("https://one.example", &savedCredential{Account: "user", Password: "secret"}, false); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(filepath.Join(l.dir, "credentials", "*.enc"))
	data, _ := os.ReadFile(files[0])
	data[len(data)-1] ^= 1
	if err := os.WriteFile(files[0], data, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := l.credential("https://one.example", nil, false); err == nil {
		t.Fatal("tampered credentials accepted")
	}
}

func TestNativeMarketPreferencesRetainedAcrossWorkspaceChanges(t *testing.T) {
	l := &launcher{dir: t.TempDir(), addr: "127.0.0.1:12345"}
	if err := l.rememberWorkspace("remote", "https://workspace.example", nil); err != nil {
		t.Fatal(err)
	}
	origin := "http://" + l.addr
	info, err := l.clientAction(clientRequest{Origin: origin, Operation: "info"})
	if err != nil {
		t.Fatal(err)
	}
	token := info.(map[string]any)["bridgeToken"].(string)
	if _, err := l.clientAction(clientRequest{Origin: origin, BridgeToken: token, Operation: "market-settings-save", MarketURL: "https://tools.example/market", CheckUpdates: false, AutoUpdate: true}); err != nil {
		t.Fatal(err)
	}
	if err := l.rememberWorkspace("local", "", nil); err != nil {
		t.Fatal(err)
	}
	if err := l.rememberWorkspace("remote", "https://other-workspace.example", nil); err != nil {
		t.Fatal(err)
	}
	if _, err := l.clientAction(clientRequest{Origin: origin, BridgeToken: token, Operation: "tools-open"}); err != nil {
		t.Fatal(err)
	}
	reopened := &launcher{dir: l.dir, addr: l.addr}
	p, err := reopened.preferences()
	if err != nil || p.ToolMarketURL != "https://tools.example/market" || p.ToolCheckUpdates == nil || *p.ToolCheckUpdates || !p.ToolAutoUpdate || p.Last != "remote" || p.Remote != "https://other-workspace.example" {
		t.Fatalf("opening tools or changing workspace lost saved preferences: %+v %v", p, err)
	}
	for _, operation := range []string{"market-settings", "market-settings-save", "tools-open"} {
		if _, err := l.clientAction(clientRequest{Origin: origin, Operation: operation}); err == nil {
			t.Fatalf("%s bypassed main-document handshake", operation)
		}
	}
}

func TestNativeRemoteResumeBrowser(t *testing.T) {
	if os.Getenv("BOOKSTARK_BROWSER_TEST") != "1" {
		t.Skip("set BOOKSTARK_BROWSER_TEST=1")
	}
	var available atomic.Bool
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := r.Cookie("bookstark_native"); err == nil {
			t.Error("native access cookie leaked to remote")
		}
		if r.URL.Path == "/ready" && r.Method == "POST" {
			available.Store(true)
			w.WriteHeader(204)
			return
		}
		if !available.Load() {
			w.WriteHeader(503)
			return
		}
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("<h1>Remote workspace ready</h1>"))
	}))
	defer remote.Close()
	remoteAddress := strings.Replace(remote.URL, "127.0.0.1", "localhost", 1)
	l, listener, err := newLauncher(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := l.rememberWorkspace("remote", remoteAddress, nil); err != nil {
		t.Fatal(err)
	}
	server := newLauncherServer(l)
	go server.Serve(listener)
	defer server.Close()
	cwd, _ := os.Getwd()
	cmd := exec.Command("node", filepath.Join(cwd, "tests/browser/native_remote_resume_browser_test.cjs"))
	cmd.Env = append(os.Environ(), "NATIVE_START_URL="+l.startURL(), "NATIVE_REMOTE_URL="+remoteAddress)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("remote resume: %v\n%s", err, output)
	} else {
		t.Log(string(output))
	}
	if _, err := os.Stat(filepath.Join(l.dir, "local")); !os.IsNotExist(err) {
		t.Fatal("remote failure initialized a local workspace")
	}
}
