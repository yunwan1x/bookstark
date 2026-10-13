package controllers_test

import (
	"bookstark/models"
	"bytes"
	"image"
	"image/png"
	"mime/multipart"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestBackgroundUploadPrivacyAndReset(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if w := adminAssetRequest(router, "", "GET", "/api/profile/background", nil); w.Code != 401 {
		t.Fatal(w.Code)
	}
	save := func(mode string, raw []byte, remove string) *httptest.ResponseRecorder {
		var body bytes.Buffer
		m := multipart.NewWriter(&body)
		m.WriteField("mode", mode)
		m.WriteField("fade", "65")
		m.WriteField("animated", "false")
		m.WriteField("remove", remove)
		if raw != nil {
			f, _ := m.CreateFormFile("file", "test.png")
			f.Write(raw)
		}
		m.Close()
		req := httptest.NewRequest("PUT", "/api/profile/background", &body)
		req.Header.Set("Content-Type", m.FormDataContentType())
		req.Header.Set("Authorization", "Token "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)
		return w
	}
	if w := save("image", nil, ""); w.Code != 400 {
		t.Fatal("missing image", w.Code)
	}
	var pngData bytes.Buffer
	png.Encode(&pngData, image.NewRGBA(image.Rect(0, 0, 64, 32)))
	if w := save("image", pngData.Bytes(), ""); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	imageURL := "/api/profile/background/image"
	w := adminAssetRequest(router, token, "GET", imageURL, nil)
	if w.Code != 200 || w.Header().Get("Content-Type") != "image/jpeg" || !strings.Contains(w.Header().Get("Cache-Control"), "private") {
		t.Fatal(w.Code, w.Header())
	}
	if other, _, err := models.GetBackgroundImage(9999); err == nil || len(other) > 0 {
		t.Fatal("image leaked to another member")
	}
	if w := adminAssetRequest(router, "", "GET", imageURL, nil); w.Code != 401 {
		t.Fatal("anonymous image access", w.Code)
	}
	req := httptest.NewRequest("GET", imageURL, nil)
	req.Header.Set("Authorization", "Token "+token)
	req.Header.Set("If-None-Match", w.Header().Get("ETag"))
	cached := httptest.NewRecorder()
	router.ServeHTTP(cached, req)
	if cached.Code != 304 {
		t.Fatal("image redownloaded", cached.Code)
	}
	if w := save("image", []byte("invalid"), ""); w.Code != 400 {
		t.Fatal("invalid upload accepted")
	}
	if w := adminAssetRequest(router, token, "GET", imageURL, nil); w.Code != 200 {
		t.Fatal("failed upload removed image")
	}
	if w := save("solid", nil, ""); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if w := save("image", nil, ""); w.Code != 200 {
		t.Fatal("saved image lost")
	}
	if w := save("dynamic", nil, "true"); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if w := adminAssetRequest(router, token, "GET", imageURL, nil); w.Code != 404 {
		t.Fatal("reset retained image")
	}
	if w := adminAssetRequest(router, token, "GET", "/profile", nil); w.Code != 200 || !strings.Contains(w.Body.String(), `id="background-mode"`) {
		t.Fatal("profile rendering", w.Code)
	}
}
