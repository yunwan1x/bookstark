//go:build wails

package main

import (
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"bookstark/models"
)

func bookmarkExtensionMethod(path, method string) bool {
	switch path {
	case "/api/bookmarks/":
		return method == http.MethodGet || method == http.MethodPost
	case "/api/bookmarks/check/", "/api/tags/":
		return method == http.MethodGet
	}
	if id, ok := strings.CutPrefix(path, "/api/bookmarks/"); ok && strings.HasSuffix(id, "/") {
		id = strings.TrimSuffix(id, "/")
		if n, err := strconv.ParseInt(id, 10, 64); err == nil && n > 0 && strconv.FormatInt(n, 10) == id {
			return method == http.MethodGet || method == http.MethodPatch || method == http.MethodPut || method == http.MethodDelete
		}
	}
	return false
}

func extensionOrigin(origin string) bool {
	u, err := url.Parse(origin)
	return err == nil && (u.Scheme == "chrome-extension" || u.Scheme == "moz-extension") &&
		u.Host != "" && u.User == nil && u.Port() == "" && u.Path == "" && u.RawQuery == "" && u.Fragment == ""
}

// Returns false for requests which still require the native workspace cookie.
func (l *launcher) serveBookmarkExtension(w http.ResponseWriter, r *http.Request) bool {
	method := r.Method
	if method == http.MethodOptions {
		method = r.Header.Get("Access-Control-Request-Method")
	}
	if !bookmarkExtensionMethod(r.URL.Path, method) {
		return false
	}
	origin := r.Header.Get("Origin")
	if origin != "" && origin != "http://"+l.addr && !extensionOrigin(origin) {
		return false
	}
	if r.Method == http.MethodOptions {
		// Preflight carries no token. Restrict it to extension origins and the
		// headers used by the plugin. Actual requests must authenticate below.
		if !extensionOrigin(origin) {
			return false
		}
		hasAuthorization := false
		for _, header := range strings.Split(r.Header.Get("Access-Control-Request-Headers"), ",") {
			switch strings.ToLower(strings.TrimSpace(header)) {
			case "authorization":
				hasAuthorization = true
			case "content-type":
			default:
				return false
			}
		}
		if !hasAuthorization {
			return false
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Methods", method)
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.WriteHeader(http.StatusNoContent)
		return true
	}
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Token ")
	if !ok || token == "" {
		return false
	}
	l.mu.Lock()
	backend := l.backend
	l.mu.Unlock()
	if backend == nil {
		http.Error(w, "Open the local workspace in BookStark first", http.StatusServiceUnavailable)
		return true
	}
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Cache-Control", "no-store")
	apiToken, member, err := models.GetApiTokenCached(token)
	if err != nil || apiToken == nil || member == nil {
		http.Error(w, "Invalid API token", http.StatusUnauthorized)
		return true
	}
	// Authenticate as the token owner even if the browser sends an unrelated
	// login cookie. Never let cookie authentication replace this credential.
	request := r.Clone(r.Context())
	request.Header.Del("Cookie")
	backend.ServeHTTP(w, request)
	return true
}
