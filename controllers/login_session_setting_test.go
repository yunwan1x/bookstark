package controllers_test

import (
	"net/http"
	"testing"

	"bookstark/models"
)

func TestUpdateSettingsValidatesLoginSessionDays(t *testing.T) {
	router, token := initAssetControllerTest(t)

	for _, value := range []string{"0", "366", "invalid"} {
		w := adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", map[string]any{
			"login_session_days": value,
		})
		if w.Code != http.StatusBadRequest {
			t.Fatalf("PUT login_session_days=%q status = %d, want 400; body=%s", value, w.Code, w.Body.String())
		}
	}

	w := adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", map[string]any{
		"login_session_days": "60",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("PUT valid login_session_days status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if got := models.GetSetting("login_session_days"); got != "60" {
		t.Fatalf("stored login_session_days = %q, want 60", got)
	}
}
