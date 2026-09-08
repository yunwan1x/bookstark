package controllers_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"bookstark/models"
)

func TestPasswordResetPublicFlowQueuesMailAndChangesPassword(t *testing.T) {
	router, _ := initAssetControllerTest(t)
	member, err := models.GetMemberByAccount("admin")
	if err != nil {
		t.Fatal(err)
	}
	if err := models.UpdateMemberProfile(member.MemberID, "admin@example.com", "notes"); err != nil {
		t.Fatal(err)
	}
	if err := models.BatchUpdateSettings(map[string]string{
		"mail_enabled": "1", "password_reset_enabled": "1",
		"smtp_host": "smtp.example.com", "smtp_port": "587",
		"mail_from_address": "notify@example.com", "mail_public_url": "https://books.example.com",
		"password_reset_expiry_minutes": "30",
	}); err != nil {
		t.Fatal(err)
	}

	w := shareCommentRequestFromIP(router, http.MethodPost, "/api/password/forgot", map[string]any{"identity": "admin@example.com"}, "192.0.2.44")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), "如果账号存在") {
		t.Fatalf("forgot response = %d %s", w.Code, w.Body.String())
	}
	mail, err := models.ClaimNextMail(time.Now().Add(time.Minute))
	if err != nil || mail == nil {
		t.Fatalf("queued mail = %#v, %v", mail, err)
	}
	if mail.Kind != "password_reset" || mail.ToEmail != "admin@example.com" {
		t.Fatalf("unexpected mail = %#v", mail)
	}
	marker := "#token="
	start := strings.Index(mail.HTMLBody, marker)
	if start < 0 {
		t.Fatalf("reset token missing from mail")
	}
	start += len(marker)
	end := strings.IndexAny(mail.HTMLBody[start:], "\"<")
	if end < 0 {
		t.Fatalf("reset token terminator missing")
	}
	token := mail.HTMLBody[start : start+end]

	w = shareCommentRequestFromIP(router, http.MethodPost, "/api/password/reset", map[string]any{
		"token": token, "new_password": "reset-secret", "confirm_password": "reset-secret",
	}, "192.0.2.44")
	if w.Code != http.StatusOK {
		t.Fatalf("reset response = %d %s", w.Code, w.Body.String())
	}
	member, err = models.GetMemberByAccount("admin")
	if err != nil || !member.VerifyPassword("reset-secret") {
		t.Fatalf("password not reset: %v", err)
	}

	w = shareCommentRequestFromIP(router, http.MethodPost, "/api/password/reset", map[string]any{
		"token": token, "new_password": "second-secret", "confirm_password": "second-secret",
	}, "192.0.2.44")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("reused token response = %d %s", w.Code, w.Body.String())
	}
}

func TestPasswordResetDoesNotRevealUnknownAccount(t *testing.T) {
	router, _ := initAssetControllerTest(t)
	if err := models.BatchUpdateSettings(map[string]string{
		"mail_enabled": "1", "password_reset_enabled": "1",
		"smtp_host": "smtp.example.com", "mail_from_address": "notify@example.com",
		"mail_public_url": "https://books.example.com",
	}); err != nil {
		t.Fatal(err)
	}
	w := shareCommentRequestFromIP(router, http.MethodPost, "/api/password/forgot", map[string]any{"identity": "missing@example.com"}, "192.0.2.45")
	if w.Code != http.StatusOK {
		t.Fatalf("unknown account response = %d %s", w.Code, w.Body.String())
	}
	var response struct {
		Message string `json:"message"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil || !strings.Contains(response.Message, "如果账号存在") {
		t.Fatalf("unexpected generic response: %s, %v", w.Body.String(), err)
	}
	mail, err := models.ClaimNextMail(time.Now().Add(time.Minute))
	if err != nil || mail != nil {
		t.Fatalf("unknown account queued mail = %#v, %v", mail, err)
	}
}
