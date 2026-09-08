package services

import (
	"context"
	"fmt"
	"html"
	"log"
	"sort"
	"strings"
	"sync"
	"time"

	"bookstark/models"
)

const maxMailAttempts = 3

type NotificationService struct {
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

func StartNotificationService() *NotificationService {
	ctx, cancel := context.WithCancel(context.Background())
	service := &NotificationService{cancel: cancel}
	service.wg.Add(2)
	go service.reminderLoop(ctx)
	go service.outboxLoop(ctx)
	return service
}

func (s *NotificationService) Stop() {
	if s == nil || s.cancel == nil {
		return
	}
	s.cancel()
	s.wg.Wait()
}

func (s *NotificationService) reminderLoop(ctx context.Context) {
	defer s.wg.Done()
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		if _, err := QueueTaskReminderDigests(time.Now()); err != nil {
			log.Printf("task reminder scan: %v", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (s *NotificationService) outboxLoop(ctx context.Context) {
	defer s.wg.Done()
	_ = models.RecoverStaleSendingMail(time.Now().Add(-10 * time.Minute))
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	for {
		if err := DeliverNextQueuedMail(ctx, time.Now()); err != nil {
			log.Printf("mail outbox delivery: %v", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func QueueTaskReminderDigests(now time.Time) (int, error) {
	cfg := models.GetMailSettings()
	if !cfg.Ready() || !cfg.TaskReminderEnabled {
		return 0, nil
	}
	today := now.Format("2006-01-02")
	prefs, err := models.ListReadyTaskReminderPreferences(today, now.Format("15:04"))
	if err != nil {
		return 0, err
	}
	queued := 0
	for _, pref := range prefs {
		items, err := models.ListTaskReminderItems(pref.MemberID, today, pref.RemindBeforeDays, pref.IncludeOverdue)
		if err != nil {
			return queued, err
		}
		if len(items) > 0 {
			message := BuildTaskReminderDigest(pref, items, now, cfg.PublicURL)
			created, err := models.CreateMailOutbox(&models.MailOutbox{
				Kind:          "task_digest",
				MemberID:      pref.MemberID,
				ToEmail:       pref.Email,
				Subject:       message.Subject,
				TextBody:      message.TextBody,
				HTMLBody:      message.HTMLBody,
				DedupeKey:     fmt.Sprintf("task_digest:%d:%s:%s", pref.MemberID, today, pref.SendTime),
				NextAttemptAt: now,
			})
			if err != nil {
				return queued, err
			}
			if created {
				queued++
			}
		}
		if err := models.MarkTaskReminderProcessed(pref.MemberID, today); err != nil {
			return queued, err
		}
	}
	return queued, nil
}

func DeliverNextQueuedMail(ctx context.Context, now time.Time) error {
	cfg := models.GetMailSettings()
	if !cfg.Ready() {
		return nil
	}
	mail, err := models.ClaimNextMail(now)
	if err != nil || mail == nil {
		return err
	}
	err = SendMail(ctx, cfg, MailMessage{
		To: mail.ToEmail, Subject: mail.Subject, TextBody: mail.TextBody, HTMLBody: mail.HTMLBody,
	})
	if err == nil {
		return models.MarkMailSent(mail.MailID, time.Now())
	}
	attempts := mail.Attempts + 1
	delays := []time.Duration{time.Minute, 5 * time.Minute, 30 * time.Minute}
	delay := delays[min(attempts-1, len(delays)-1)]
	markErr := models.MarkMailDeliveryFailed(mail.MailID, attempts, time.Now().Add(delay), truncateError(err), attempts >= maxMailAttempts)
	if markErr != nil {
		return fmt.Errorf("%v; update outbox: %w", err, markErr)
	}
	return err
}

func BuildTaskReminderDigest(pref models.TaskReminderPreference, items []models.TaskReminderItem, now time.Time, publicURL string) MailMessage {
	today := now.Format("2006-01-02")
	groups := map[string][]models.TaskReminderItem{"overdue": {}, "today": {}, "upcoming": {}}
	for _, item := range items {
		switch {
		case item.DueDate < today:
			groups["overdue"] = append(groups["overdue"], item)
		case item.DueDate == today:
			groups["today"] = append(groups["today"], item)
		default:
			groups["upcoming"] = append(groups["upcoming"], item)
		}
	}
	subjectParts := make([]string, 0, 3)
	if n := len(groups["today"]); n > 0 {
		subjectParts = append(subjectParts, fmt.Sprintf("今日到期 %d 项", n))
	}
	if n := len(groups["upcoming"]); n > 0 {
		subjectParts = append(subjectParts, fmt.Sprintf("即将到期 %d 项", n))
	}
	if n := len(groups["overdue"]); n > 0 {
		subjectParts = append(subjectParts, fmt.Sprintf("逾期 %d 项", n))
	}
	subject := "[BookStark] " + strings.Join(subjectParts, " · ")
	link := strings.TrimRight(publicURL, "/") + "/notes?tab=tasks"
	if publicURL == "" {
		link = "/notes?tab=tasks"
	}

	var textBody strings.Builder
	textBody.WriteString("BookStark 待办提醒\n\n")
	var htmlBody strings.Builder
	htmlBody.WriteString(`<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:640px;margin:auto;color:#172033"><h2 style="margin:0 0 20px">BookStark 待办提醒</h2>`)
	for _, group := range []struct{ key, label, color string }{
		{"overdue", "已逾期", "#dc2626"},
		{"today", "今日到期", "#2563eb"},
		{"upcoming", "即将到期", "#7c3aed"},
	} {
		groupItems := groups[group.key]
		if len(groupItems) == 0 {
			continue
		}
		textBody.WriteString(fmt.Sprintf("%s %d 项\n", group.label, len(groupItems)))
		htmlBody.WriteString(fmt.Sprintf(`<h3 style="font-size:15px;color:%s;margin:22px 0 8px">%s %d 项</h3><div style="border:1px solid #e5e7eb;border-radius:8px;overflow:hidden">`, group.color, group.label, len(groupItems)))
		for i, item := range groupItems {
			context := ""
			if item.TopicName != "" {
				context = " · 专题：" + item.TopicName
			}
			textBody.WriteString(fmt.Sprintf("%d. %s · %s%s\n", i+1, item.Content, item.DueDate, context))
			border := "border-top:1px solid #eef0f3;"
			if i == 0 {
				border = ""
			}
			htmlBody.WriteString(fmt.Sprintf(`<div style="padding:11px 14px;%s"><div style="font-size:14px;font-weight:600">%s</div><div style="font-size:12px;color:#6b7280;margin-top:4px">%s%s</div></div>`, border, html.EscapeString(item.Content), html.EscapeString(item.DueDate), html.EscapeString(context)))
		}
		textBody.WriteString("\n")
		htmlBody.WriteString(`</div>`)
	}
	textBody.WriteString("打开待办：" + link + "\n")
	htmlBody.WriteString(fmt.Sprintf(`<p style="margin:24px 0 0"><a href="%s" style="display:inline-block;background:#2563eb;color:#fff;text-decoration:none;padding:10px 16px;border-radius:6px;font-size:14px">打开 BookStark 待办</a></p><p style="font-size:11px;color:#9ca3af;margin-top:22px">你可以在 BookStark 个人设置中调整或关闭邮件提醒。</p></div>`, html.EscapeString(link)))
	return MailMessage{To: pref.Email, Subject: subject, TextBody: textBody.String(), HTMLBody: htmlBody.String()}
}

func truncateError(err error) string {
	if err == nil {
		return ""
	}
	value := err.Error()
	if len(value) > 1000 {
		value = value[:1000]
	}
	return value
}

func SortedReminderItems(items []models.TaskReminderItem) []models.TaskReminderItem {
	result := append([]models.TaskReminderItem(nil), items...)
	sort.SliceStable(result, func(i, j int) bool {
		if result[i].DueDate == result[j].DueDate {
			return result[i].TaskID < result[j].TaskID
		}
		return result[i].DueDate < result[j].DueDate
	})
	return result
}
