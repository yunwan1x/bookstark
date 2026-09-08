package models

import (
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

const (
	TopicResourceDocument = "document"
	TopicResourceNote     = "note"
	TopicResourceArticle  = "article"
	TopicResourceBookmark = "bookmark"
	TopicResourceTask     = "task"

	TopicSummaryManual = "manual"
	TopicSummaryAI     = "ai"
)

var ErrTopicResourceDuplicate = errors.New("topic resource already exists")

type Topic struct {
	TopicID    int64     `json:"topic_id"`
	Title      string    `json:"title"`
	Question   string    `json:"question"`
	MemberID   int64     `json:"member_id"`
	IsPinned   bool      `json:"is_pinned"`
	CreateTime time.Time `json:"create_time"`
	ModifyTime time.Time `json:"modify_time"`
}

type TopicSummary struct {
	SummaryID    int64     `json:"summary_id"`
	TopicID      int64     `json:"topic_id"`
	Content      string    `json:"content"`
	SummaryType  string    `json:"summary_type"`
	OrderSort    int       `json:"order_sort"`
	CommentCount int       `json:"comment_count"`
	CreateTime   time.Time `json:"create_time"`
	ModifyTime   time.Time `json:"modify_time"`
}

type TopicResource struct {
	TopicResourceID int64     `json:"topic_resource_id"`
	TopicID         int64     `json:"topic_id"`
	ResourceType    string    `json:"resource_type"`
	TargetID        int64     `json:"target_id"`
	TitleSnapshot   string    `json:"title_snapshot"`
	DescSnapshot    string    `json:"desc_snapshot"`
	OrderSort       int       `json:"order_sort"`
	CommentCount    int       `json:"comment_count"`
	ResourceMissing bool      `json:"resource_missing"`
	OpenURL         string    `json:"open_url,omitempty"`
	CreateTime      time.Time `json:"create_time"`
}

type TopicListItem struct {
	Topic
	ResourceCount int `json:"resource_count"`
	SummaryCount  int `json:"summary_count"`
	TaskCount     int `json:"task_count"`
}

type TopicStats struct {
	ResourceCount int `json:"resource_count"`
	SummaryCount  int `json:"summary_count"`
	TaskCount     int `json:"task_count"`
	CommentCount  int `json:"comment_count"`
}

type TopicDetail struct {
	Topic     *Topic          `json:"topic"`
	Summaries []TopicSummary  `json:"summaries"`
	Resources []TopicResource `json:"resources"`
	Tasks     []Task          `json:"tasks"`
	Stats     TopicStats      `json:"stats"`
}

type TopicFilter struct {
	Keyword  string
	Date     string
	Page     int
	PageSize int
}

type TopicDailyCount struct {
	Date          string `json:"date"`
	Count         int    `json:"count"`
	TopicCount    int    `json:"topic_count"`
	SummaryCount  int    `json:"summary_count"`
	ResourceCount int    `json:"resource_count"`
	TaskCount     int    `json:"task_count"`
}

func ValidTopicResourceType(resourceType string) bool {
	switch resourceType {
	case TopicResourceDocument, TopicResourceNote, TopicResourceArticle, TopicResourceBookmark, TopicResourceTask:
		return true
	default:
		return false
	}
}

func NormalizeTopicSummaryType(summaryType string) string {
	summaryType = strings.ToLower(strings.TrimSpace(summaryType))
	if summaryType == "" {
		return TopicSummaryManual
	}
	return summaryType
}

func ValidTopicSummaryType(summaryType string) bool {
	switch NormalizeTopicSummaryType(summaryType) {
	case TopicSummaryManual, TopicSummaryAI:
		return true
	default:
		return false
	}
}

func CreateTopic(t *Topic) error {
	return createTopicTx(DB, t)
}

func createTopicTx(exec dbTx, t *Topic) error {
	now := time.Now()
	t.Title = strings.TrimSpace(t.Title)
	t.Question = strings.TrimSpace(t.Question)
	t.CreateTime = now
	t.ModifyTime = now
	res, err := exec.Exec(`
		INSERT INTO md_topics (title, question, member_id, is_pinned, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?)`,
		t.Title, t.Question, t.MemberID, boolToInt(t.IsPinned), t.CreateTime, t.ModifyTime)
	if err != nil {
		return err
	}
	t.TopicID, _ = res.LastInsertId()
	return nil
}

func GetTopicByID(id int64) (*Topic, error) {
	var t Topic
	var pinned int
	err := DB.QueryRow(`
		SELECT topic_id, title, question, member_id, is_pinned, create_time, modify_time
		FROM md_topics WHERE topic_id = ?`, id).
		Scan(&t.TopicID, &t.Title, &t.Question, &t.MemberID, &pinned, &t.CreateTime, &t.ModifyTime)
	if err != nil {
		return nil, err
	}
	t.IsPinned = pinned == 1
	return &t, nil
}

func UpdateTopic(t *Topic) error {
	t.Title = strings.TrimSpace(t.Title)
	t.Question = strings.TrimSpace(t.Question)
	t.ModifyTime = time.Now()
	res, err := DB.Exec(`
		UPDATE md_topics
		SET title = ?, question = ?, is_pinned = ?, modify_time = ?
		WHERE topic_id = ? AND member_id = ?`,
		t.Title, t.Question, boolToInt(t.IsPinned), t.ModifyTime, t.TopicID, t.MemberID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func ListTopics(memberID int64, f TopicFilter) ([]TopicListItem, int64, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.PageSize < 1 {
		f.PageSize = 20
	}
	if f.PageSize > 100 {
		f.PageSize = 100
	}

	where := []string{"t.member_id = ?"}
	args := []interface{}{memberID}
	if f.Keyword != "" {
		kw := "%" + escapeLike(f.Keyword) + "%"
		where = append(where, `(t.title LIKE ? ESCAPE '\' OR t.question LIKE ? ESCAPE '\'
			OR EXISTS (SELECT 1 FROM md_topic_summaries ts WHERE ts.topic_id = t.topic_id AND ts.content LIKE ? ESCAPE '\')
			OR EXISTS (SELECT 1 FROM md_topic_resources tr WHERE tr.topic_id = t.topic_id AND (tr.title_snapshot LIKE ? ESCAPE '\' OR tr.desc_snapshot LIKE ? ESCAPE '\'))
			OR EXISTS (SELECT 1 FROM md_tasks task WHERE task.topic_id = t.topic_id AND task.member_id = t.member_id AND task.content LIKE ? ESCAPE '\'))`)
		args = append(args, kw, kw, kw, kw, kw, kw)
	}
	if f.Date != "" {
		where = append(where, `(substr(t.modify_time, 1, 10) = ?
			OR EXISTS (SELECT 1 FROM md_topic_summaries ts WHERE ts.topic_id = t.topic_id AND substr(ts.modify_time, 1, 10) = ?)
			OR EXISTS (SELECT 1 FROM md_topic_resources tr WHERE tr.topic_id = t.topic_id AND substr(tr.create_time, 1, 10) = ?)
			OR EXISTS (SELECT 1 FROM md_tasks task WHERE task.topic_id = t.topic_id AND task.member_id = t.member_id AND substr(task.modify_time, 1, 10) = ?))`)
		args = append(args, f.Date, f.Date, f.Date, f.Date)
	}

	whereSQL := "WHERE " + strings.Join(where, " AND ")
	var total int64
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_topics t "+whereSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
		SELECT t.topic_id, t.title, t.question, t.member_id, t.is_pinned, t.create_time, t.modify_time,
			(SELECT COUNT(*) FROM md_topic_resources tr WHERE tr.topic_id = t.topic_id) AS resource_count,
			(SELECT COUNT(*) FROM md_topic_summaries ts WHERE ts.topic_id = t.topic_id) AS summary_count,
			(SELECT COUNT(*) FROM md_tasks task WHERE task.topic_id = t.topic_id AND task.member_id = t.member_id) AS task_count
		FROM md_topics t ` + whereSQL + `
		ORDER BY t.is_pinned DESC, t.modify_time DESC, t.topic_id DESC
		LIMIT ? OFFSET ?`
	rows, err := DB.Query(query, append(args, f.PageSize, (f.Page-1)*f.PageSize)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	topics := []TopicListItem{}
	for rows.Next() {
		var item TopicListItem
		var pinned int
		if err := rows.Scan(&item.TopicID, &item.Title, &item.Question, &item.MemberID, &pinned, &item.CreateTime, &item.ModifyTime, &item.ResourceCount, &item.SummaryCount, &item.TaskCount); err != nil {
			return nil, 0, err
		}
		item.IsPinned = pinned == 1
		topics = append(topics, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return topics, total, nil
}

func GetTopicDetail(id, memberID int64) (*TopicDetail, error) {
	topic, err := GetTopicByID(id)
	if err != nil {
		return nil, err
	}
	if topic.MemberID != memberID {
		return nil, sql.ErrNoRows
	}
	summaries, err := ListTopicSummaries(id)
	if err != nil {
		return nil, err
	}
	resources, err := ListTopicResources(id)
	if err != nil {
		return nil, err
	}
	tasks, _, err := ListTasks(memberID, TaskFilter{TopicID: id, Page: 1, PageSize: 100})
	if err != nil {
		return nil, err
	}
	stats := TopicStats{ResourceCount: len(resources), SummaryCount: len(summaries), TaskCount: len(tasks)}
	detail := &TopicDetail{Topic: topic, Summaries: summaries, Resources: resources, Tasks: tasks, Stats: stats}
	if err := AttachTopicCommentCounts(detail); err != nil {
		return nil, err
	}
	return detail, nil
}

func CreateTopicSummary(summary *TopicSummary) error {
	summary.Content = strings.TrimSpace(summary.Content)
	summary.SummaryType = NormalizeTopicSummaryType(summary.SummaryType)
	if !ValidTopicSummaryType(summary.SummaryType) {
		return fmt.Errorf("不支持的小结类型")
	}
	now := time.Now()
	summary.CreateTime = now
	summary.ModifyTime = now
	res, err := DB.Exec(`
		INSERT INTO md_topic_summaries (topic_id, content, summary_type, order_sort, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?)`,
		summary.TopicID, summary.Content, summary.SummaryType, summary.OrderSort, summary.CreateTime, summary.ModifyTime)
	if err != nil {
		return err
	}
	summary.SummaryID, _ = res.LastInsertId()
	return touchTopic(summary.TopicID)
}

func ListTopicSummaries(topicID int64) ([]TopicSummary, error) {
	rows, err := DB.Query(`
		SELECT summary_id, topic_id, content, summary_type, order_sort, create_time, modify_time
		FROM md_topic_summaries
		WHERE topic_id = ?
		ORDER BY order_sort ASC, summary_id ASC`, topicID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []TopicSummary{}
	for rows.Next() {
		var item TopicSummary
		if err := rows.Scan(&item.SummaryID, &item.TopicID, &item.Content, &item.SummaryType, &item.OrderSort, &item.CreateTime, &item.ModifyTime); err != nil {
			return nil, err
		}
		item.SummaryType = NormalizeTopicSummaryType(item.SummaryType)
		items = append(items, item)
	}
	return items, rows.Err()
}

func UpdateTopicSummary(summary *TopicSummary) error {
	summary.Content = strings.TrimSpace(summary.Content)
	summary.SummaryType = NormalizeTopicSummaryType(summary.SummaryType)
	if !ValidTopicSummaryType(summary.SummaryType) {
		return fmt.Errorf("不支持的小结类型")
	}
	summary.ModifyTime = time.Now()
	res, err := DB.Exec(`
		UPDATE md_topic_summaries
		SET content = ?, summary_type = ?, order_sort = ?, modify_time = ?
		WHERE summary_id = ? AND topic_id = ?`,
		summary.Content, summary.SummaryType, summary.OrderSort, summary.ModifyTime, summary.SummaryID, summary.TopicID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return sql.ErrNoRows
	}
	return touchTopic(summary.TopicID)
}

func DeleteTopicSummary(summaryID, topicID int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := DeleteTopicCommentsForTargetTx(tx, topicID, TopicCommentSummary, summaryID); err != nil {
		return err
	}
	res, err := tx.Exec("DELETE FROM md_topic_summaries WHERE summary_id = ? AND topic_id = ?", summaryID, topicID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return sql.ErrNoRows
	}
	if _, err := tx.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ?", time.Now(), topicID); err != nil {
		return err
	}
	return tx.Commit()
}

func SortTopicSummaries(topicID int64, items []SortItem) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	now := time.Now()
	for _, item := range items {
		if _, err := tx.Exec("UPDATE md_topic_summaries SET order_sort = ?, modify_time = ? WHERE summary_id = ? AND topic_id = ?", item.OrderSort, now, item.ID, topicID); err != nil {
			return err
		}
	}
	if _, err := tx.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ?", now, topicID); err != nil {
		return err
	}
	return tx.Commit()
}

func CreateTopicResource(resource *TopicResource) error {
	resource.ResourceType = strings.TrimSpace(resource.ResourceType)
	if !ValidTopicResourceType(resource.ResourceType) {
		return fmt.Errorf("不支持的资料类型")
	}
	if resource.TargetID <= 0 {
		return fmt.Errorf("请选择有效资源")
	}
	resource.TitleSnapshot = strings.TrimSpace(resource.TitleSnapshot)
	resource.DescSnapshot = strings.TrimSpace(resource.DescSnapshot)
	var count int
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_topic_resources WHERE topic_id = ? AND resource_type = ? AND target_id = ?", resource.TopicID, resource.ResourceType, resource.TargetID).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return ErrTopicResourceDuplicate
	}
	now := time.Now()
	resource.CreateTime = now
	res, err := DB.Exec(`
		INSERT INTO md_topic_resources (topic_id, resource_type, target_id, title_snapshot, desc_snapshot, order_sort, create_time)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		resource.TopicID, resource.ResourceType, resource.TargetID, resource.TitleSnapshot, resource.DescSnapshot, resource.OrderSort, resource.CreateTime)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "constraint") {
			return ErrTopicResourceDuplicate
		}
		return err
	}
	resource.TopicResourceID, _ = res.LastInsertId()
	enrichTopicResource(resource)
	return touchTopic(resource.TopicID)
}

