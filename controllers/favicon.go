package controllers

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"bookstark/models"

	"github.com/gin-gonic/gin"
)

const (
	faviconCacheDir      = "data/favicon"
	faviconMaxSize       = 1 << 20 // 1MB
	faviconClientTimeout = 5 * time.Second
)

var (
	faviconClient = &http.Client{
		Timeout: faviconClientTimeout,
		Transport: &http.Transport{
			MaxIdleConns:    20,
			MaxConnsPerHost: 5,
			IdleConnTimeout: 30 * time.Second,
		},
	}
	faviconInFlight sync.Map
	faviconSem      = make(chan struct{}, 5) // max 5 concurrent favicon fetches
	faviconMigrate  sync.Once
)

// faviconCachePath returns the cache file path for a given favicon URL.
func faviconCachePath(faviconURL string) string {
	ext := ".ico"
	u, err := url.Parse(faviconURL)
	if err == nil {
		path := strings.ToLower(u.Path)
		switch {
		case strings.HasSuffix(path, ".png"):
			ext = ".png"
		case strings.HasSuffix(path, ".svg"):
			ext = ".svg"
		case strings.HasSuffix(path, ".gif"):
			ext = ".gif"
		case strings.HasSuffix(path, ".jpg") || strings.HasSuffix(path, ".jpeg"):
			ext = ".jpg"
		case strings.HasSuffix(path, ".webp"):
			ext = ".webp"
		}
	}
	return filepath.Join(faviconCacheDir, fmt.Sprintf("%s%s", models.FaviconURLHash(faviconURL), ext))
}

// FaviconProxy handles /api/favicon?url=xxx requests.
// It fetches the favicon from the remote URL, caches it locally, and serves it.
// On failure, redirects to the original URL as a fallback.
func FaviconProxy(c *gin.Context) {
	ensureFaviconFileCacheMigrated()

	faviconURL := c.Query("url")
	if faviconURL == "" {
		c.Redirect(http.StatusFound, "/static/favicon.svg")
		return
	}

	if !isSafeFaviconURL(faviconURL) {
		// 合法的 http/https URL 即使 DNS 校验失败，也让浏览器直接加载
		// 仅对非 http/https 的危险 URL（javascript:, data:, file: 等）重定向到程序图标
		u, err := url.Parse(faviconURL)
		if err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != "" {
			c.Redirect(http.StatusFound, faviconURL)
			return
		}
		c.Redirect(http.StatusFound, "/static/favicon.svg")
		return
	}

	// Check cache
	faviconMaxAge := time.Duration(models.GetFaviconCacheDays()) * 24 * time.Hour
	if entry, err := models.LoadFaviconCache(faviconURL); err == nil && entry != nil {
		cacheAge := time.Since(entry.UpdatedAt)
		if cacheAge < faviconMaxAge {
			serveFaviconCacheEntry(c, entry, http.StatusOK, "public, max-age=604800")
			if cacheAge > faviconMaxAge*3/4 {
				go refreshFaviconCache(faviconURL)
			}
			return
		}
		serveFaviconCacheEntry(c, entry, http.StatusOK, "public, max-age=300")
		go refreshFaviconCache(faviconURL)
		return
	} else if err != nil {
		log.Printf("favicon: db cache read failed for %s: %v", faviconURL, err)
	}

	cachePath := faviconCachePath(faviconURL)
	if info, err := os.Stat(cachePath); err == nil {
		if time.Since(info.ModTime()) < faviconMaxAge {
			c.Header("Cache-Control", "public, max-age=604800")
			c.Header("Content-Type", faviconContentType(cachePath))
			c.File(cachePath)
			if time.Since(info.ModTime()) > faviconMaxAge*3/4 {
				go refreshFaviconCache(faviconURL)
			}
			return
		}
	}

	// Dedup: if a request for this URL is already in flight, wait briefly and serve cache
	if _, loaded := faviconInFlight.LoadOrStore(faviconURL, struct{}{}); loaded {
		// Another goroutine is fetching; wait a moment and try cache
		time.Sleep(200 * time.Millisecond)
		if entry, err := models.LoadFaviconCache(faviconURL); err == nil && entry != nil {
			serveFaviconCacheEntry(c, entry, http.StatusOK, "public, max-age=300")
			return
		}
		if _, statErr := os.Stat(cachePath); statErr == nil {
			c.Header("Cache-Control", "public, max-age=300")
			c.Header("Content-Type", faviconContentType(cachePath))
			c.File(cachePath)
			return
		}
		// Still no cache, redirect
		c.Redirect(http.StatusFound, faviconURL)
		return
	}
	defer faviconInFlight.Delete(faviconURL)

	// Fetch from remote (with concurrency limit)
	faviconSem <- struct{}{}
	data, mimeType, extension, err := fetchFavicon(faviconURL)
	<-faviconSem
	if err != nil {
		log.Printf("favicon: fetch failed for %s: %v", faviconURL, err)
		// Serve stale cache if available
		if _, statErr := os.Stat(cachePath); statErr == nil {
			c.Header("Cache-Control", "public, max-age=300")
			c.Header("Content-Type", faviconContentType(cachePath))
			c.File(cachePath)
			return
		}
		c.Redirect(http.StatusFound, faviconURL)
		return
	}
	entry, err := models.StoreFaviconCache(faviconURL, mimeType, extension, data)
	if err != nil {
		log.Printf("favicon: db cache write failed for %s: %v", faviconURL, err)
	}
	if entry != nil {
		serveFaviconCacheEntry(c, entry, http.StatusOK, "public, max-age=604800")
		return
	}

	c.Header("Cache-Control", "public, max-age=604800")
	c.Header("Content-Type", mimeType)
	c.Data(http.StatusOK, mimeType, data)
}

