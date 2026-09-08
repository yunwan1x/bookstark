package models

import (
	"database/sql"
	"errors"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	TopicCommentResource = "resource"
	TopicCommentSummary  = "summary"
	TopicCommentTask     = "task"
	TopicCommentMaxRunes = 20000
)

var (
	ErrTopicCommentInvalidContent   = errors.New("评论内容无效")
	ErrTopicCommentReplyUnsupported = errors.New("专题评论不支持回复")
)

type TopicComment struct {
	CommentID       int64     `json:"comment_id"`
	TopicID         int64     `json:"topic_id"`
	TargetType      string    `json:"target_type"`
	TargetID        int64     `json:"target_id"`
	MemberID        int64     `json:"member_id"`
	AuthorName      string    `json:"author_name"`
	ParentCommentID int64     `json:"parent_comment_id"`
	Content         string    `json:"content"`
	CreateTime      time.Time `json:"create_time"`
	ModifyTime      time.Time `json:"modify_time"`
}

type TopicCommentCount struct {
	TargetType string `json:"target_type"`
	TargetID   int64  `json:"target_id"`
	Count      int    `json:"count"`
}

func NormalizeTopicCommentTargetType(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func ValidTopicCommentTargetType(value string) bool {
	switch NormalizeTopicCommentTargetType(value) {
	case TopicCommentResource, TopicCommentSummary, TopicCommentTask:
		return true
	default:
		return false
	}
}

func ValidateTopicCommentTarget(exec dbTx, topicID, memberID int64, targetType string, targetID int64) error {
	targetType = NormalizeTopicCommentTargetType(targetType)
	if topicID <= 0 || targetID <= 0 || !ValidTopicCommentTargetType(targetType) {
		return sql.ErrNoRows
	}
	var count int
	var err error
	switch targetType {
	case TopicCommentResource:
		err = exec.QueryRow(`SELECT COUNT(*) FROM md_topic_resources r
			JOIN md_topics t ON t.topic_id = r.topic_id
			WHERE r.topic_resource_id = ? AND r.topic_id = ? AND t.member_id = ?`,
			targetID, topicID, memberID).Scan(&count)
	case TopicCommentSummary:
		err = exec.QueryRow(`SELECT COUNT(*) FROM md_topic_summaries s
			JOIN md_topics t ON t.topic_id = s.topic_id
			WHERE s.summary_id = ? AND s.topic_id = ? AND t.member_id = ?`,
			targetID, topicID, memberID).Scan(&count)
	case TopicCommentTask:
		err = exec.QueryRow(`SELECT COUNT(*) FROM md_tasks
			WHERE task_id = ? AND topic_id = ? AND member_id = ?`,
			targetID, topicID, memberID).Scan(&count)
	}
	if err != nil {
		return err
	}
	if count == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func ListTopicComments(topicID, memberID int64, targetType string, targetID int64, page, pageSize int) ([]TopicComment, int64, error) {
	topic, err := GetTopicByID(topicID)
	if err != nil || topic.MemberID != memberID {
		return nil, 0, sql.ErrNoRows
	}
	targetType = NormalizeTopicCommentTargetType(targetType)
	if targetType != "" {
		if err := ValidateTopicCommentTarget(DB, topicID, memberID, targetType, targetID); err != nil {
			return nil, 0, err
		}
	}
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 50
	}
	if pageSize > 200 {
		pageSize = 200
	}
	where := "c.topic_id = ?"
	args := []interface{}{topicID}
	if targetType != "" {
		where += " AND c.target_type = ? AND c.target_id = ?"
		args = append(args, targetType, targetID)
	}
	var total int64
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_topic_comments c WHERE "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := DB.Query(`
		SELECT c.comment_id, c.topic_id, c.target_type, c.target_id, c.member_id,
			COALESCE(m.account, ''), c.parent_comment_id, c.content, c.create_time, c.modify_time
		FROM md_topic_comments c
		LEFT JOIN md_members m ON m.member_id = c.member_id
		WHERE `+where+`
		ORDER BY c.create_time ASC, c.comment_id ASC
		LIMIT ? OFFSET ?`, append(args, pageSize, (page-1)*pageSize)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := []TopicComment{}
	for rows.Next() {
		var item TopicComment
		if err := rows.Scan(&item.CommentID, &item.TopicID, &item.TargetType, &item.TargetID,
			&item.MemberID, &item.AuthorName, &item.ParentCommentID, &item.Content,
			&item.CreateTime, &item.ModifyTime); err != nil {
			return nil, 0, err
		}
		// Legacy replies remain visible as regular top-level comments.
		item.ParentCommentID = 0
		items = append(items, item)
	}
	return items, total, rows.Err()
}

func CreateTopicComment(comment *TopicComment) error {
	comment.Content = strings.TrimSpace(comment.Content)
	comment.TargetType = NormalizeTopicCommentTargetType(comment.TargetType)
	if comment.Content == "" || utf8.RuneCountInString(comment.Content) > TopicCommentMaxRunes {
		return ErrTopicCommentInvalidContent
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := ValidateTopicCommentTarget(tx, comment.TopicID, comment.MemberID, comment.TargetType, comment.TargetID); err != nil {
		return err
	}
	if comment.ParentCommentID > 0 {
		return ErrTopicCommentReplyUnsupported
	}
	now := time.Now()
	comment.CreateTime = now
	comment.ModifyTime = now
	res, err := tx.Exec(`INSERT INTO md_topic_comments
			(topic_id, target_type, target_id, member_id, parent_comment_id, content, create_time, modify_time)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		comment.TopicID, comment.TargetType, comment.TargetID, comment.MemberID,
		comment.ParentCommentID, comment.Content, comment.CreateTime, comment.ModifyTime)
	if err != nil {
		return err
	}
	comment.CommentID, _ = res.LastInsertId()
	if _, err := tx.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ? AND member_id = ?", now, comment.TopicID, comment.MemberID); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	if member, err := GetMemberByID(comment.MemberID); err == nil {
		comment.AuthorName = member.Account
	}
	return nil
}