func ListTopicResources(topicID int64) ([]TopicResource, error) {
	rows, err := DB.Query(`
		SELECT topic_resource_id, topic_id, resource_type, target_id, title_snapshot, desc_snapshot, order_sort, create_time
		FROM md_topic_resources
		WHERE topic_id = ?
		ORDER BY order_sort ASC, topic_resource_id ASC`, topicID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []TopicResource{}
	for rows.Next() {
		var item TopicResource
		if err := rows.Scan(&item.TopicResourceID, &item.TopicID, &item.ResourceType, &item.TargetID, &item.TitleSnapshot, &item.DescSnapshot, &item.OrderSort, &item.CreateTime); err != nil {
			return nil, err
		}
		enrichTopicResource(&item)
		items = append(items, item)
	}
	return items, rows.Err()
}

func DeleteTopicResource(topicResourceID, topicID int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := DeleteTopicCommentsForTargetTx(tx, topicID, TopicCommentResource, topicResourceID); err != nil {
		return err
	}
	res, err := tx.Exec("DELETE FROM md_topic_resources WHERE topic_resource_id = ? AND topic_id = ?", topicResourceID, topicID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return sql.ErrNoRows
	}
	if _, err := tx.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ?", time.Now(), topicID); err != nil {
		return err
	}
	return tx.Commit()
}