// isSafeFaviconURL validates that a favicon URL is safe to fetch.
func isSafeFaviconURL(rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return false
	}
	if u.Host == "" {
		return false
	}
	return isSafeURL(rawURL).Safe
}

// fetchFavicon downloads a favicon from the remote URL.
func fetchFavicon(faviconURL string) ([]byte, string, string, error) {
	req, err := http.NewRequest("GET", faviconURL, nil)
	if err != nil {
		return nil, "", "", err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "image/*,*/*;q=0.1")

	resp, err := faviconClient.Do(req)
	if err != nil {
		return nil, "", "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, "", "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	limited := io.LimitReader(resp.Body, faviconMaxSize+1)
	data, err := io.ReadAll(limited)
	if err != nil {
		return nil, "", "", err
	}
	if len(data) == 0 {
		return nil, "", "", fmt.Errorf("empty response")
	}
	if len(data) > faviconMaxSize {
		return nil, "", "", fmt.Errorf("response too large")
	}

	mimeType := strings.TrimSpace(strings.Split(resp.Header.Get("Content-Type"), ";")[0])
	extension := faviconExtensionFromURL(faviconURL)
	if mimeType == "" || !strings.HasPrefix(strings.ToLower(mimeType), "image/") {
		detected := http.DetectContentType(data)
		if strings.HasPrefix(strings.ToLower(detected), "image/") {
			mimeType = detected
		}
	}
	if extension == ".svg" && !strings.HasPrefix(strings.ToLower(mimeType), "image/") {
		mimeType = "image/svg+xml"
	}
	if mimeType == "" || (!strings.HasPrefix(strings.ToLower(mimeType), "image/") && extension != ".svg") {
		return nil, "", "", fmt.Errorf("unsupported content type %q", mimeType)
	}

	if extension == "" {
		extension = faviconExtensionFromMime(mimeType)
	}
	if extension == "" {
		extension = ".ico"
	}
	if mimeType == "" {
		mimeType = models.FaviconMimeTypeFromExtension(extension)
	}
	return data, mimeType, extension, nil
}

// refreshFaviconCache asynchronously refreshes a stale favicon cache entry.
func refreshFaviconCache(faviconURL string) {
	faviconSem <- struct{}{}
	data, mimeType, extension, err := fetchFavicon(faviconURL)
	<-faviconSem
	if err != nil {
		log.Printf("favicon: async refresh failed for %s: %v", faviconURL, err)
		return
	}
	if _, err := models.StoreFaviconCache(faviconURL, mimeType, extension, data); err != nil {
		log.Printf("favicon: async cache write failed for %s: %v", faviconURL, err)
	}
}

// faviconContentType returns the Content-Type based on file extension.
func faviconContentType(path string) string {
	return models.FaviconMimeTypeFromExtension(filepath.Ext(path))
}

func faviconExtensionFromURL(faviconURL string) string {
	u, err := url.Parse(faviconURL)
	if err != nil {
		return ""
	}
	switch strings.ToLower(filepath.Ext(u.Path)) {
	case ".png", ".svg", ".gif", ".jpg", ".jpeg", ".webp", ".ico":
		return strings.ToLower(filepath.Ext(u.Path))
	default:
		return ""
	}
}

func faviconExtensionFromMime(mimeType string) string {
	switch strings.ToLower(mimeType) {
	case "image/png":
		return ".png"
	case "image/svg+xml":
		return ".svg"
	case "image/gif":
		return ".gif"
	case "image/jpeg":
		return ".jpg"
	case "image/webp":
		return ".webp"
	case "image/x-icon", "image/vnd.microsoft.icon":
		return ".ico"
	default:
		return ""
	}
}

func serveFaviconCacheEntry(c *gin.Context, entry *models.FaviconCacheEntry, status int, cacheControl string) {
	mimeType := entry.MimeType
	if mimeType == "" {
		mimeType = models.FaviconMimeTypeFromExtension(entry.Extension)
	}
	c.Header("Cache-Control", cacheControl)
	if entry.ContentHash != "" {
		c.Header("ETag", `"`+entry.ContentHash+`"`)
	}
	c.Data(status, mimeType, entry.Data)
}

func ensureFaviconFileCacheMigrated() {
	faviconMigrate.Do(func() {
		migrated, err := models.MigrateFaviconFileCache(faviconCacheDir)
		if err != nil {
			log.Printf("favicon: file cache migration failed: %v", err)
			return
		}
		if migrated > 0 {
			log.Printf("favicon: migrated %d file cache entries to db", migrated)
		}
	})
}
