//go:build wails

package main

import (
	"crypto/rand"
	"crypto/subtle"
	_ "embed"
	"errors"
	"fmt"
	"html/template"
	"log"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"bookstark/conf"
	"bookstark/controllers"
	"bookstark/i18n"
	"bookstark/routers"
)

// Only web URLs may leave the WebView through the external-link bridge.
// In particular, never pass file, script or OS command schemes to the opener.
func nativeExternalURL(message string) (string, bool) {
	address, ok := strings.CutPrefix(message, "bookstark:open-external:")
	if !ok || len(address) > 16384 {
		return "", false
	}
	u, err := url.Parse(address)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil {
		return "", false
	}
	return u.String(), true
}

//go:embed native/launcher.html
var launcherHTML string

//go:embed native/launcher.js
var launcherJS string

var launcherPage = template.Must(template.New("launcher").Parse(launcherHTML))

type launcher struct {
	bridgeTokens     map[string]string
	addr, token, dir string
	mu               sync.Mutex
	settingsMu       sync.Mutex
	credentialMu     sync.Mutex
	backend          http.Handler
	startError       error
	initialPassword  string
}

type launcherPageData struct {
	Remote     string
	Error      string
	FirstLogin string
	AutoStart  bool
	Tools      bool
	Ask        bool
	NeedsSetup bool
	Lang       string
	T          func(string) string
}

func newLauncher(dir string) (*launcher, net.Listener, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, nil, err
	}
	// Keep a stable origin so the WebView can reuse local storage and cookies.
	portPath := filepath.Join(dir, "workspace-port")
	port := "0"
	saved, err := os.ReadFile(portPath)
	if err == nil {
		value, err := strconv.ParseUint(string(saved), 10, 16)
		if err != nil || value < 1024 {
			return nil, nil, errors.New("invalid local workspace port")
		}
		port = strconv.FormatUint(value, 10)
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, nil, err
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:"+port)
	if err != nil {
		return nil, nil, fmt.Errorf("open workspace listener: %w", err)
	}
	if port == "0" {
		port := strconv.Itoa(listener.Addr().(*net.TCPAddr).Port)
		if err := writePrivateFile(portPath, []byte(port)); err != nil {
			listener.Close()
			return nil, nil, err
		}
	}
	return &launcher{addr: listener.Addr().String(), token: rand.Text(), dir: dir}, listener, nil
}

func (l *launcher) startURL() string {
	return "http://" + l.addr + "/__bookstark/open/" + l.token
}

