package controllers_test

import (
	"compress/gzip"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"bookstark/models"
)

func TestCreateEncryptedBlog(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Encrypted create test",
		"blog_type":    "article",
		"editor_type":  "markdown",
		"blog_content": "",
		"new_password": "secret-pass",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}

	var resp struct {
		Code int `json:"code"`
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.Code != 0 || resp.Data.BlogID == 0 {
		t.Fatalf("unexpected response: %s", w.Body.String())
	}

	blog, err := models.GetBlogByID(resp.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	if !blog.HasPassword() {
		t.Fatalf("created blog should have password")
	}
	if !blog.VerifyPassword("secret-pass") {
		t.Fatalf("created blog password should verify")
	}
	if !models.IsEncrypted(blog.BlogContent) {
		t.Fatalf("created blog content should be encrypted, got %q", blog.BlogContent)
	}
	plain, err := models.DecryptContent("secret-pass", blog.BlogContent)
	if err != nil {
		t.Fatalf("DecryptContent() error = %v", err)
	}
	if plain != "" {
		t.Fatalf("decrypted content = %q, want empty", plain)
	}
}

func TestCreateHTMLBlogStoresManualDescription(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "HTML description test",
		"blog_type":    "article",
		"editor_type":  "html",
		"blog_content": "<h1>HTML content should stay out of preview</h1>",
		"blog_desc":    "人工录入 HTML 摘要",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}

	var createResp struct {
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createResp); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	blog, err := models.GetBlogByID(createResp.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	if blog.BlogDesc != "人工录入 HTML 摘要" {
		t.Fatalf("BlogDesc = %q", blog.BlogDesc)
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/blogs/"+strconv.FormatInt(createResp.Data.BlogID, 10), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /api/blogs/:id status = %d, body=%s", w.Code, w.Body.String())
	}
	var getResp struct {
		Data struct {
			BlogDesc    string `json:"blog_desc"`
			BlogContent string `json:"blog_content"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &getResp); err != nil {
		t.Fatalf("decode get response: %v", err)
	}
	if getResp.Data.BlogDesc != "人工录入 HTML 摘要" {
		t.Fatalf("GET BlogDesc = %q", getResp.Data.BlogDesc)
	}
	if getResp.Data.BlogContent != "" {
		t.Fatalf("HTML blog content should not be inlined, got %q", getResp.Data.BlogContent)
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/blogs?type=article&editor_type=html", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}
	var listResp struct {
		Data []struct {
			BlogID         int64  `json:"blog_id"`
			BlogDesc       string `json:"blog_desc"`
			ContentPreview string `json:"content_preview"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &listResp); err != nil {
		t.Fatalf("decode list response: %v", err)
	}
	var found bool
	for _, item := range listResp.Data {
		if item.BlogID == createResp.Data.BlogID {
			found = true
			if item.BlogDesc != "人工录入 HTML 摘要" {
				t.Fatalf("listed BlogDesc = %q", item.BlogDesc)
			}
			if item.ContentPreview != "人工录入 HTML 摘要" {
				t.Fatalf("listed ContentPreview = %q", item.ContentPreview)
			}
		}
	}
	if !found {
		t.Fatalf("created blog not found in list: %#v", listResp.Data)
	}
}

func TestCreateEncryptedDrawingBlogEncryptsDefaultContent(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Encrypted drawing create test",
		"blog_type":    "article",
		"editor_type":  "drawing",
		"new_password": "draw-pass",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}

	var resp struct {
		Code int `json:"code"`
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	blog, err := models.GetBlogByID(resp.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	if !models.IsEncrypted(blog.BlogContent) {
		t.Fatalf("drawing default content should be encrypted, got %q", blog.BlogContent)
	}
	plain, err := models.DecryptContent("draw-pass", blog.BlogContent)
	if err != nil {
		t.Fatalf("DecryptContent() error = %v", err)
	}
	if !strings.Contains(plain, `"elements"`) {
		t.Fatalf("decrypted drawing content = %q, want default drawing scene", plain)
	}
}

func TestCreateBlogRejectsOversizedMarkdownContent(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Oversized markdown create test",
		"blog_type":    "article",
		"editor_type":  "markdown",
		"blog_content": strings.Repeat("x", 500001),
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("POST /api/blogs status = %d, want %d, body=%s", w.Code, http.StatusBadRequest, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "博客内容不能超过500KB") {
		t.Fatalf("POST /api/blogs body = %s, want oversized content message", w.Body.String())
	}
}

func TestCreateHTMLBlogAllowsContentUpToFiveMB(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "HTML five MB create allowed test",
		"blog_type":    "article",
		"editor_type":  "html",
		"blog_content": strings.Repeat("x", 500001),
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, want %d, body=%s", w.Code, http.StatusOK, w.Body.String())
	}
}

func TestCreateHTMLBlogRejectsContentOverFiveMB(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "HTML five MB create reject test",
		"blog_type":    "article",
		"editor_type":  "html",
		"blog_content": strings.Repeat("x", 5242881),
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("POST /api/blogs status = %d, want %d, body=%s", w.Code, http.StatusBadRequest, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "HTML内容不能超过5MB") {
		t.Fatalf("POST /api/blogs body = %s, want HTML oversized content message", w.Body.String())
	}
}

func TestUpdateHTMLBlogRejectsContentOverFiveMB(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "HTML five MB update reject source",
		"blog_type":    "article",
		"editor_type":  "html",
		"blog_content": "<p>small</p>",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}

	var createResp struct {
		Code int `json:"code"`
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createResp); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodPut, "/api/blogs/"+strconv.FormatInt(createResp.Data.BlogID, 10), map[string]any{
		"blog_title":   "HTML five MB update reject source",
		"blog_content": strings.Repeat("x", 5242881),
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("PUT /api/blogs/:id status = %d, want %d, body=%s", w.Code, http.StatusBadRequest, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "HTML内容不能超过5MB") {
		t.Fatalf("PUT /api/blogs/:id body = %s, want HTML oversized content message", w.Body.String())
	}
}

func TestCreateHTMLBlogCompressesContentAndRawEndpointReturnsHTML(t *testing.T) {
	router, token := initAssetControllerTest(t)
	html := "<section><h1>Compressed HTML</h1><p>" + strings.Repeat("payload ", 200) + "</p></section>"

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Compressed HTML blog",
		"blog_type":    "article",
		"editor_type":  "html",
		"blog_content": html,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}

	var createResp struct {
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createResp); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	blog, err := models.GetBlogByID(createResp.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	if !strings.HasPrefix(blog.BlogContent, "CMP:v1:gzip:") {
		t.Fatalf("BlogContent should be stored compressed, got prefix %.24q", blog.BlogContent)
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/blogs/"+strconv.FormatInt(createResp.Data.BlogID, 10)+"/content/raw", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET raw HTML status = %d, body=%s", w.Code, w.Body.String())
	}
	if got := w.Header().Get("Content-Encoding"); got != "gzip" {
		t.Fatalf("Content-Encoding = %q, want gzip", got)
	}
	zr, err := gzip.NewReader(w.Body)
	if err != nil {
		t.Fatalf("gzip reader: %v", err)
	}
	defer zr.Close()
	body, err := io.ReadAll(zr)
	if err != nil {
		t.Fatalf("read gzip body: %v", err)
	}
	if string(body) != html {
		t.Fatalf("raw HTML body mismatch")
	}
}

func TestUpdateBlogTitleOnlyKeepsContent(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Title only update source",
		"blog_type":    "article",
		"editor_type":  "markdown",
		"blog_content": "original article body",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}

	var createResp struct {
		Code int `json:"code"`
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createResp); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodPut, "/api/blogs/"+strconv.FormatInt(createResp.Data.BlogID, 10), map[string]any{
		"blog_title": "Title only update renamed",
		"labels":     "",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("PUT /api/blogs/:id status = %d, body=%s", w.Code, w.Body.String())
	}

	blog, err := models.GetBlogByID(createResp.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	if blog.BlogTitle != "Title only update renamed" {
		t.Fatalf("BlogTitle = %q, want renamed title", blog.BlogTitle)
	}
	if blog.BlogContent != "original article body" {
		t.Fatalf("BlogContent = %q, want original body", blog.BlogContent)
	}
}
