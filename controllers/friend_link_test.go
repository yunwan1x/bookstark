package controllers_test

import (
	"bookstark/models"
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestFooterQRCodeUploadAndSave(t *testing.T) {
	router, token := initAssetControllerTest(t)
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Chdir(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(wd)
	img := image.NewRGBA(image.Rect(0, 0, 40, 40))
	for y := 0; y < 40; y++ {
		for x := 0; x < 40; x++ {
			c := color.White
			if (x/5+y/5)%2 == 0 {
				c = color.Black
			}
			img.Set(x, y, c)
		}
	}
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	part, err := w.CreateFormFile("file", "social-qr.png")
	if err != nil {
		t.Fatal(err)
	}
	if err = png.Encode(part, img); err != nil {
		t.Fatal(err)
	}
	if err = w.WriteField("category", "editor"); err != nil {
		t.Fatal(err)
	}
	if err = w.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/api/uploads", &body)
	req.Header.Set("Authorization", "Token "+token)
	req.Header.Set("Content-Type", w.FormDataContentType())
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)
	var data struct {
		Data struct {
			URL string `json:"url"`
		} `json:"data"`
	}
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &data) != nil || !strings.HasPrefix(data.Data.URL, "/upload-files/") {
		t.Fatal(response.Code, response.Body.String())
	}
	items := map[string]any{"items": []models.FriendLink{{LinkName: "QR", QRCode: data.Data.URL, GroupName: "Social", IsEnabled: 1}}}
	if response = adminAssetRequest(router, token, "PUT", "/api/admin/friend-links", items); response.Code != 200 {
		t.Fatal(response.Code, response.Body.String())
	}
	if response = adminAssetRequest(router, "", "GET", data.Data.URL, nil); response.Code != 200 {
		t.Fatal("uploaded QR unavailable", response.Code)
	}
}

func TestFooterAdminSaveAndPublicRendering(t *testing.T) {
	router, token := initAssetControllerTest(t)
	body := map[string]any{"items": []models.FriendLink{
		{LinkName: "Documentation", LinkURL: "https://example.com/docs", GroupName: "Resources", GroupOrder: 1, IsEnabled: 1},
		{LinkName: "Public QR", QRCode: "/upload-files/editor/test.png", GroupName: "Follow us", GroupOrder: 2, IsEnabled: 1, Description: "<script>alert(1)</script>"},
		{LinkName: "Disabled footer entry", LinkURL: "https://example.com/hidden", IsEnabled: 0},
	}}
	if w := adminAssetRequest(router, "", http.MethodPut, "/api/admin/friend-links", body); w.Code != 401 {
		t.Fatalf("unauthenticated write=%d", w.Code)
	}
	if w := adminAssetRequest(router, token, http.MethodPut, "/api/admin/friend-links", body); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	for _, page := range []string{"/home", "/profile", "/nav", "/bookmarks", "/shares"} {
		w := adminAssetRequest(router, token, http.MethodGet, page, nil)
		if w.Code != 200 {
			t.Fatalf("%s: %d", page, w.Code)
		}
		html := w.Body.String()
		for _, want := range []string{`class="site-footer"`, `Resources`, `Follow us`, `/upload-files/editor/test.png`, `&lt;script&gt;alert(1)&lt;/script&gt;`} {
			if !strings.Contains(html, want) {
				t.Errorf("%s missing %s", page, want)
			}
		}
		if strings.Contains(html, "Disabled footer entry") {
			t.Errorf("%s shows disabled entry", page)
		}
	}
	if w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/friend-links", nil); w.Code != 200 || !strings.Contains(w.Body.String(), `"qr_code":"/upload-files/editor/test.png"`) {
		t.Fatal("metadata missing")
	}
	body["simple_mode"] = true
	if w := adminAssetRequest(router, token, "PUT", "/api/admin/friend-links", body); w.Code != 200 {
		t.Fatal(w.Code)
	}
	w := adminAssetRequest(router, token, "GET", "/shares", nil)
	html := w.Body.String()
	if !strings.Contains(html, `class="site-footer-simple"`) || !strings.Contains(html, "https://example.com/docs") || strings.Contains(html, "/upload-files/editor/test.png") || strings.Contains(html, `class="site-footer-groups"`) {
		t.Fatal("simple rendering incorrect")
	}
	body["simple_mode"] = false
	if w := adminAssetRequest(router, token, "PUT", "/api/admin/friend-links", body); w.Code != 200 {
		t.Fatal(w.Code)
	}
	w = adminAssetRequest(router, token, "GET", "/shares", nil)
	if !strings.Contains(w.Body.String(), "/upload-files/editor/test.png") {
		t.Fatal("QR lost switching back")
	}
}
