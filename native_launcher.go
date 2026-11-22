//go:build wails

package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	_ "embed"
	"encoding/base64"
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

	"bookstark/conf"
	"bookstark/models"
	"bookstark/routers"
)

//go:embed native/launcher.html
var launcherHTML string

var launcherPage = template.Must(template.New("launcher").Parse(launcherHTML))

type launcher struct {
	addr, token, dir string
	mu               sync.Mutex
	backend          http.Handler
	startError       error
	initialPassword  string
}

type launcherPageData struct {
	Remote     string
	Error      string
	FirstLogin string
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
		l.render(w, http.StatusOK, launcherPageData{})
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
	case r.URL.Path == "/__bookstark/" && r.Method == http.MethodGet:
		l.render(w, http.StatusOK, launcherPageData{})
	case r.URL.Path == "/__bookstark/remote" && r.Method == http.MethodPost:
		r.Body = http.MaxBytesReader(w, r.Body, 8192)
		if err := r.ParseForm(); err != nil {
			l.render(w, http.StatusBadRequest, launcherPageData{Error: "无法读取服务器地址。"})
			return
		}
		address, err := validateServerURL(r.PostForm.Get("address"))
		if err != nil {
			l.render(w, http.StatusBadRequest, launcherPageData{Error: err.Error(), Remote: r.PostForm.Get("address")})
			return
		}
		if err := writePrivateFile(filepath.Join(l.dir, "remote-url"), []byte(address)); err != nil {
			l.render(w, http.StatusInternalServerError, launcherPageData{Error: "无法保存服务器地址。"})
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		http.Redirect(w, r, address, http.StatusSeeOther)
	case r.URL.Path == "/__bookstark/local" && r.Method == http.MethodPost:
		password, err := l.startLocal()
		if err != nil {
			log.Printf("start local workspace: %v", err)
			l.render(w, http.StatusInternalServerError, launcherPageData{Error: "本地工作区启动失败。请检查磁盘空间和文件权限后重新打开应用。"})
			return
		}
		if password != "" {
			l.render(w, http.StatusOK, launcherPageData{FirstLogin: password})
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

func (l *launcher) render(w http.ResponseWriter, status int, data launcherPageData) {
	if data.Remote == "" {
		previous, err := os.ReadFile(filepath.Join(l.dir, "remote-url"))
		if err == nil && len(previous) < 4096 {
			data.Remote = string(previous)
		}
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self' http: https:; frame-ancestors 'none'")
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

func (l *launcher) startLocal() (string, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.backend == nil && l.startError == nil {
		l.startError = l.openLocal()
	}
	if l.startError != nil {
		return "", l.startError
	}
	if admin, err := models.GetMemberByAccount("admin"); err == nil && admin.VerifyPassword(l.initialPassword) {
		return l.initialPassword, nil
	}
	return "", nil
}

func (l *launcher) openLocal() error {
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
	passwordMAC := hmac.New(sha256.New, []byte(secret))
	passwordMAC.Write([]byte("BookStark initial local admin password"))
	l.initialPassword = base64.RawURLEncoding.EncodeToString(passwordMAC.Sum(nil)[:12])
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
