package main

import (
	"os"
	"strings"
	"testing"
)

func TestPasswordResetUIRoutesAndSettingsRemainIntegrated(t *testing.T) {
	files := map[string][]string{
		"templates/login.html":           {"/forgot-password", "PasswordResetAvailable"},
		"templates/forgot_password.html": {"/api/password/forgot", "identity", "forgot-form"},
		"templates/reset_password.html":  {"location.hash", "/api/password/reset", "history.replaceState", "new_password"},
		"templates/admin_system.html":    {"password_reset_enabled", "password_reset_expiry_minutes"},
		"routers/router.go":              {"controllers.ForgotPasswordPage", "controllers.ResetPasswordPage", "controllers.RequestPasswordReset", "controllers.CompletePasswordReset"},
	}
	for path, expected := range files {
		content, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		for _, item := range expected {
			if !strings.Contains(string(content), item) {
				t.Errorf("%s missing %q", path, item)
			}
		}
	}
}
