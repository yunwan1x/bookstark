//go:build wails && !dev

package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestNativeBookmarkExtensionBoundary(t *testing.T) {
	l := &launcher{addr: "127.0.0.1:12345", token: "native-cookie"}
	for _, tc := range []struct {
		name, path, method, origin, requestMethod, headers string
		status                                             int
	}{
		{"chrome preflight", "/api/bookmarks/", "OPTIONS", "chrome-extension://test", "POST", "authorization,content-type", 204},
		{"firefox preflight", "/api/tags/", "OPTIONS", "moz-extension://test", "GET", "Authorization", 204},
		{"item preflight", "/api/bookmarks/12/", "OPTIONS", "chrome-extension://test", "PATCH", "authorization, content-type", 204},
		{"website preflight", "/api/bookmarks/", "OPTIONS", "https://example.org", "POST", "authorization,content-type", 403},
		{"null origin", "/api/bookmarks/", "OPTIONS", "null", "POST", "authorization", 403},
		{"unrelated headers", "/api/bookmarks/", "OPTIONS", "chrome-extension://test", "POST", "authorization,x-csrf-token", 403},
		{"missing auth header", "/api/bookmarks/", "OPTIONS", "chrome-extension://test", "POST", "content-type", 403},
		{"unsupported method", "/api/tags/", "OPTIONS", "chrome-extension://test", "DELETE", "authorization", 403},
		{"token controls", "/api/api-tokens", "OPTIONS", "chrome-extension://test", "POST", "authorization", 403},
		{"launcher controls", "/__bookstark/local", "OPTIONS", "chrome-extension://test", "POST", "authorization", 403},
		{"nested path", "/api/bookmarks/1/extra/", "OPTIONS", "chrome-extension://test", "GET", "authorization", 403},
		{"website with token", "/api/bookmarks/", "GET", "https://example.org", "", "", 403},
		{"workspace not open", "/api/bookmarks/", "GET", "chrome-extension://test", "", "", 503},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest(tc.method, "http://"+l.addr+tc.path, nil)
			r.Header.Set("Origin", tc.origin)
			r.Header.Set("Sec-Fetch-Site", "cross-site")
			r.Header.Set("Authorization", "Token test")
			r.Header.Set("Access-Control-Request-Method", tc.requestMethod)
			r.Header.Set("Access-Control-Request-Headers", tc.headers)
			w := httptest.NewRecorder()
			l.ServeHTTP(w, r)
			if w.Code != tc.status {
				t.Fatalf("status = %d, want %d: %s", w.Code, tc.status, w.Body.String())
			}
			if tc.status == http.StatusNoContent && w.Header().Get("Access-Control-Allow-Origin") != tc.origin {
				t.Fatal("extension preflight missing CORS response")
			}
		})
	}
	// Keep Host checking ahead of all token and CORS exceptions.
	r := httptest.NewRequest("OPTIONS", "http://other-host/api/bookmarks/", nil)
	r.Header.Set("Origin", "chrome-extension://test")
	r.Header.Set("Access-Control-Request-Method", "POST")
	r.Header.Set("Access-Control-Request-Headers", "authorization")
	w := httptest.NewRecorder()
	l.ServeHTTP(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatal("extension bypassed native Host validation")
	}
}
