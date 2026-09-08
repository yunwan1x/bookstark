package main

import (
	"os"
	"strings"
	"testing"
)

func TestTaskEmailReminderUIAndRoutesRemainIntegrated(t *testing.T) {
	profile, err := os.ReadFile("templates/profile.html")
	if err != nil {
		t.Fatal(err)
	}
	admin, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatal(err)
	}
	router, err := os.ReadFile("routers/router.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{"panel-reminders", "task-reminder-enabled", "/api/profile/task-reminder", "saveReminderPreference", "testReminderMail"} {
		if !strings.Contains(string(profile), expected) {
			t.Errorf("profile reminder UI missing %q", expected)
		}
	}
	for _, expected := range []string{"mail_enabled", "task_email_reminder_enabled", "password_reset_enabled", "password_reset_expiry_minutes", "smtp_password", "testAdminMail", "mail-status-text"} {
		if !strings.Contains(string(admin), expected) {
			t.Errorf("admin mail settings UI missing %q", expected)
		}
	}
	for _, expected := range []string{"controllers.GetTaskReminderPreference", "controllers.UpdateTaskReminderPreference", "controllers.TestAdminMail", "controllers.GetAdminMailStatus"} {
		if !strings.Contains(string(router), expected) {
			t.Errorf("mail route missing %q", expected)
		}
	}
}
