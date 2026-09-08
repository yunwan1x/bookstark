package controllers

import "testing"

func TestValidateMailSetting(t *testing.T) {
	tests := []struct {
		key, value string
		wantError  bool
	}{
		{"mail_enabled", "1", false},
		{"mail_enabled", "yes", true},
		{"password_reset_enabled", "1", false},
		{"password_reset_enabled", "yes", true},
		{"password_reset_expiry_minutes", "30", false},
		{"password_reset_expiry_minutes", "4", true},
		{"smtp_host", "smtp.example.com", false},
		{"smtp_host", "https://smtp.example.com", true},
		{"smtp_port", "587", false},
		{"smtp_port", "70000", true},
		{"smtp_encryption", "starttls", false},
		{"smtp_encryption", "ssl3", true},
		{"mail_from_address", "notify@example.com", false},
		{"mail_from_address", "bad-address", true},
		{"mail_public_url", "https://books.example.com", false},
		{"mail_public_url", "javascript:alert(1)", true},
		{"mail_timeout_seconds", "10", false},
		{"mail_timeout_seconds", "1", true},
	}
	for _, test := range tests {
		err := validateMailSetting(test.key, test.value)
		if (err != nil) != test.wantError {
			t.Errorf("validateMailSetting(%q, %q) error=%v, wantError=%v", test.key, test.value, err, test.wantError)
		}
	}
}
