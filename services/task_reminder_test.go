package services

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"bookstark/models"
)

func setupReminderTestDB(t *testing.T) *models.Member {
	t.Helper()
	if models.DB != nil {
		_ = models.DB.Close()
	}
	if err := models.InitDB(filepath.Join(t.TempDir(), "reminder.db")); err != nil {
		t.Fatalf("InitDB: %v", err)
	}
	t.Cleanup(func() {
		_ = models.DB.Close()
		models.DB = nil
	})
	member, err := models.GetMemberByID(1)
	if err != nil {
		t.Fatalf("GetMemberByID: %v", err)
	}
	if err := models.UpdateMemberProfile(member.MemberID, "admin@example.com", "notes"); err != nil {
		t.Fatalf("UpdateMemberProfile: %v", err)
	}
	member.Email = "admin@example.com"
	return member
}

func TestQueueTaskReminderDigestsGroupsAndDeduplicates(t *testing.T) {
	member := setupReminderTestDB(t)
	if err := models.BatchUpdateSettings(map[string]string{
		"mail_enabled": "1", "task_email_reminder_enabled": "1",
		"smtp_host": "smtp.example.com", "smtp_port": "587",
		"mail_from_address": "notify@example.com", "mail_public_url": "https://books.example.com",
	}); err != nil {
		t.Fatalf("BatchUpdateSettings: %v", err)
	}
	if err := models.UpsertTaskReminderPreference(models.TaskReminderPreference{
		MemberID: member.MemberID, Enabled: true, SendTime: "09:00",
		RemindBeforeDays: 3, IncludeOverdue: true,
	}); err != nil {
		t.Fatalf("UpsertTaskReminderPreference: %v", err)
	}
	now := time.Date(2026, 7, 14, 9, 5, 0, 0, time.Local)
	for _, task := range []models.Task{
		{Content: "今日任务", DueDate: "2026-07-14", MemberID: member.MemberID},
		{Content: "区间内任务", DueDate: "2026-07-15", MemberID: member.MemberID},
		{Content: "提前任务", DueDate: "2026-07-17", MemberID: member.MemberID},
		{Content: "逾期任务", DueDate: "2026-07-10", MemberID: member.MemberID},
	} {
		copy := task
		if err := models.CreateTask(&copy); err != nil {
			t.Fatalf("CreateTask(%s): %v", task.Content, err)
		}
	}
	queued, err := QueueTaskReminderDigests(now)
	if err != nil || queued != 1 {
		t.Fatalf("first queue = %d, %v; want 1, nil", queued, err)
	}
	queued, err = QueueTaskReminderDigests(now.Add(time.Minute))
	if err != nil || queued != 0 {
		t.Fatalf("second queue = %d, %v; want 0, nil", queued, err)
	}
	mail, err := models.ClaimNextMail(now.Add(2 * time.Minute))
	if err != nil || mail == nil {
		t.Fatalf("ClaimNextMail: %#v, %v", mail, err)
	}
	for _, expected := range []string{"今日到期 1 项", "即将到期 2 项", "逾期 1 项"} {
		if !strings.Contains(mail.Subject, expected) {
			t.Errorf("subject %q missing %q", mail.Subject, expected)
		}
	}
	if !strings.Contains(mail.HTMLBody, "https://books.example.com/notes?tab=tasks") {
		t.Errorf("HTML body missing public todo link")
	}
	pref, err := models.GetTaskReminderPreference(member.MemberID)
	if err != nil || pref.LastProcessedDate != "2026-07-14" {
		t.Fatalf("last processed = %q, %v", pref.LastProcessedDate, err)
	}
}

func TestQueueTaskReminderDigestsDisabledByDefault(t *testing.T) {
	setupReminderTestDB(t)
	queued, err := QueueTaskReminderDigests(time.Now())
	if err != nil || queued != 0 {
		t.Fatalf("queue with default settings = %d, %v", queued, err)
	}
	summary, err := models.GetMailStatusSummary()
	if err != nil || summary.Pending != 0 || summary.Sent != 0 || summary.Failed != 0 {
		t.Fatalf("unexpected outbox summary: %#v, %v", summary, err)
	}
}

func TestBuildMIMEMessageContainsAlternativeBodies(t *testing.T) {
	cfg := models.MailSettings{FromName: "BookStark", FromAddress: "notify@example.com"}
	raw := string(buildMIMEMessage(cfg, "user@example.com", MailMessage{
		Subject: "测试提醒", TextBody: "plain", HTMLBody: "<b>html</b>",
	}))
	for _, expected := range []string{"multipart/alternative", "text/plain", "text/html", "plain", "<b>html</b>"} {
		if !strings.Contains(raw, expected) {
			t.Errorf("MIME output missing %q", expected)
		}
	}
}
