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

func TestRichDocumentBlogStoresCompressedAndServesRawJSON(t *testing.T) {
	router, token := initAssetControllerTest(t)
	content := `{"schema":"bookstark-richdoc","schema_version":1,"editor_version":"0.9.137","data":{"main":[{"value":"富文档接口测试"},{"type":"image","value":"/upload-files/editor/test.webp","width":20,"height":10}]},"options":{},"comments":[]}`
	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Rich document API test",
		"blog_type":    "article",
		"editor_type":  "richdoc",
		"blog_content": content,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}
	var created struct {
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}
	blog, err := models.GetBlogByID(created.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	if !models.IsCompressedContent(blog.BlogContent) {
		t.Fatalf("rich document blog content is not compressed")
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/blogs/"+strconv.FormatInt(created.Data.BlogID, 10)+"/content/raw", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET rich document raw content status = %d, body=%s", w.Code, w.Body.String())
	}
	if got := w.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/json") {
		t.Fatalf("Content-Type = %q, want application/json", got)
	}
	if got := w.Header().Get("Content-Encoding"); got != "gzip" {
		t.Fatalf("Content-Encoding = %q, want gzip", got)
	}
	zr, err := gzip.NewReader(w.Body)
	if err != nil {
		t.Fatalf("gzip.NewReader() error = %v", err)
	}
	defer zr.Close()
	raw, err := io.ReadAll(zr)
	if err != nil {
		t.Fatalf("read raw content: %v", err)
	}
	if string(raw) != content {
		t.Fatalf("raw rich document content differs from source")
	}
}

func TestRichDocumentAPIRejectsEmbeddedImage(t *testing.T) {
	router, token := initAssetControllerTest(t)
	content := `{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"type":"image","value":"data:image/png;base64,iVBORw0KGgo="}]},"options":{},"comments":[]}`
	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Embedded image rejection test",
		"blog_type":    "article",
		"editor_type":  "richdoc",
		"blog_content": content,
	})
	if w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), "不能嵌入文档") {
		t.Fatalf("POST embedded rich document status = %d, body=%s", w.Code, w.Body.String())
	}
}

func TestEncryptedRichDocumentCompressesBeforeEncryption(t *testing.T) {
	router, token := initAssetControllerTest(t)
	content := `{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"加密富文档"}]},"options":{},"comments":[]}`
	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Encrypted rich document test",
		"blog_type":    "article",
		"editor_type":  "richdoc",
		"blog_content": content,
		"new_password": "richdoc-password",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST encrypted rich document status = %d, body=%s", w.Code, w.Body.String())
	}
	var created struct {
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}
	blog, err := models.GetBlogByID(created.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	plain, err := models.DecryptContent("richdoc-password", blog.BlogContent)
	if err != nil {
		t.Fatalf("DecryptContent() error = %v", err)
	}
	if !models.IsCompressedContent(plain) {
		t.Fatalf("decrypted rich document should retain the compressed envelope")
	}
	decoded, err := models.DecodeContentForType(models.RichDocumentType, plain)
	if err != nil || decoded != content {
		t.Fatalf("decoded encrypted rich document mismatch: error=%v", err)
	}
}
