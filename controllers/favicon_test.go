package controllers

import (
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"bookstark/models"

	"github.com/gin-gonic/gin"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func TestFaviconProxyStoresAndServesDBCache(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tempDir := t.TempDir()
	if models.DB != nil {
		_ = models.DB.Close()
		models.DB = nil
	}
	if err := models.InitDB(filepath.Join(tempDir, "main.db")); err != nil {
		t.Fatalf("InitDB() error = %v", err)
	}
	if err := models.SetFaviconCacheDBPath(filepath.Join(tempDir, "favicon.db")); err != nil {
		t.Fatalf("SetFaviconCacheDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = models.CloseFaviconCacheDB()
		_ = models.SetFaviconCacheDBPath("")
		if models.DB != nil {
			_ = models.DB.Close()
			models.DB = nil
		}
	})

	oldClient := faviconClient
	requests := 0
	faviconClient = &http.Client{
		Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			requests++
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     http.Header{"Content-Type": []string{"image/svg+xml"}},
				Body:       io.NopCloser(strings.NewReader(`<svg xmlns="http://www.w3.org/2000/svg"></svg>`)),
				Request:    req,
			}, nil
		}),
	}
	faviconMigrate = sync.Once{}
	t.Cleanup(func() {
		faviconClient = oldClient
		faviconMigrate = sync.Once{}
	})

	router := gin.New()
	router.GET("/api/favicon", FaviconProxy)
	faviconURL := "http://93.184.216.34/favicon.svg"

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/favicon?url="+faviconURL, nil)
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("first status = %d, body = %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "image/svg+xml") {
		t.Fatalf("first content type = %q", ct)
	}

	entry, err := models.LoadFaviconCache(faviconURL)
	if err != nil {
		t.Fatalf("LoadFaviconCache() error = %v", err)
	}
	if entry == nil {
		t.Fatalf("favicon cache entry was not stored")
	}

	w = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/favicon?url="+faviconURL, nil)
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("second status = %d, body = %s", w.Code, w.Body.String())
	}
	if requests != 1 {
		t.Fatalf("remote fetches = %d, want 1", requests)
	}
}
