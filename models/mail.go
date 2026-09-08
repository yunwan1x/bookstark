package models

import (
	"database/sql"
	"errors"
	"time"
)

const (
	MailStatusPending = "pending"
	MailStatusSending = "sending"
	MailStatusSent    = "sent"
	MailStatusFailed  = "failed"
)

type MailOutbox struct {
	MailID        int64      `json:"mail_id"`
	Kind          string     `json:"kind"`
	MemberID      int64      `json:"member_id"`
	ToEmail       string     `json:"to_email"`
	Subject       string     `json:"subject"`
	TextBody      string     `json:"text_body"`
	HTMLBody      string     `json:"html_body"`
	DedupeKey     string     `json:"dedupe_key"`
	Status        string     `json:"status"`
	Attempts      int        `json:"attempts"`
	NextAttemptAt time.Time  `json:"next_attempt_at"`
	SentAt        *time.Time `json:"sent_at,omitempty"`
	LastError     string     `json:"last_error"`
	CreateTime    time.Time  `json:"create_time"`
	ModifyTime    time.Time  `json:"modify_time"`
}

type MailStatusSummary struct {
	Pending   int64      `json:"pending"`
	Failed    int64      `json:"failed"`
	Sent      int64      `json:"sent"`
	LastSent  *time.Time `json:"last_sent,omitempty"`
	LastError string     `json:"last_error"`
}

// CreateMailOutbox queues a message once. The dedupe key makes scheduler
// retries and multiple application instances safe.
func CreateMailOutbox(mail *MailOutbox) (bool, error) {
	now := time.Now()
	if mail.NextAttemptAt.IsZero() {
		mail.NextAttemptAt = now
	}
	result, err := DB.Exec(`
		INSERT OR IGNORE INTO md_mail_outbox
		(kind, member_id, to_email, subject, text_body, html_body, dedupe_key,
		 status, attempts, next_attempt_at, sent_at, last_error, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, NULL, '', ?, ?)`,
		mail.Kind, mail.MemberID, mail.ToEmail, mail.Subject, mail.TextBody,
		mail.HTMLBody, mail.DedupeKey, MailStatusPending, mail.NextAttemptAt, now, now)
	if err != nil {
		return false, err
	}
	affected, err := result.RowsAffected()
	return affected > 0, err
}

func RecoverStaleSendingMail(before time.Time) error {
	_, err := DB.Exec(`
		UPDATE md_mail_outbox
		SET status = ?, next_attempt_at = ?, last_error = '发送进程中断，已重新排队', modify_time = ?
		WHERE status = ? AND modify_time < ?`,
		MailStatusPending, time.Now(), time.Now(), MailStatusSending, before)
	return err
}

func ClaimNextMail(now time.Time) (*MailOutbox, error) {
	tx, err := DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	mail := &MailOutbox{}
	var sentAt sql.NullTime
	err = tx.QueryRow(`
		SELECT mail_id, kind, member_id, to_email, subject, text_body, html_body,
		       dedupe_key, status, attempts, next_attempt_at, sent_at, last_error,
		       create_time, modify_time
		FROM md_mail_outbox
		WHERE status = ? AND next_attempt_at <= ?
		ORDER BY next_attempt_at, mail_id
		LIMIT 1`, MailStatusPending, now).Scan(
		&mail.MailID, &mail.Kind, &mail.MemberID, &mail.ToEmail, &mail.Subject,
		&mail.TextBody, &mail.HTMLBody, &mail.DedupeKey, &mail.Status, &mail.Attempts,
		&mail.NextAttemptAt, &sentAt, &mail.LastError, &mail.CreateTime, &mail.ModifyTime)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	result, err := tx.Exec(`
		UPDATE md_mail_outbox SET status = ?, modify_time = ?
		WHERE mail_id = ? AND status = ?`, MailStatusSending, now, mail.MailID, MailStatusPending)
	if err != nil {
		return nil, err
	}
	affected, err := result.RowsAffected()
	if err != nil || affected != 1 {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	mail.Status = MailStatusSending
	if sentAt.Valid {
		mail.SentAt = &sentAt.Time
	}
	return mail, nil
}

func MarkMailSent(mailID int64, sentAt time.Time) error {
	_, err := DB.Exec(`
		UPDATE md_mail_outbox
		SET status = ?, sent_at = ?, last_error = '', modify_time = ?
		WHERE mail_id = ?`, MailStatusSent, sentAt, sentAt, mailID)
	return err
}

func MarkMailDeliveryFailed(mailID int64, attempts int, nextAttempt time.Time, lastError string, terminal bool) error {
	status := MailStatusPending
	if terminal {
		status = MailStatusFailed
	}
	_, err := DB.Exec(`
		UPDATE md_mail_outbox
		SET status = ?, attempts = ?, next_attempt_at = ?, last_error = ?, modify_time = ?
		WHERE mail_id = ?`, status, attempts, nextAttempt, lastError, time.Now(), mailID)
	return err
}

func GetMailStatusSummary() (MailStatusSummary, error) {
	var summary MailStatusSummary
	err := DB.QueryRow(`
		SELECT
			COALESCE(SUM(CASE WHEN status IN ('pending','sending') THEN 1 ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END), 0)
		FROM md_mail_outbox`).Scan(&summary.Pending, &summary.Failed, &summary.Sent)
	if err != nil {
		return summary, err
	}
	var lastSent sql.NullTime
	_ = DB.QueryRow(`SELECT MAX(sent_at) FROM md_mail_outbox WHERE status = 'sent'`).Scan(&lastSent)
	if lastSent.Valid {
		summary.LastSent = &lastSent.Time
	}
	_ = DB.QueryRow(`
		SELECT last_error FROM md_mail_outbox
		WHERE last_error != '' ORDER BY modify_time DESC LIMIT 1`).Scan(&summary.LastError)
	return summary, nil
}
