package controllers_test

import (
	"net/http"
	"testing"

	"bookstark/conf"
	"bookstark/models"
)

func TestDefaultHomeRedirectsByProfileSetting(t *testing.T) {
	router, token := initAssetControllerTest(t)
	admin, err := models.GetMemberByAccount(conf.App.AdminAccount)
	if err != nil {
		t.Fatalf("GetMemberByAccount() error = %v", err)
	}

	w := adminAssetRequest(router, token, http.MethodGet, "/", nil)
	if w.Code != http.StatusFound || w.Header().Get("Location") != "/notes" {
		t.Fatalf("default home status=%d location=%q, want 302 /notes", w.Code, w.Header().Get("Location"))
	}

	for home, location := range map[string]string{
		"tasks":     "/notes?tab=tasks",
		"articles":  "/notes?tab=articles",
		"books":     "/books",
		"bookmarks": "/bookmarks",
		"search":    "/search",
	} {
		w = adminAssetRequest(router, token, http.MethodPut, "/api/profile", map[string]any{
			"email":        admin.Email,
			"default_home": home,
		})
		if w.Code != http.StatusOK {
			t.Fatalf("PUT /api/profile default_home=%s status=%d body=%s", home, w.Code, w.Body.String())
		}
		w = adminAssetRequest(router, token, http.MethodGet, "/", nil)
		if w.Code != http.StatusFound || w.Header().Get("Location") != location {
			t.Fatalf("home=%s status=%d location=%q, want 302 %s", home, w.Code, w.Header().Get("Location"), location)
		}
	}
}

func TestDefaultHomeNavRendersHomeWithoutLoop(t *testing.T) {
	router, token := initAssetControllerTest(t)
	admin, err := models.GetMemberByAccount(conf.App.AdminAccount)
	if err != nil {
		t.Fatalf("GetMemberByAccount() error = %v", err)
	}

	w := adminAssetRequest(router, token, http.MethodPut, "/api/profile", map[string]any{
		"email":        admin.Email,
		"default_home": "nav",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("PUT /api/profile default_home=nav status=%d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET / with nav default status=%d, want 200; location=%q", w.Code, w.Header().Get("Location"))
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/nav", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /nav status=%d, want 200", w.Code)
	}
}

func TestUpdateProfileRejectsInvalidDefaultHome(t *testing.T) {
	router, token := initAssetControllerTest(t)
	admin, err := models.GetMemberByAccount(conf.App.AdminAccount)
	if err != nil {
		t.Fatalf("GetMemberByAccount() error = %v", err)
	}

	w := adminAssetRequest(router, token, http.MethodPut, "/api/profile", map[string]any{
		"email":        admin.Email,
		"default_home": "https://example.com",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("invalid default_home status=%d body=%s, want 400", w.Code, w.Body.String())
	}
}