func UpdateTopicComment(commentID, topicID, memberID int64, content string) (*TopicComment, error) {
	content = strings.TrimSpace(content)
	if content == "" || utf8.RuneCountInString(content) > TopicCommentMaxRunes {
		return nil, ErrTopicCommentInvalidContent
	}
	tx, err := DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	now := time.Now()
	res, err := tx.Exec(`UPDATE md_topic_comments SET content = ?, modify_time = ?
			WHERE comment_id = ? AND topic_id = ? AND member_id = ?`,
		content, now, commentID, topicID, memberID)
	if err != nil {
		return nil, err
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		return nil, sql.ErrNoRows
	}
	if _, err := tx.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ? AND member_id = ?", now, topicID, memberID); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return GetTopicCommentByID(commentID, topicID, memberID)
}

func GetTopicCommentByID(commentID, topicID, memberID int64) (*TopicComment, error) {
	var item TopicComment
	err := DB.QueryRow(`
		SELECT c.comment_id, c.topic_id, c.target_type, c.target_id, c.member_id,
			COALESCE(m.account, ''), c.parent_comment_id, c.content, c.create_time, c.modify_time
		FROM md_topic_comments c
		LEFT JOIN md_members m ON m.member_id = c.member_id
		WHERE c.comment_id = ? AND c.topic_id = ? AND c.member_id = ?`,
		commentID, topicID, memberID).
		Scan(&item.CommentID, &item.TopicID, &item.TargetType, &item.TargetID,
			&item.MemberID, &item.AuthorName, &item.ParentCommentID, &item.Content,
			&item.CreateTime, &item.ModifyTime)
	if err != nil {
		return nil, err
	}
	return &item, nil
}

func DeleteTopicComment(commentID, topicID, memberID int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var exists int
	if err := tx.QueryRow(`SELECT 1 FROM md_topic_comments
			WHERE comment_id = ? AND topic_id = ? AND member_id = ?`,
		commentID, topicID, memberID).Scan(&exists); err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE md_topic_comments SET parent_comment_id = 0
		WHERE parent_comment_id = ? AND topic_id = ? AND member_id = ?`,
		commentID, topicID, memberID); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM md_topic_comments
		WHERE comment_id = ? AND topic_id = ? AND member_id = ?`,
		commentID, topicID, memberID); err != nil {
		return err
	}
	if _, err := tx.Exec("UPDATE md_topics SET modify_time = ? WHERE topic_id = ? AND member_id = ?", time.Now(), topicID, memberID); err != nil {
		return err
	}
	return tx.Commit()
}

func ListTopicCommentCounts(topicID int64) ([]TopicCommentCount, error) {
	rows, err := DB.Query(`SELECT target_type, target_id, COUNT(*)
		FROM md_topic_comments WHERE topic_id = ?
		GROUP BY target_type, target_id`, topicID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []TopicCommentCount{}
	for rows.Next() {
		var item TopicCommentCount
		if err := rows.Scan(&item.TargetType, &item.TargetID, &item.Count); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func AttachTopicCommentCounts(detail *TopicDetail) error {
	if detail == nil || detail.Topic == nil {
		return nil
	}
	counts, err := ListTopicCommentCounts(detail.Topic.TopicID)
	if err != nil {
		return err
	}
	resourceCounts := map[int64]int{}
	summaryCounts := map[int64]int{}
	taskCounts := map[int64]int{}
	for _, count := range counts {
		detail.Stats.CommentCount += count.Count
		switch count.TargetType {
		case TopicCommentResource:
			resourceCounts[count.TargetID] = count.Count
		case TopicCommentSummary:
			summaryCounts[count.TargetID] = count.Count
		case TopicCommentTask:
			taskCounts[count.TargetID] = count.Count
		}
	}
	for i := range detail.Resources {
		detail.Resources[i].CommentCount = resourceCounts[detail.Resources[i].TopicResourceID]
	}
	for i := range detail.Summaries {
		detail.Summaries[i].CommentCount = summaryCounts[detail.Summaries[i].SummaryID]
	}
	for i := range detail.Tasks {
		detail.Tasks[i].CommentCount = taskCounts[detail.Tasks[i].TaskID]
	}
	return nil
}

func DeleteTopicCommentsForTargetTx(exec dbTx, topicID int64, targetType string, targetID int64) error {
	_, err := exec.Exec(`DELETE FROM md_topic_comments
		WHERE topic_id = ? AND target_type = ? AND target_id = ?`,
		topicID, NormalizeTopicCommentTargetType(targetType), targetID)
	return err
}