func (l *launcher) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Host != l.addr {
		_, port, _ := net.SplitHostPort(l.addr)
		if controllers.IsLocalToolSandboxHost(r.Host, port) && (r.Method == http.MethodGet || r.Method == http.MethodHead) && !strings.HasPrefix(r.URL.Path, "/__bookstark/") && (!strings.HasPrefix(r.URL.Path, "/api/") || strings.HasPrefix(r.URL.Path, "/api/tool-assets/")) {
			l.mu.Lock()
			backend := l.backend
			l.mu.Unlock()
			if backend != nil {
				backend.ServeHTTP(w, r)
				return
			}
		}
		http.Error(w, "Invalid host", http.StatusForbidden)
		return
	}
	w.Header().Set("Referrer-Policy", "same-origin")
	if r.Method == http.MethodGet && subtle.ConstantTimeCompare([]byte(r.URL.Path), []byte("/__bookstark/open/"+l.token)) == 1 {
		http.SetCookie(w, &http.Cookie{
			Name: "bookstark_native", Value: l.token, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode,
		})
		// Commit a loopback document before using the Strict cookie. Android
		// reaches this page from its separate Wails asset origin.
		l.render(w, r, http.StatusOK, launcherPageData{AutoStart: r.URL.Query().Get("choose") != "1", Tools: r.URL.Query().Get("tools") == "1"})
		return
	}
	// Installed assets are read-only capabilities. A separate tool origin has
	// neither launcher nor login cookies and must not gain access to other routes.
	if strings.HasPrefix(r.URL.Path, "/api/tool-assets/") && (r.Method == http.MethodGet || r.Method == http.MethodHead || r.Method == http.MethodOptions) {
		l.mu.Lock()
		backend := l.backend
		l.mu.Unlock()
		if backend != nil {
			backend.ServeHTTP(w, r)
			return
		}
	}
	// Extensions do not share the WebView cookie. Only the Linkding API may
	// enter with an API token; launcher controls and other routes stay private.
	if l.serveBookmarkExtension(w, r) {
		return
	}
	if r.Header.Get("Sec-Fetch-Site") == "cross-site" ||
		(r.Header.Get("Origin") != "" && r.Header.Get("Origin") != "http://"+l.addr) {
		http.Error(w, "Invalid origin", http.StatusForbidden)
		return
	}
	cookie, err := r.Cookie("bookstark_native")
	if err != nil || subtle.ConstantTimeCompare([]byte(cookie.Value), []byte(l.token)) != 1 {
		http.Error(w, "Open this workspace from BookStark", http.StatusForbidden)
		return
	}
	switch {
	case r.URL.Path == "/__bookstark/tools" && r.Method == http.MethodPost:
		if _, err := l.startLocal("", ""); err != nil {
			http.Error(w, "local tools unavailable", 503)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"url":"/market"}`))
	case r.URL.Path == "/__bookstark/resume" && r.Method == http.MethodPost:
		l.resumeWorkspace(w, r)
	case r.URL.Path == "/__bookstark/client" && r.Method == http.MethodPost:
		l.serveClient(w, r)
	case r.URL.Path == "/__bookstark/launcher.js" && r.Method == http.MethodGet:
		w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		_, _ = w.Write([]byte(launcherJS))
	case r.URL.Path == "/__bookstark/" && r.Method == http.MethodGet:
		l.render(w, r, http.StatusOK, launcherPageData{})
	case r.URL.Path == "/__bookstark/remote" && r.Method == http.MethodPost:
		r.Body = http.MaxBytesReader(w, r.Body, 8192)
		if err := r.ParseForm(); err != nil {
			l.render(w, r, http.StatusBadRequest, launcherPageData{Error: "无法读取服务器地址。"})
			return
		}
		address, err := validateServerURL(r.PostForm.Get("address"))
		if err != nil {
			l.render(w, r, http.StatusBadRequest, launcherPageData{Error: err.Error(), Remote: r.PostForm.Get("address")})
			return
		}
		if err := writePrivateFile(filepath.Join(l.dir, "remote-url"), []byte(address)); err != nil {
			l.render(w, r, http.StatusInternalServerError, launcherPageData{Error: "无法保存服务器地址。"})
			return
		}
		if err := probeWorkspace(address); err != nil {
			l.render(w, r, http.StatusServiceUnavailable, launcherPageData{Error: "native.startup.unreachable", Remote: address})
			return
		}
		ask := r.PostForm.Get("remember") == "off"
		if err := l.rememberWorkspace("remote", address, &ask); err != nil {
			l.render(w, r, 500, launcherPageData{Error: "native.startup.save_error"})
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		http.Redirect(w, r, address, http.StatusSeeOther)
	case r.URL.Path == "/__bookstark/local" && r.Method == http.MethodPost:
		r.Body = http.MaxBytesReader(w, r.Body, 8192)
		if err := r.ParseForm(); err != nil {
			l.render(w, r, http.StatusBadRequest, launcherPageData{Error: "native.setup.invalid_form"})
			return
		}
		password, err := l.startLocal(r.PostForm.Get("password"), r.PostForm.Get("confirm_password"))
		if err != nil {
			if errors.Is(err, errLocalPassword) || errors.Is(err, errLocalPasswordMismatch) {
				l.render(w, r, http.StatusBadRequest, launcherPageData{Error: err.Error()})
				return
			}
			log.Printf("start local workspace: %v", err)
			l.render(w, r, http.StatusInternalServerError, launcherPageData{Error: "本地工作区启动失败。请检查磁盘空间和文件权限后重新打开应用。"})
			return
		}
		ask := r.PostForm.Get("remember") == "off"
		if err := l.rememberWorkspace("local", "", &ask); err != nil {
			l.render(w, r, 500, launcherPageData{Error: "native.startup.save_error"})
			return
		}
		if password != "" {
			l.render(w, r, http.StatusOK, launcherPageData{FirstLogin: password})
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		http.Redirect(w, r, "/", http.StatusSeeOther)
	case strings.HasPrefix(r.URL.Path, "/__bookstark/"):
		http.NotFound(w, r)
	default:
		l.mu.Lock()
		backend := l.backend
		l.mu.Unlock()
		if backend == nil {
			http.Redirect(w, r, "/__bookstark/", http.StatusSeeOther)
			return
		}
		backend.ServeHTTP(w, r)
	}
}

func (l *launcher) render(w http.ResponseWriter, r *http.Request, status int, data launcherPageData) {
	data.Lang = "zh"
	if strings.HasPrefix(strings.ToLower(r.Header.Get("Accept-Language")), "en") {
		data.Lang = "en"
	}
	if cookie, err := r.Cookie("lang"); err == nil && (cookie.Value == "en" || cookie.Value == "zh") {
		data.Lang = cookie.Value
	}
	data.T = i18n.MakeT(data.Lang)
	if data.Error != "" {
		data.Error = data.T(data.Error)
	}
	needsSetup, err := l.needsLocalSetup()
	if err != nil {
		status = http.StatusInternalServerError
		data.Error = data.T("native.setup.check_failed")
	}
	data.NeedsSetup = needsSetup
	p, prefsErr := l.preferences()
	if prefsErr != nil {
		data.AutoStart = false
		data.Error = data.T("native.startup.save_error")
	}
	data.Ask = p.Ask
	data.AutoStart = (data.Tools || (data.AutoStart && !p.Ask && p.Last != "")) && data.Error == ""

	if data.Remote == "" {
		previous, err := os.ReadFile(filepath.Join(l.dir, "remote-url"))
		if err == nil && len(previous) < 4096 {
			data.Remote = string(previous)
		}
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; connect-src 'self'; script-src 'self'; style-src 'unsafe-inline'; form-action 'self' http: https:; frame-ancestors 'none'")
	w.WriteHeader(status)
	if err := launcherPage.Execute(w, data); err != nil {
		log.Printf("render BookStark launcher: %v", err)
	}
}

func validateServerURL(raw string) (string, error) {
	address, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || address.Hostname() == "" || address.User != nil || address.Opaque != "" || address.ForceQuery || address.RawQuery != "" || address.Fragment != "" ||
		(address.Scheme != "http" && address.Scheme != "https") || len(raw) > 4096 {
		return "", errors.New("请输入完整的 HTTP 或 HTTPS 服务器地址。")
	}
	host := strings.ToLower(address.Hostname())
	ip, ipErr := netip.ParseAddr(host)
	// Cookies do not distinguish ports. Reserve 127/8 for the local
	// workspace; an explicit localhost URL can reach a separate service.
	labels := strings.Split(strings.TrimSuffix(host, "."), ".")
	lastLabel := labels[len(labels)-1]
	_, numeric := strconv.ParseUint(lastLabel, 0, 32)
	if (ipErr == nil && ip.Unmap().Is4() && ip.Unmap().IsLoopback()) ||
		(ipErr != nil && (numeric == nil || strings.HasPrefix(lastLabel, "0x"))) {
		return "", errors.New("请用 localhost 连接这台设备上另一个端口的服务。")
	}
	if address.Scheme == "http" {
		allowed := host == "localhost" || strings.HasSuffix(host, ".local") ||
			(ipErr == nil && (ip.IsPrivate() || ip.IsLoopback() || netip.MustParsePrefix("100.64.0.0/10").Contains(ip)))
		if !allowed {
			return "", errors.New("公网服务器请使用 HTTPS。局域网 HTTP 可填写内网 IP 或 .local 地址。")
		}
	}
	if address.Path == "" {
		address.Path = "/"
	}
	return address.String(), nil
}

var errLocalPassword = errors.New("native.setup.password_invalid")
var errLocalPasswordMismatch = errors.New("native.setup.password_mismatch")

func (l *launcher) needsLocalSetup() (bool, error) {
	_, err := os.Stat(filepath.Join(l.dir, "local", "bookstark.db"))
	if errors.Is(err, os.ErrNotExist) {
		return true, nil
	}
	return false, err
}

func validateLocalPassword(password, confirmation string) error {
	// bcrypt accepts at most 72 bytes. Preserve the exact password, including spaces.
	if utf8.RuneCountInString(password) < 8 || len(password) > 72 || strings.TrimSpace(password) == "" {
		return errLocalPassword
	}
	if password != confirmation {
		return errLocalPasswordMismatch
	}
	return nil
}

func (l *launcher) startLocal(password, confirmation string) (string, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.backend == nil {
		l.startError = nil
		needsSetup, err := l.needsLocalSetup()
		if err != nil {
			return "", err
		}
		if needsSetup {
			if password == "" && confirmation == "" {
				password, confirmation = defaultLocalAdminPassword, defaultLocalAdminPassword
			}
			if err := validateLocalPassword(password, confirmation); err != nil {
				return "", err
			}
		} else {
			password = ""
		}
		l.startError = l.openLocal(password)
		if l.startError == nil && needsSetup {
			if _, err := l.credential("http://"+l.addr, &savedCredential{Account: "admin", Password: password}, false); err != nil {
				return "", err
			}
			return password, nil
		}
	}
	if l.startError != nil {
		return "", l.startError
	}

	return "", nil
}

func (l *launcher) openLocal(password string) error {
	dir := filepath.Join(l.dir, "local")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	if err := os.Chdir(dir); err != nil {
		return err
	}
	conf.LoadDefaults()
	conf.App.Mode = "release"
	conf.App.DBPath = filepath.Join(dir, "bookstark.db")
	conf.App.WebDAVDBPath = filepath.Join(dir, "bookstark-webdav.db")
	conf.App.AdminAccount = "admin"
	secret, err := localSecret(filepath.Join(dir, "workspace.key"))
	if err != nil {
		return err
	}
	l.initialPassword = defaultLocalAdminPassword
	if password != "" {
		l.initialPassword = password
	}
	conf.App.AdminPassword = l.initialPassword
	conf.App.JWTSecret = secret
	conf.App.AssetSecret = secret
	routers.EmbedFS.StaticFS = EmbedFS.StaticFS
	routers.EmbedFS.TemplateFS = EmbedFS.TemplateFS
	routers.EmbedFS.ConfFS = EmbedFS.ConfFS
	conf.LoadAssetHashes(EmbedFS.StaticFS, "asset-hashes.json")
	if err := initDatabases(); err != nil {
		return err
	}
	conf.App.ToolLocalClient = true
	router := routers.Setup()
	if err := router.SetTrustedProxies(nil); err != nil {
		return err
	}
	l.backend = headMethodFallback(router)
	return nil
}

func localSecret(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err == nil {
		if len(data) != len(rand.Text()) {
			return "", errors.New("invalid local workspace key")
		}
		return string(data), nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	secret := rand.Text()
	return secret, writePrivateFile(path, []byte(secret))
}

func writePrivateFile(path string, data []byte) error {
	file, err := os.CreateTemp(filepath.Dir(path), ".bookstark-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	_, writeErr := file.Write(data)
	closeErr := file.Close()
	if err := errors.Join(writeErr, closeErr); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}

func newLauncherServer(launcher *launcher) *http.Server {
	return &http.Server{
		Handler: launcher, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second,
	}
}

func (l *launcher) webviewBootstrap(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	// The native Android asset handler cannot return a 3xx response.
	fmt.Fprintf(w, `<!doctype html><meta charset="utf-8"><meta name="referrer" content="no-referrer"><title>BookStark</title><meta http-equiv="refresh" content="0;url=%s">`, template.HTMLEscapeString(l.startURL()))
}
