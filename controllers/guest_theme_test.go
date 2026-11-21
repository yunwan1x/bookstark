package controllers_test

import (
	"bookstark/models"
	"net/http"
	"strings"
	"testing"
)

func TestGuestDefaultThemeSettingsAndFirstPaint(t *testing.T) {
	router, token := initAssetControllerTest(t)
	save := func(value string) int {
		return adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", map[string]any{"guest_default_theme": value}).Code
	}
	if got := models.GetGuestDefaultTheme(); got != "light" {
		t.Fatalf("initial default=%s", got)
	}
	for _, theme := range []string{"light", "nvidia", "apple", "glass", "hud"} {
		if status := save(theme); status != http.StatusOK {
			t.Fatalf("save %s: %d", theme, status)
		}
		if got := models.GetGuestDefaultTheme(); got != theme {
			t.Fatalf("saved %s got %s", theme, got)
		}
	}
	for _, path := range []string{"/shares", "/notes/public", "/login", "/register", "/forgot-password", "/reset-password"} {
		response := adminAssetRequest(router, "", http.MethodGet, path, nil)
		if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `name="bookstark-default-theme" content="hud"`) {
			t.Fatalf("guest %s status=%d missing HUD first paint", path, response.Code)
		}
	}
	response := adminAssetRequest(router, token, http.MethodGet, "/shares", nil)
	if !strings.Contains(response.Body.String(), `name="bookstark-default-theme" content="light"`) {
		t.Fatal("guest setting must not change authenticated fallback")
	}
	for _, invalid := range []string{"", "dark", "__proto__", "HUD", "<script>alert(1)</script>"} {
		if status := save(invalid); status != http.StatusBadRequest {
			t.Fatalf("invalid %q accepted: %d", invalid, status)
		}
		if models.GetGuestDefaultTheme() != "hud" {
			t.Fatal("invalid save changed setting")
		}
	}
	response = adminAssetRequest(router, "", http.MethodPut, "/api/admin/settings", map[string]any{"guest_default_theme": "apple"})
	if response.Code == http.StatusOK || models.GetGuestDefaultTheme() != "hud" {
		t.Fatal("guest may not change system default")
	}
	if status := save("glass"); status != http.StatusOK {
		t.Fatal(status)
	}
	response = adminAssetRequest(router, "", http.MethodGet, "/shares", nil)
	if !strings.Contains(response.Body.String(), `name="bookstark-default-theme" content="glass"`) {
		t.Fatal("next request did not receive new default")
	}
	if err := models.BatchUpdateSettings(map[string]string{"guest_default_theme": "invalid-legacy-value"}); err != nil {
		t.Fatal(err)
	}
	if models.GetGuestDefaultTheme() != "light" {
		t.Fatal("corrupt stored setting should fall back to light")
	}
}
