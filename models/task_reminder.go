package models

import (
	"database/sql"
	"errors"
	"time"
)

type TaskReminderPreference struct {
	MemberID          int64     `json:"member_id"`
	Enabled           bool      `json:"enabled"`
	SendTime          string    `json:"send_time"`
	RemindBeforeDays  int       `json:"remind_before_days"`
	IncludeOverdue    bool      `json:"include_overdue"`
	LastProcessedDate string    `json:"last_processed_date"`
	Email             string    `json:"email,omitempty"`
	UpdateTime        time.Time `json:"update_time"`
}

type TaskReminderItem struct {
	TaskID    int64  `json:"task_id"`
	Content   string `json:"content"`
	DueDate   string `json:"due_date"`
	ParentID  int64  `json:"parent_id"`
	TopicID   int64  `json:"topic_id"`
	TopicName string `json:"topic_name"`
}

func DefaultTaskReminderPreference(memberID int64) TaskReminderPreference {
	return TaskReminderPreference{
		MemberID: memberID,
		SendTime: "09:00",
	}
}

func GetTaskReminderPreference(memberID int64) (TaskReminderPreference, error) {
	pref := DefaultTaskReminderPreference(memberID)
	var enabled, overdue int
	err := DB.QueryRow(`
		SELECT enabled, send_time, remind_before_days, include_overdue,
		       last_processed_date, update_time
		FROM md_task_reminder_preferences WHERE member_id = ?`, memberID).Scan(
		&enabled, &pref.SendTime, &pref.RemindBeforeDays, &overdue,
		&pref.LastProcessedDate, &pref.UpdateTime)
	if errors.Is(err, sql.ErrNoRows) {
		member, memberErr := GetMemberByID(memberID)
		if memberErr != nil {
			return pref, memberErr
		}
		pref.Email = member.Email
		return pref, nil
	}
	if err != nil {
		return pref, err
	}
	pref.Enabled = enabled == 1
	pref.IncludeOverdue = overdue == 1
	member, err := GetMemberByID(memberID)
	if err == nil {
		pref.Email = member.Email
	}
	return pref, nil
}

func UpsertTaskReminderPreference(pref TaskReminderPreference) error {
	now := time.Now()
	_, err := DB.Exec(`
		INSERT INTO md_task_reminder_preferences
		(member_id, enabled, send_time, remind_before_days, include_overdue,
		 last_processed_date, update_time)
		VALUES (?, ?, ?, ?, ?, '', ?)
		ON CONFLICT(member_id) DO UPDATE SET
			enabled = excluded.enabled,
			send_time = excluded.send_time,
			remind_before_days = excluded.remind_before_days,
			include_overdue = excluded.include_overdue,
			update_time = excluded.update_time`,
		pref.MemberID, boolToInt(pref.Enabled), pref.SendTime, pref.RemindBeforeDays,
		boolToInt(pref.IncludeOverdue), now)
	return err
}

func ListReadyTaskReminderPreferences(today, currentTime string) ([]TaskReminderPreference, error) {
	rows, err := DB.Query(`
		SELECT p.member_id, p.enabled, p.send_time, p.remind_before_days,
		       p.include_overdue, p.last_processed_date, p.update_time, m.email
		FROM md_task_reminder_preferences p
		JOIN md_members m ON m.member_id = p.member_id
		WHERE p.enabled = 1 AND m.status = 1 AND m.email != ''
		  AND p.send_time <= ? AND p.last_processed_date != ?
		ORDER BY p.member_id`, currentTime, today)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []TaskReminderPreference
	for rows.Next() {
		var pref TaskReminderPreference
		var enabled, overdue int
		if err := rows.Scan(&pref.MemberID, &enabled, &pref.SendTime,
			&pref.RemindBeforeDays, &overdue, &pref.LastProcessedDate,
			&pref.UpdateTime, &pref.Email); err != nil {
			return nil, err
		}
		pref.Enabled = enabled == 1
		pref.IncludeOverdue = overdue == 1
		result = append(result, pref)
	}
	return result, rows.Err()
}

func ListTaskReminderItems(memberID int64, today string, remindBeforeDays int, includeOverdue bool) ([]TaskReminderItem, error) {
	todayTime, err := time.Parse("2006-01-02", today)
	if err != nil {
		return nil, err
	}
	upcoming := todayTime.AddDate(0, 0, remindBeforeDays).Format("2006-01-02")
	query := `
		SELECT task.task_id, task.content, task.due_date, task.parent_id,
		       task.topic_id, COALESCE(topic.title, '')
		FROM md_tasks task
		LEFT JOIN md_topics topic ON topic.topic_id = task.topic_id
		WHERE task.member_id = ? AND task.done = 0 AND task.due_date != ''
		  AND (`
	args := []interface{}{memberID}
	if remindBeforeDays > 0 {
		query += `task.due_date >= ? AND task.due_date <= ?`
		args = append(args, today, upcoming)
	} else {
		query += `task.due_date = ?`
		args = append(args, today)
	}
	if includeOverdue {
		query += ` OR task.due_date < ?`
		args = append(args, today)
	}
	query += `) ORDER BY task.due_date, task.task_id`
	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []TaskReminderItem
	for rows.Next() {
		var item TaskReminderItem
		if err := rows.Scan(&item.TaskID, &item.Content, &item.DueDate,
			&item.ParentID, &item.TopicID, &item.TopicName); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func MarkTaskReminderProcessed(memberID int64, date string) error {
	_, err := DB.Exec(`
		UPDATE md_task_reminder_preferences
		SET last_processed_date = ?, update_time = ?
		WHERE member_id = ?`, date, time.Now(), memberID)
	return err
}