func SortTopicResources(topicID int64, items []SortItem) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, item := range items {
		if _, err := tx.Exec("UPDATE md_topic_resources SET order_sort = ? WHERE topic_resource_id = ? AND topic_id = ?", item.OrderSort, item.ID, topicID); err != nil {
			return err
		}
	}
	if _, err := tx.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ?", time.Now(), topicID); err != nil {
		return err
	}
	return tx.Commit()
}

func DeleteTopic(id, memberID int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	snap, name, snapErr := SnapshotTopic(tx, id)
	if snapErr != nil {
		return snapErr
	}
	if snap.Topic.MemberID != memberID {
		return sql.ErrNoRows
	}
	if err := CreateTrash(tx, "topic", name, snap, memberID); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_topic_summaries WHERE topic_id = ?", id); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_topic_resources WHERE topic_id = ?", id); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_tasks WHERE topic_id = ? AND member_id = ?", id, memberID); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_topic_comments WHERE topic_id = ? AND member_id = ?", id, memberID); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'topic' AND target_id = ?", id); err != nil {
		return err
	}
	res, err := tx.Exec("DELETE FROM md_topics WHERE topic_id = ? AND member_id = ?", id, memberID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return sql.ErrNoRows
	}
	return tx.Commit()
}

func ToggleTopicPin(id, memberID int64, pinned bool) error {
	res, err := DB.Exec("UPDATE md_topics SET is_pinned = ?, modify_time = ? WHERE topic_id = ? AND member_id = ?", boolToInt(pinned), time.Now(), id, memberID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func GetTopicDailyCounts(memberID int64, year, month int) ([]TopicDailyCount, error) {
	startDate := fmt.Sprintf("%04d-%02d-01", year, month)
	endDate := fmt.Sprintf("%04d-%02d-31", year, month)
	rows, err := DB.Query(`
		WITH events AS (
			SELECT substr(t.modify_time, 1, 10) AS d, 1 AS topic_count, 0 AS summary_count, 0 AS resource_count, 0 AS task_count
			FROM md_topics t
			WHERE t.member_id = ? AND substr(t.modify_time, 1, 10) BETWEEN ? AND ?
			UNION ALL
			SELECT substr(ts.modify_time, 1, 10) AS d, 0, 1, 0, 0
			FROM md_topic_summaries ts JOIN md_topics t ON t.topic_id = ts.topic_id
			WHERE t.member_id = ? AND substr(ts.modify_time, 1, 10) BETWEEN ? AND ?
			UNION ALL
			SELECT substr(tr.create_time, 1, 10) AS d, 0, 0, 1, 0
			FROM md_topic_resources tr JOIN md_topics t ON t.topic_id = tr.topic_id
			WHERE t.member_id = ? AND substr(tr.create_time, 1, 10) BETWEEN ? AND ?
			UNION ALL
			SELECT substr(task.modify_time, 1, 10) AS d, 0, 0, 0, 1
			FROM md_tasks task
			WHERE task.member_id = ? AND task.topic_id > 0 AND substr(task.modify_time, 1, 10) BETWEEN ? AND ?
		)
		SELECT d,
			SUM(topic_count + summary_count + resource_count + task_count) AS cnt,
			SUM(topic_count), SUM(summary_count), SUM(resource_count), SUM(task_count)
		FROM events
		WHERE d IS NOT NULL AND d != ''
		GROUP BY d
		ORDER BY d`,
		memberID, startDate, endDate,
		memberID, startDate, endDate,
		memberID, startDate, endDate,
		memberID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []TopicDailyCount{}
	for rows.Next() {
		var r TopicDailyCount
		if err := rows.Scan(&r.Date, &r.Count, &r.TopicCount, &r.SummaryCount, &r.ResourceCount, &r.TaskCount); err != nil {
			return nil, err
		}
		result = append(result, r)
	}
	return result, rows.Err()
}

func touchTopic(topicID int64) error {
	_, err := DB.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ?", time.Now(), topicID)
	return err
}

func enrichTopicResource(item *TopicResource) {
	switch item.ResourceType {
	case TopicResourceDocument:
		var identify, bookIdentify, name string
		err := DB.QueryRow(`
			SELECT d.identify, b.identify, d.document_name
			FROM md_documents d JOIN md_books b ON b.book_id = d.book_id
			WHERE d.document_id = ?`, item.TargetID).Scan(&identify, &bookIdentify, &name)
		if err != nil {
			item.ResourceMissing = true
			return
		}
		if item.TitleSnapshot == "" {
			item.TitleSnapshot = name
		}
		item.OpenURL = "/books/" + bookIdentify + "/edit?doc=" + fmt.Sprint(item.TargetID)
	case TopicResourceNote, TopicResourceArticle:
		var identify, title string
		err := DB.QueryRow("SELECT blog_identify, blog_title FROM md_blogs WHERE blog_id = ?", item.TargetID).Scan(&identify, &title)
		if err != nil {
			item.ResourceMissing = true
			return
		}
		if item.TitleSnapshot == "" {
			item.TitleSnapshot = title
		}
		item.OpenURL = "/blogs/" + identify + "/edit"
	case TopicResourceBookmark:
		var title, url string
		err := DB.QueryRow("SELECT title, url FROM md_bookmark WHERE bookmark_id = ?", item.TargetID).Scan(&title, &url)
		if err != nil {
			item.ResourceMissing = true
			return
		}
		if item.TitleSnapshot == "" {
			item.TitleSnapshot = title
		}
		item.OpenURL = url
	case TopicResourceTask:
		var content string
		err := DB.QueryRow("SELECT content FROM md_tasks WHERE task_id = ?", item.TargetID).Scan(&content)
		if err != nil {
			item.ResourceMissing = true
			return
		}
		if item.TitleSnapshot == "" {
			item.TitleSnapshot = content
		}
		item.OpenURL = "/notes?tab=tasks"
	}
}
