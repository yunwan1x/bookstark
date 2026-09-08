package controllers_test

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"bookstark/models"
)

func TestShareEditSaveUpdatesOriginalBlog(t *testing.T) {
	router, apiToken := initAssetControllerTest(t)

	w := adminAssetRequest(router, apiToken, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Share edit persistence",
		"blog_type":    "article",
		"editor_type":  "markdown",
		"blog_content": "before share edit",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}
	var created struct {
		Data models.Blog `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode blog response: %v", err)
	}

	editToken := strings.Repeat("a", 64)
	share, err := models.CreateShare("blog", created.Data.BlogID, created.Data.MemberID, editToken)
	if err != nil {
		t.Fatalf("CreateShare() error = %v", err)
	}

	updatedContent := "saved through editable share"
	w = adminAssetRequest(router, apiToken, http.MethodPut,
		"/api/shares/"+url.PathEscape(share.ShareIdentify)+"/edit?token="+url.QueryEscape(editToken),
		map[string]any{"content": updatedContent},
	)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT share edit status = %d, body=%s", w.Code, w.Body.String())
	}
	var saved struct {
		Code int `json:"code"`
		Data struct {
			ModifyTime string `json:"modify_time"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &saved); err != nil {
		t.Fatalf("decode share save response: %v", err)
	}
	if saved.Code != 0 || saved.Data.ModifyTime == "" {
		t.Fatalf("unexpected share save response: %s", w.Body.String())
	}

	blog, err := models.GetBlogByID(created.Data.BlogID)
	if err != nil {
		t.Fatalf("GetBlogByID() error = %v", err)
	}
	if blog.BlogContent != updatedContent {
		t.Fatalf("original blog content = %q, want %q", blog.BlogContent, updatedContent)
	}
	if blog.Version < 2 {
		t.Fatalf("blog version = %d, want share edit to increment it", blog.Version)
	}
}

func TestPresentationShareEditUploadsImageThroughSystemPipeline(t *testing.T) {
	router, apiToken := initAssetControllerTest(t)

	w := adminAssetRequest(router, apiToken, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Presentation image upload",
		"blog_type":    "article",
		"editor_type":  models.PresentationType,
		"blog_content": models.DefaultPresentation("Presentation image upload"),
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}
	var created struct {
		Data models.Blog `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode blog response: %v", err)
	}

	editToken := strings.Repeat("p", 64)
	share, err := models.CreateShare("blog", created.Data.BlogID, created.Data.MemberID, editToken)
	if err != nil {
		t.Fatalf("CreateShare() error = %v", err)
	}

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("file", "slide.png")
	if err != nil {
		t.Fatalf("CreateFormFile() error = %v", err)
	}
	img := image.NewRGBA(image.Rect(0, 0, 1, 1))
	img.Set(0, 0, color.RGBA{R: 37, G: 99, B: 235, A: 255})
	var imageData bytes.Buffer
	if err := png.Encode(&imageData, img); err != nil {
		t.Fatalf("encode PNG: %v", err)
	}
	if _, err := part.Write(imageData.Bytes()); err != nil {
		t.Fatalf("write PNG part: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	path := "/api/shares/" + url.PathEscape(share.ShareIdentify) +
		"/edit/uploads?token=" + url.QueryEscape(editToken)
	req := httptest.NewRequest(http.MethodPost, path, &body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	w = httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("POST presentation share image status = %d, body=%s", w.Code, w.Body.String())
	}
	var uploaded struct {
		Code int `json:"code"`
		Data struct {
			URL string `json:"url"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &uploaded); err != nil {
		t.Fatalf("decode upload response: %v", err)
	}
	if uploaded.Code != 0 || !strings.HasPrefix(uploaded.Data.URL, "/upload-files/") {
		t.Fatalf("unexpected upload response: %s", w.Body.String())
	}
	t.Cleanup(func() {
		rel := strings.TrimPrefix(uploaded.Data.URL, "/upload-files/")
		_ = os.Remove(filepath.Join(models.UploadBaseDir, filepath.Clean(rel)))
	})
}
