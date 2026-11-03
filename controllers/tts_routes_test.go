package controllers_test

import (
	"bookstark/models"
	"testing"
)

func TestTTSRoutesRequireLoginAndAIEnabled(t *testing.T) {
	r, token := initAssetControllerTest(t)
	for _, path := range []string{"/api/ai/tts/voices", "/api/ai/tts/stream"} {
		method := "GET"
		if path == "/api/ai/tts/stream" {
			method = "POST"
		}
		w := adminAssetRequest(r, "", method, path, map[string]string{"text": "hello"})
		if w.Code != 401 {
			t.Fatal(path, w.Code)
		}
		if err := models.BatchUpdateSettings(map[string]string{"ai_enabled": "0"}); err != nil {
			t.Fatal(err)
		}
		w = adminAssetRequest(r, token, method, path, map[string]string{"text": "hello"})
		if w.Code != 403 {
			t.Fatal(path, w.Code, w.Body.String())
		}
	}
	if err := models.BatchUpdateSettings(map[string]string{"ai_enabled": "1"}); err != nil {
		t.Fatal(err)
	}
	w := adminAssetRequest(r, token, "GET", "/api/ai/tts/voices", nil)
	if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal(w.Code, w.Body.String())
	}
}
