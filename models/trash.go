package models

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"
)

// Trash 回收站记录
type Trash struct {
	TrashID      int64     `json:"trash_id"`
	ResourceType string    `json:"resource_type"`
	ResourceName string    `json:"resource_name"`
	Snapshot     string    `json:"snapshot"`
	MemberID     int64     `json:"member_id"`
	DeleteTime   time.Time `json:"delete_time"`
}

// TrashItem 回收站列表项（不含 snapshot 大字段）
type TrashItem struct {
	TrashID      int64     `json:"trash_id"`
	ResourceType string    `json:"resource_type"`
	ResourceName string    `json:"resource_name"`
	MemberID     int64     `json:"member_id"`
	DeleteTime   time.Time `json:"delete_time"`
	ResourceURL  string    `json:"resource_url,omitempty"` // 书签时存储 URL
}

// TrashSnapshot 通用快照结构
type TrashSnapshot struct {
	Book           *BookSnap           `json:"book,omitempty"`
	Blog           *BlogSnap           `json:"blog,omitempty"`
	Bookmark       *BookmarkSnap       `json:"bookmark,omitempty"`
	Document       *DocumentSnap       `json:"document,omitempty"`
	Task           *TaskSnap           `json:"task,omitempty"`
	Topic          *TopicSnap          `json:"topic,omitempty"`
	Tasks          []TaskSnap          `json:"tasks,omitempty"`
	TopicSummaries []TopicSummarySnap  `json:"topic_summaries,omitempty"`
	TopicResources []TopicResourceSnap `json:"topic_resources,omitempty"`
	TopicComments  []TopicCommentSnap  `json:"topic_comments,omitempty"`
	Documents      []DocumentSnap      `json:"documents,omitempty"`
	Shares         []ShareSnap         `json:"shares,omitempty"`
	LabelRelations []LabelRelationSnap `json:"label_relations,omitempty"`
}

type BookSnap struct {
	BookID             int64      `json:"book_id"`
	BookName           string     `json:"book_name"`
	ItemID             int        `json:"item_id"`
	Identify           string     `json:"identify"`
	OrderIndex         int        `json:"order_index"`
	Description        string     `json:"description"`
	Label              string     `json:"label"`
	DocCount           int        `json:"doc_count"`
	MemberID           int64      `json:"member_id"`
	CreateTime         time.Time  `json:"create_time"`
	ModifyTime         *time.Time `json:"modify_time"`
	IsUseFirstDocument int        `json:"is_use_first_document"`
}

type BlogSnap struct {
	BlogID       int64     `json:"blog_id"`
	BlogTitle    string    `json:"blog_title"`
	BlogIdentify string    `json:"blog_identify"`
	MemberID     int64     `json:"member_id"`
	BlogContent  string    `json:"blog_content"`
	BlogDesc     string    `json:"blog_desc,omitempty"`
	Password     string    `json:"password"`
	ModifyTime   time.Time `json:"modify_time"`
	ModifyAt     int64     `json:"modify_at"`
	CreateTime   time.Time `json:"create_time"`
	Version      int       `json:"version"`
	BlogType     string    `json:"blog_type"`
	Visibility   int       `json:"visibility"`
	IsPinned     int       `json:"is_pinned"`
	PinOrder     int       `json:"pin_order"`
}

type BookmarkSnap struct {
	BookmarkID  int64     `json:"bookmark_id"`
	Title       string    `json:"title"`
	URL         string    `json:"url"`
	Description string    `json:"description"`
	Favicon     string    `json:"favicon"`
	OrderSort   int       `json:"order_sort"`
	Label       string    `json:"label"`
	MemberID    int64     `json:"member_id"`
	IsPublic    bool      `json:"is_public"`
	IsPinned    bool      `json:"is_pinned"`
	NavVisible  bool      `json:"nav_visible"`
	CreateTime  time.Time `json:"create_time"`
	ModifyTime  time.Time `json:"modify_time"`
}

type DocumentSnap struct {
	DocumentID   int64      `json:"document_id"`
	DocumentName string     `json:"document_name"`
	Identify     string     `json:"identify"`
	BookID       int64      `json:"book_id"`
	ParentID     int64      `json:"parent_id"`
	OrderSort    int        `json:"order_sort"`
	Markdown     string     `json:"markdown"`
	DocType      string     `json:"doc_type"`
	MemberID     int64      `json:"member_id"`
	CreateTime   time.Time  `json:"create_time"`
	ModifyTime   *time.Time `json:"modify_time"`
	ModifyAt     int64      `json:"modify_at"`
	IsOpen       int        `json:"is_open"`
	ViewCount    int        `json:"view_count"`
}

type TaskSnap struct {
	TaskID       int64      `json:"task_id"`
	Content      string     `json:"content"`
	DueDate      string     `json:"due_date"`
	Done         bool       `json:"done"`
	ParentID     int64      `json:"parent_id"`
	TopicID      int64      `json:"topic_id"`
	MemberID     int64      `json:"member_id"`
	CompleteTime *time.Time `json:"complete_time"`
	CreateTime   time.Time  `json:"create_time"`
	ModifyTime   time.Time  `json:"modify_time"`
}

type TopicSnap struct {
	TopicID    int64     `json:"topic_id"`
	Title      string    `json:"title"`
	Question   string    `json:"question"`
	MemberID   int64     `json:"member_id"`
	IsPinned   bool      `json:"is_pinned"`
	CreateTime time.Time `json:"create_time"`
	ModifyTime time.Time `json:"modify_time"`
}

type TopicSummarySnap struct {
	SummaryID   int64     `json:"summary_id"`
	TopicID     int64     `json:"topic_id"`
	Content     string    `json:"content"`
	SummaryType string    `json:"summary_type"`
	OrderSort   int       `json:"order_sort"`
	CreateTime  time.Time `json:"create_time"`
	ModifyTime  time.Time `json:"modify_time"`
}

type TopicResourceSnap struct {
	TopicResourceID int64     `json:"topic_resource_id"`
	TopicID         int64     `json:"topic_id"`
	ResourceType    string    `json:"resource_type"`
	TargetID        int64     `json:"target_id"`
	TitleSnapshot   string    `json:"title_snapshot"`
	DescSnapshot    string    `json:"desc_snapshot"`
	OrderSort       int       `json:"order_sort"`
	CreateTime      time.Time `json:"create_time"`
}

type TopicCommentSnap struct {
	CommentID       int64     `json:"comment_id"`
	TopicID         int64     `json:"topic_id"`
	TargetType      string    `json:"target_type"`
	TargetID        int64     `json:"target_id"`
	MemberID        int64     `json:"member_id"`
	ParentCommentID int64     `json:"parent_comment_id"`
	Content         string    `json:"content"`
	CreateTime      time.Time `json:"create_time"`
	ModifyTime      time.Time `json:"modify_time"`
}

type ShareSnap struct {
	ShareID       int64     `json:"share_id"`
	ShareType     string    `json:"share_type"`
	ShareIdentify string    `json:"share_identify"`
	TargetID      int64     `json:"target_id"`
	MemberID      int64     `json:"member_id"`
	ShareTime     time.Time `json:"share_time"`
}

type LabelRelationSnap struct {
	ID           int64  `json:"id"`
	LabelID      int64  `json:"label_id"`
	ResourceID   int64  `json:"resource_id"`
	RelationType string `json:"relation_type"`
}

// CreateTrash 创建回收站记录（在事务内执行）
func CreateTrash(tx *sql.Tx, resourceType, resourceName string, snapshot *TrashSnapshot, memberID int64) error {
	data, err := json.Marshal(snapshot)
	if err != nil {
		return fmt.Errorf("序列化快照失败: %w", err)
	}
	_, err = tx.Exec(
		"INSERT INTO md_trash (resource_type, resource_name, snapshot, member_id, delete_time) VALUES (?, ?, ?, ?, ?)",
		resourceType, resourceName, string(data), memberID, time.Now(),
	)
	return err
}

// ListTrash 列出回收站项目
func ListTrash(memberID int64, resourceType string, page, pageSize int) ([]TrashItem, int64, error) {
	where := "WHERE 1=1"
	var args []interface{}

	if memberID > 0 {
		where += " AND member_id = ?"
		args = append(args, memberID)
	}
	if resourceType != "" {
		where += " AND resource_type = ?"
		args = append(args, resourceType)
	}

	var total int64
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_trash "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	query := "SELECT trash_id, resource_type, resource_name, snapshot, member_id, delete_time FROM md_trash " + where + " ORDER BY delete_time DESC LIMIT ? OFFSET ?"
	args = append(args, pageSize, offset)

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []TrashItem
	for rows.Next() {
		var item TrashItem
		var snapshot string
		if err := rows.Scan(&item.TrashID, &item.ResourceType, &item.ResourceName, &snapshot, &item.MemberID, &item.DeleteTime); err != nil {
			return nil, 0, err
		}
		// 书签类型从 snapshot 中提取 URL
		if item.ResourceType == "bookmark" && snapshot != "" {
			var snap TrashSnapshot
			if err := json.Unmarshal([]byte(snapshot), &snap); err == nil && snap.Bookmark != nil {
				item.ResourceURL = snap.Bookmark.URL
			}
		}
		items = append(items, item)
	}
	return items, total, nil
}

// ListTrashIDsByFilter 根据筛选条件查询所有匹配的回收站ID（不分页）
func ListTrashIDsByFilter(memberID int64, resourceType string) ([]int64, error) {
	where := "WHERE 1=1"
	var args []interface{}

	if memberID > 0 {
		where += " AND member_id = ?"
		args = append(args, memberID)
	}
	if resourceType != "" {
		where += " AND resource_type = ?"
		args = append(args, resourceType)
	}

	rows, err := DB.Query("SELECT trash_id FROM md_trash "+where+" ORDER BY trash_id", args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// GetTrashByID 按 ID 获取回收站记录
func GetTrashByID(trashID int64) (*Trash, error) {
	t := &Trash{}
	err := DB.QueryRow(
		"SELECT trash_id, resource_type, resource_name, snapshot, member_id, delete_time FROM md_trash WHERE trash_id = ?",
		trashID,
	).Scan(&t.TrashID, &t.ResourceType, &t.ResourceName, &t.Snapshot, &t.MemberID, &t.DeleteTime)
	if err != nil {
		return nil, err
	}
	return t, nil
}

// RestoreFromTrash 从回收站恢复
func RestoreFromTrash(trashID int64) error {
	t, err := GetTrashByID(trashID)
	if err != nil {
		return fmt.Errorf("回收站记录不存在")
	}

	var snap TrashSnapshot
	if err := json.Unmarshal([]byte(t.Snapshot), &snap); err != nil {
		return fmt.Errorf("解析快照失败: %w", err)
	}

	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	switch t.ResourceType {
	case "book":
		if err := restoreBook(tx, snap); err != nil {
			return err
		}
	case "blog":
		if err := restoreBlog(tx, snap); err != nil {
			return err
		}
	case "bookmark":
		if err := restoreBookmark(tx, snap); err != nil {
			return err
		}
	case "document":
		if err := restoreDocument(tx, snap); err != nil {
			return err
		}
	case "task":
		taskIDMap, err := restoreTaskWithMap(tx, snap)
		if err != nil {
			return err
		}
		topicID := int64(0)
		if snap.Task != nil {
			topicID = snap.Task.TopicID
		}
		if topicID > 0 {
			if err := restoreTopicComments(tx, snap.TopicComments, topicID, nil, nil, taskIDMap); err != nil {
				return err
			}
		}
	case "topic":
		if err := restoreTopic(tx, snap); err != nil {
			return err
		}
	default:
		return fmt.Errorf("不支持恢复的资源类型: %s", t.ResourceType)
	}

	// 删除回收站记录
	if _, err := tx.Exec("DELETE FROM md_trash WHERE trash_id = ?", trashID); err != nil {
		return err
	}

	return tx.Commit()
}

func restoreBook(tx *sql.Tx, snap TrashSnapshot) error {
	if snap.Book == nil {
		return fmt.Errorf("快照数据不完整")
	}
	b := snap.Book

	// identify 冲突处理
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_books WHERE identify = ?", b.Identify).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		b.Identify = fmt.Sprintf("%s_restored_%d", b.Identify, time.Now().UnixNano())
	}

	_, err := tx.Exec(
		"INSERT INTO md_books (book_id, book_name, item_id, identify, order_index, description, label, doc_count, member_id, create_time, modify_time, is_use_first_document) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		b.BookID, b.BookName, b.ItemID, b.Identify, b.OrderIndex, b.Description, b.Label, b.DocCount, b.MemberID, b.CreateTime, b.ModifyTime, b.IsUseFirstDocument,
	)
	if err != nil {
		return fmt.Errorf("恢复书籍失败: %w", err)
	}

	// 恢复子文档
	for i := range snap.Documents {
		d := &snap.Documents[i]
		var docCount int
		if err := tx.QueryRow("SELECT COUNT(*) FROM md_documents WHERE document_id = ?", d.DocumentID).Scan(&docCount); err != nil {
			return err
		}
		if docCount > 0 {
			continue // 已存在则跳过
		}
		_, err := tx.Exec(
			"INSERT INTO md_documents (document_id, document_name, identify, book_id, parent_id, order_sort, markdown, doc_type, member_id, create_time, modify_time, modify_at, is_open, view_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			d.DocumentID, d.DocumentName, d.Identify, d.BookID, d.ParentID, d.OrderSort, d.Markdown, d.DocType, d.MemberID, d.CreateTime, d.ModifyTime, d.ModifyAt, d.IsOpen, d.ViewCount,
		)
		if err != nil {
			log.Printf("restoreBook: 恢复文档 %d 失败: %v", d.DocumentID, err)
			continue
		}
	}

	// 恢复分享记录
	for _, s := range snap.Shares {
		_, err := tx.Exec(
			"INSERT OR IGNORE INTO md_shares (share_type, share_identify, target_id, member_id, share_time) VALUES (?, ?, ?, ?, ?)",
			s.ShareType, s.ShareIdentify, s.TargetID, s.MemberID, s.ShareTime,
		)
		if err != nil {
			log.Printf("restoreBook: 恢复分享记录失败: %v", err)
		}
	}

	// 恢复标签关联
	restoreLabelRelations(tx, snap.LabelRelations)

	return nil
}

func restoreTopic(tx *sql.Tx, snap TrashSnapshot) error {
	if snap.Topic == nil {
		return fmt.Errorf("快照数据不完整")
	}
	t := snap.Topic
	topicID := t.TopicID
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_topics WHERE topic_id = ?", topicID).Scan(&count); err != nil {
		return err
	}
	if count == 0 {
		_, err := tx.Exec(
			"INSERT INTO md_topics (topic_id, title, question, member_id, is_pinned, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?)",
			t.TopicID, t.Title, t.Question, t.MemberID, boolToInt(t.IsPinned), t.CreateTime, t.ModifyTime,
		)
		if err != nil {
			return fmt.Errorf("恢复专题失败: %w", err)
		}
	} else {
		res, err := tx.Exec(
			"INSERT INTO md_topics (title, question, member_id, is_pinned, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?)",
			t.Title, t.Question, t.MemberID, boolToInt(t.IsPinned), t.CreateTime, t.ModifyTime,
		)
		if err != nil {
			return fmt.Errorf("恢复专题失败: %w", err)
		}
		topicID, _ = res.LastInsertId()
	}

	summaryIDMap := make(map[int64]int64, len(snap.TopicSummaries))
	for _, summary := range snap.TopicSummaries {
		summary.SummaryType = NormalizeTopicSummaryType(summary.SummaryType)
		var summaryCount int
		if err := tx.QueryRow("SELECT COUNT(*) FROM md_topic_summaries WHERE summary_id = ?", summary.SummaryID).Scan(&summaryCount); err != nil {
			return err
		}
		if summaryCount == 0 && topicID == summary.TopicID {
			_, err := tx.Exec(
				"INSERT INTO md_topic_summaries (summary_id, topic_id, content, summary_type, order_sort, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?)",
				summary.SummaryID, topicID, summary.Content, summary.SummaryType, summary.OrderSort, summary.CreateTime, summary.ModifyTime,
			)
			if err != nil {
				return fmt.Errorf("恢复专题小结失败: %w", err)
			}
			summaryIDMap[summary.SummaryID] = summary.SummaryID
			continue
		}
		res, err := tx.Exec(
			"INSERT INTO md_topic_summaries (topic_id, content, summary_type, order_sort, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?)",
			topicID, summary.Content, summary.SummaryType, summary.OrderSort, summary.CreateTime, summary.ModifyTime,
		)
		if err != nil {
			return fmt.Errorf("恢复专题小结失败: %w", err)
		}
		summaryIDMap[summary.SummaryID], _ = res.LastInsertId()
	}

	resourceIDMap := make(map[int64]int64, len(snap.TopicResources))
	for _, resource := range snap.TopicResources {
		var resourceCount int
		if err := tx.QueryRow("SELECT COUNT(*) FROM md_topic_resources WHERE topic_resource_id = ?", resource.TopicResourceID).Scan(&resourceCount); err != nil {
			return err
		}
		if resourceCount == 0 && topicID == resource.TopicID {
			_, err := tx.Exec(
				"INSERT INTO md_topic_resources (topic_resource_id, topic_id, resource_type, target_id, title_snapshot, desc_snapshot, order_sort, create_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
				resource.TopicResourceID, topicID, resource.ResourceType, resource.TargetID, resource.TitleSnapshot, resource.DescSnapshot, resource.OrderSort, resource.CreateTime,
			)
			if err != nil {
				return fmt.Errorf("恢复专题资料失败: %w", err)
			}
			resourceIDMap[resource.TopicResourceID] = resource.TopicResourceID
			continue
		}
		res, err := tx.Exec(
			"INSERT OR IGNORE INTO md_topic_resources (topic_id, resource_type, target_id, title_snapshot, desc_snapshot, order_sort, create_time) VALUES (?, ?, ?, ?, ?, ?, ?)",
			topicID, resource.ResourceType, resource.TargetID, resource.TitleSnapshot, resource.DescSnapshot, resource.OrderSort, resource.CreateTime,
		)
		if err != nil {
			return fmt.Errorf("恢复专题资料失败: %w", err)
		}
		resourceIDMap[resource.TopicResourceID], _ = res.LastInsertId()
		if resourceIDMap[resource.TopicResourceID] == 0 {
			var restoredResourceID int64
			_ = tx.QueryRow(`SELECT topic_resource_id FROM md_topic_resources
				WHERE topic_id = ? AND resource_type = ? AND target_id = ?`,
				topicID, resource.ResourceType, resource.TargetID).Scan(&restoredResourceID)
			resourceIDMap[resource.TopicResourceID] = restoredResourceID
		}
	}

	for i := range snap.Tasks {
		snap.Tasks[i].TopicID = topicID
	}
	taskIDMap, err := restoreTaskWithMap(tx, snap)
	if err != nil && len(snap.Tasks) > 0 {
		return err
	}
	if err := restoreTopicComments(tx, snap.TopicComments, topicID, summaryIDMap, resourceIDMap, taskIDMap); err != nil {
		return err
	}
	for _, s := range snap.Shares {
		_, err := tx.Exec(
			"INSERT OR IGNORE INTO md_shares (share_type, share_identify, target_id, member_id, share_time) VALUES (?, ?, ?, ?, ?)",
			s.ShareType, s.ShareIdentify, topicID, s.MemberID, s.ShareTime,
		)
		if err != nil {
			log.Printf("restoreTopic: 恢复分享记录失败: %v", err)
		}
	}

	return nil
}

func restoreBlog(tx *sql.Tx, snap TrashSnapshot) error {
	if snap.Blog == nil {
		return fmt.Errorf("快照数据不完整")
	}
	b := snap.Blog

	// identify 冲突处理
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_blogs WHERE blog_identify = ?", b.BlogIdentify).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		b.BlogIdentify = fmt.Sprintf("%s_restored_%d", b.BlogIdentify, time.Now().UnixNano())
	}

	_, err := tx.Exec(
		"INSERT INTO md_blogs (blog_id, blog_title, blog_identify, member_id, blog_content, blog_desc, password, modify_time, modify_at, create_time, version, blog_type, visibility, is_pinned, pin_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		b.BlogID, b.BlogTitle, b.BlogIdentify, b.MemberID, b.BlogContent, b.BlogDesc, b.Password, b.ModifyTime, b.ModifyAt, b.CreateTime, b.Version, b.BlogType, b.Visibility, b.IsPinned, b.PinOrder,
	)
	if err != nil {
		return fmt.Errorf("恢复博客失败: %w", err)
	}

	// 恢复分享记录
	for _, s := range snap.Shares {
		_, err := tx.Exec(
			"INSERT OR IGNORE INTO md_shares (share_type, share_identify, target_id, member_id, share_time) VALUES (?, ?, ?, ?, ?)",
			s.ShareType, s.ShareIdentify, s.TargetID, s.MemberID, s.ShareTime,
		)
		if err != nil {
			log.Printf("restoreBlog: 恢复分享记录失败: %v", err)
		}
	}

	restoreLabelRelations(tx, snap.LabelRelations)
	return nil
}

func restoreBookmark(tx *sql.Tx, snap TrashSnapshot) error {
	if snap.Bookmark == nil {
		return fmt.Errorf("快照数据不完整")
	}
	b := snap.Bookmark

	isPublic := 0
	if b.IsPublic {
		isPublic = 1
	}
	isPinned := 0
	if b.IsPinned {
		isPinned = 1
	}
	isNavVisible := 0
	if b.NavVisible {
		isNavVisible = 1
	}

	_, err := tx.Exec(
		"INSERT INTO md_bookmark (bookmark_id, title, url, description, favicon, order_sort, label, member_id, is_public, is_pinned, nav_visible, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		b.BookmarkID, b.Title, b.URL, b.Description, b.Favicon, b.OrderSort, b.Label, b.MemberID, isPublic, isPinned, isNavVisible, b.CreateTime, b.ModifyTime,
	)
	if err != nil {
		return fmt.Errorf("恢复书签失败: %w", err)
	}

	restoreLabelRelations(tx, snap.LabelRelations)
	return nil
}

func restoreDocument(tx *sql.Tx, snap TrashSnapshot) error {
	if snap.Document == nil {
		return fmt.Errorf("快照数据不完整")
	}
	d := snap.Document

	// 检查父书籍是否仍存在
	var bookCount int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_books WHERE book_id = ?", d.BookID).Scan(&bookCount); err != nil {
		return err
	}
	if bookCount == 0 {
		return fmt.Errorf("文档所属书籍不存在，无法恢复")
	}

	// identify 冲突处理
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_documents WHERE book_id = ? AND identify = ?", d.BookID, d.Identify).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		d.Identify = fmt.Sprintf("%s_restored_%d", d.Identify, time.Now().UnixNano())
	}

	_, err := tx.Exec(
		"INSERT INTO md_documents (document_id, document_name, identify, book_id, parent_id, order_sort, markdown, doc_type, member_id, create_time, modify_time, modify_at, is_open, view_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		d.DocumentID, d.DocumentName, d.Identify, d.BookID, d.ParentID, d.OrderSort, d.Markdown, d.DocType, d.MemberID, d.CreateTime, d.ModifyTime, d.ModifyAt, d.IsOpen, d.ViewCount,
	)
	if err != nil {
		return fmt.Errorf("恢复文档失败: %w", err)
	}

	// 更新书籍文档计数
	if _, err := tx.Exec("UPDATE md_books SET doc_count = doc_count + 1 WHERE book_id = ?", d.BookID); err != nil {
		log.Printf("restoreDocument: 更新文档计数失败: %v", err)
	}

	// 恢复分享记录
	for _, s := range snap.Shares {
		_, err := tx.Exec(
			"INSERT OR IGNORE INTO md_shares (share_type, share_identify, target_id, member_id, share_time) VALUES (?, ?, ?, ?, ?)",
			s.ShareType, s.ShareIdentify, s.TargetID, s.MemberID, s.ShareTime,
		)
		if err != nil {
			log.Printf("restoreDocument: 恢复分享记录失败: %v", err)
		}
	}

	return nil
}

func restoreTask(tx *sql.Tx, snap TrashSnapshot) error {
	_, err := restoreTaskWithMap(tx, snap)
	return err
}

func restoreTaskWithMap(tx *sql.Tx, snap TrashSnapshot) (map[int64]int64, error) {
	tasks := snap.Tasks
	if len(tasks) == 0 && snap.Task != nil {
		tasks = []TaskSnap{*snap.Task}
	}
	if len(tasks) == 0 {
		return map[int64]int64{}, fmt.Errorf("快照数据不完整")
	}

	idMap := make(map[int64]int64, len(tasks))
	for _, t := range tasks {
		var parentID int64
		if t.ParentID > 0 {
			parentID = idMap[t.ParentID]
			if parentID == 0 {
				var parentExists int
				if err := tx.QueryRow("SELECT COUNT(*) FROM md_tasks WHERE task_id = ?", t.ParentID).Scan(&parentExists); err != nil {
					return idMap, err
				}
				if parentExists > 0 {
					parentID = t.ParentID
				}
			}
		}
		var count int
		if err := tx.QueryRow("SELECT COUNT(*) FROM md_tasks WHERE task_id = ?", t.TaskID).Scan(&count); err != nil {
			return idMap, err
		}
		done := 0
		if t.Done {
			done = 1
		}
		var err error
		if count == 0 {
			_, err = tx.Exec(
				"INSERT INTO md_tasks (task_id, content, due_date, done, parent_id, topic_id, member_id, complete_time, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
				t.TaskID, t.Content, t.DueDate, done, parentID, t.TopicID, t.MemberID, t.CompleteTime, t.CreateTime, t.ModifyTime,
			)
			if err != nil {
				return idMap, fmt.Errorf("恢复待办失败: %w", err)
			}
			idMap[t.TaskID] = t.TaskID
		} else {
			res, err := tx.Exec(
				"INSERT INTO md_tasks (content, due_date, done, parent_id, topic_id, member_id, complete_time, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
				t.Content, t.DueDate, done, parentID, t.TopicID, t.MemberID, t.CompleteTime, t.CreateTime, t.ModifyTime,
			)
			if err != nil {
				return idMap, fmt.Errorf("恢复待办失败: %w", err)
			}
			newID, _ := res.LastInsertId()
			idMap[t.TaskID] = newID
		}
	}
	return idMap, nil
}

func restoreTopicComments(tx *sql.Tx, comments []TopicCommentSnap, topicID int64, summaryIDMap, resourceIDMap, taskIDMap map[int64]int64) error {
	if len(comments) == 0 {
		return nil
	}
	commentIDMap := make(map[int64]int64, len(comments))
	pending := make([]TopicCommentSnap, 0)
	resolveTarget := func(comment TopicCommentSnap) int64 {
		switch NormalizeTopicCommentTargetType(comment.TargetType) {
		case TopicCommentSummary:
			return summaryIDMap[comment.TargetID]
		case TopicCommentResource:
			return resourceIDMap[comment.TargetID]
		case TopicCommentTask:
			return taskIDMap[comment.TargetID]
		default:
			return 0
		}
	}
	insert := func(comment TopicCommentSnap, parentID int64) error {
		targetID := resolveTarget(comment)
		if targetID == 0 {
			return nil
		}
		res, err := tx.Exec(`INSERT INTO md_topic_comments
			(topic_id, target_type, target_id, member_id, parent_comment_id, content, create_time, modify_time)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			topicID, NormalizeTopicCommentTargetType(comment.TargetType), targetID, comment.MemberID,
			parentID, comment.Content, comment.CreateTime, comment.ModifyTime)
		if err != nil {
			return err
		}
		commentIDMap[comment.CommentID], _ = res.LastInsertId()
		return nil
	}
	for _, comment := range comments {
		if comment.ParentCommentID > 0 {
			pending = append(pending, comment)
			continue
		}
		if err := insert(comment, 0); err != nil {
			return fmt.Errorf("恢复专题评论失败: %w", err)
		}
	}
	for _, comment := range pending {
		parentID := commentIDMap[comment.ParentCommentID]
		if parentID == 0 {
			continue
		}
		if err := insert(comment, parentID); err != nil {
			return fmt.Errorf("恢复专题评论回复失败: %w", err)
		}
	}
	return nil
}

// restoreLabelRelations 恢复标签关联（跳过已删除的标签）
func restoreLabelRelations(tx *sql.Tx, relations []LabelRelationSnap) {
	for _, r := range relations {
		// 检查标签是否仍存在
		var count int
		if err := tx.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_id = ?", r.LabelID).Scan(&count); err != nil {
			log.Printf("restoreLabelRelations: 检查标签失败: %v", err)
			continue
		}
		if count == 0 {
			continue // 标签已删除，跳过
		}
		_, err := tx.Exec(
			"INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, ?, datetime('now'))",
			r.LabelID, r.ResourceID, r.RelationType,
		)
		if err != nil {
			log.Printf("restoreLabelRelations: 恢复标签关联失败: %v", err)
		}
	}
}

// PermanentDeleteTrash 永久删除回收站记录
func PermanentDeleteTrash(trashID, memberID int64, isAdmin bool) error {
	if isAdmin {
		_, err := DB.Exec("DELETE FROM md_trash WHERE trash_id = ?", trashID)
		return err
	}
	_, err := DB.Exec("DELETE FROM md_trash WHERE trash_id = ? AND member_id = ?", trashID, memberID)
	return err
}

// BatchRestoreTrash 批量恢复
func BatchRestoreTrash(trashIDs []int64, memberID int64, isAdmin bool) ([]string, error) {
	var errors []string
	for _, id := range trashIDs {
		if !isAdmin {
			t, err := GetTrashByID(id)
			if err != nil || t.MemberID != memberID {
				errors = append(errors, fmt.Sprintf("记录 %d 无权操作", id))
				continue
			}
		}
		if err := RestoreFromTrash(id); err != nil {
			errors = append(errors, fmt.Sprintf("记录 %d 恢复失败: %s", id, err.Error()))
		}
	}
	return errors, nil
}

// PurgeTrash 清空回收站
func PurgeTrash(memberID int64, isAdmin bool) error {
	if isAdmin {
		_, err := DB.Exec("DELETE FROM md_trash")
		return err
	}
	_, err := DB.Exec("DELETE FROM md_trash WHERE member_id = ?", memberID)
	return err
}

// BatchDeleteTrash 批量永久删除回收站记录
func BatchDeleteTrash(ids []int64, memberID int64, isAdmin bool) ([]string, error) {
	tx, err := DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var errors []string
	for _, id := range ids {
		// 权限检查
		if !isAdmin {
			var ownerID int64
			err := tx.QueryRow("SELECT member_id FROM md_trash WHERE trash_id = ?", id).Scan(&ownerID)
			if err != nil || ownerID != memberID {
				errors = append(errors, fmt.Sprintf("记录 %d 无权操作", id))
				continue
			}
		}

		// 获取回收站记录的类型和快照
		var resourceType, snapshot string
		err := tx.QueryRow("SELECT resource_type, snapshot FROM md_trash WHERE trash_id = ?", id).Scan(&resourceType, &snapshot)
		if err != nil {
			errors = append(errors, fmt.Sprintf("记录 %d 获取信息失败", id))
			continue
		}

		// 从快照中解析资源 ID
		var snap TrashSnapshot
		if err := json.Unmarshal([]byte(snapshot), &snap); err != nil {
			errors = append(errors, fmt.Sprintf("记录 %d 解析快照失败", id))
			continue
		}

		// 根据类型永久删除资源
		switch resourceType {
		case "book":
			if snap.Book != nil {
				resourceID := snap.Book.BookID
				tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'book'", resourceID)
				// 先删除子文档的标签关联和分享，再删除子文档
				for _, d := range snap.Documents {
					tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'document'", d.DocumentID)
				}
				tx.Exec("DELETE FROM md_shares WHERE resource_type = 'book' AND target_id = ?", resourceID)
				for _, s := range snap.Shares {
					tx.Exec("DELETE FROM md_shares WHERE share_id = ?", s.ShareID)
				}
				tx.Exec("DELETE FROM md_documents WHERE book_id = ?", resourceID)
				tx.Exec("DELETE FROM md_books WHERE book_id = ?", resourceID)
			}
		case "blog":
			if snap.Blog != nil {
				resourceID := snap.Blog.BlogID
				tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'blog'", resourceID)
				for _, s := range snap.Shares {
					tx.Exec("DELETE FROM md_shares WHERE share_id = ?", s.ShareID)
				}
				tx.Exec("DELETE FROM md_blogs WHERE blog_id = ?", resourceID)
			}
		case "bookmark":
			if snap.Bookmark != nil {
				resourceID := snap.Bookmark.BookmarkID
				tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'bookmark'", resourceID)
				for _, s := range snap.Shares {
					tx.Exec("DELETE FROM md_shares WHERE share_id = ?", s.ShareID)
				}
				tx.Exec("DELETE FROM md_bookmark WHERE bookmark_id = ?", resourceID)
			}
		case "document":
			if snap.Document != nil {
				resourceID := snap.Document.DocumentID
				tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'document'", resourceID)
				for _, s := range snap.Shares {
					tx.Exec("DELETE FROM md_shares WHERE share_id = ?", s.ShareID)
				}
				tx.Exec("DELETE FROM md_documents WHERE document_id = ?", resourceID)
			}
		case "task":
			if len(snap.Tasks) > 0 {
				for _, t := range snap.Tasks {
					tx.Exec("DELETE FROM md_tasks WHERE task_id = ?", t.TaskID)
				}
			} else if snap.Task != nil {
				tx.Exec("DELETE FROM md_tasks WHERE task_id = ?", snap.Task.TaskID)
			}
		}

		// 删除回收站记录
		tx.Exec("DELETE FROM md_trash WHERE trash_id = ?", id)
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return errors, nil
}

// CountTrashByMember 统计用户回收站数量
func CountTrashByMember(memberID int64) (int64, error) {
	var count int64
	err := DB.QueryRow("SELECT COUNT(*) FROM md_trash WHERE member_id = ?", memberID).Scan(&count)
	return count, err
}

// --- 快照辅助函数 ---

// SnapshotBook 快照书籍（含子文档、分享、标签关联）
func SnapshotBook(tx *sql.Tx, bookID int64) (*TrashSnapshot, string, error) {
	snap := &TrashSnapshot{}

	// 快照书籍
	b, err := GetBookByID(bookID)
	if err != nil {
		return nil, "", fmt.Errorf("获取书籍失败: %w", err)
	}
	snap.Book = &BookSnap{
		BookID:             b.BookID,
		BookName:           b.BookName,
		ItemID:             b.ItemID,
		Identify:           b.Identify,
		OrderIndex:         b.OrderIndex,
		Description:        b.Description,
		Label:              b.Label,
		DocCount:           b.DocCount,
		MemberID:           b.MemberID,
		CreateTime:         b.CreateTime,
		ModifyTime:         b.ModifyTime,
		IsUseFirstDocument: b.IsUseFirstDocument,
	}

	// 快照子文档
	docRows, err := tx.Query("SELECT document_id, document_name, identify, book_id, parent_id, order_sort, markdown, COALESCE(doc_type,'markdown'), member_id, create_time, modify_time, modify_at, is_open, view_count FROM md_documents WHERE book_id = ?", bookID)
	if err != nil {
		return nil, "", fmt.Errorf("获取文档列表失败: %w", err)
	}
	defer docRows.Close()
	for docRows.Next() {
		var d DocumentSnap
		if err := docRows.Scan(&d.DocumentID, &d.DocumentName, &d.Identify, &d.BookID, &d.ParentID, &d.OrderSort, &d.Markdown, &d.DocType, &d.MemberID, &d.CreateTime, &d.ModifyTime, &d.ModifyAt, &d.IsOpen, &d.ViewCount); err != nil {
			return nil, "", err
		}
		snap.Documents = append(snap.Documents, d)
	}

	// 快照书籍分享
	shareRows, err := tx.Query("SELECT share_id, share_type, share_identify, target_id, member_id, share_time FROM md_shares WHERE share_type = 'book' AND target_id = ?", bookID)
	if err != nil {
		return nil, "", err
	}
	defer shareRows.Close()
	for shareRows.Next() {
		var s ShareSnap
		if err := shareRows.Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime); err != nil {
			return nil, "", err
		}
		snap.Shares = append(snap.Shares, s)
	}

	// 快照子文档分享
	if len(snap.Documents) > 0 {
		docIDs := make([]int64, len(snap.Documents))
		for i, d := range snap.Documents {
			docIDs[i] = d.DocumentID
		}
		placeholders := ""
		args := make([]interface{}, len(docIDs))
		for i, id := range docIDs {
			if i > 0 {
				placeholders += ","
			}
			placeholders += "?"
			args[i] = id
		}
		docShareRows, err := tx.Query("SELECT share_id, share_type, share_identify, target_id, member_id, share_time FROM md_shares WHERE share_type = 'document' AND target_id IN ("+placeholders+")", args...)
		if err != nil {
			return nil, "", err
		}
		defer docShareRows.Close()
		for docShareRows.Next() {
			var s ShareSnap
			if err := docShareRows.Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime); err != nil {
				return nil, "", err
			}
			snap.Shares = append(snap.Shares, s)
		}
	}

	// 快照标签关联
	snap.LabelRelations, err = snapshotLabelRelations(tx, bookID, "book")
	if err != nil {
		return nil, "", err
	}

	return snap, b.BookName, nil
}

// SnapshotBlog 快照博客
func SnapshotBlog(tx *sql.Tx, blogID int64) (*TrashSnapshot, string, error) {
	snap := &TrashSnapshot{}

	b, err := GetBlogByID(blogID)
	if err != nil {
		return nil, "", fmt.Errorf("获取博客失败: %w", err)
	}
	snap.Blog = &BlogSnap{
		BlogID:       b.BlogID,
		BlogTitle:    b.BlogTitle,
		BlogIdentify: b.BlogIdentify,
		MemberID:     b.MemberID,
		BlogContent:  b.BlogContent,
		BlogDesc:     b.BlogDesc,
		Password:     b.Password,
		ModifyTime:   b.ModifyTime,
		ModifyAt:     b.ModifyAt,
		CreateTime:   b.CreateTime,
		Version:      b.Version,
		BlogType:     b.BlogType,
		Visibility:   b.Visibility,
		IsPinned:     b.IsPinned,
		PinOrder:     b.PinOrder,
	}

	// 快照分享
	shareRows, err := tx.Query("SELECT share_id, share_type, share_identify, target_id, member_id, share_time FROM md_shares WHERE share_type = 'blog' AND target_id = ?", blogID)
	if err != nil {
		return nil, "", err
	}
	defer shareRows.Close()
	for shareRows.Next() {
		var s ShareSnap
		if err := shareRows.Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime); err != nil {
			return nil, "", err
		}
		snap.Shares = append(snap.Shares, s)
	}

	// 快照标签关联
	snap.LabelRelations, err = snapshotLabelRelations(tx, blogID, "blog")
	if err != nil {
		return nil, "", err
	}

	return snap, b.BlogTitle, nil
}

// SnapshotBookmark 快照书签
func SnapshotBookmark(tx *sql.Tx, bookmarkID int64) (*TrashSnapshot, string, error) {
	snap := &TrashSnapshot{}

	b, err := GetBookmarkByIDTx(tx, bookmarkID)
	if err != nil {
		return nil, "", fmt.Errorf("获取书签失败: %w", err)
	}
	snap.Bookmark = &BookmarkSnap{
		BookmarkID:  b.BookmarkID,
		Title:       b.Title,
		URL:         b.URL,
		Description: b.Description,
		Favicon:     b.Favicon,
		OrderSort:   b.OrderSort,
		Label:       b.Label,
		MemberID:    b.MemberID,
		IsPublic:    b.IsPublic,
		IsPinned:    b.IsPinned,
		NavVisible:  b.NavVisible,
		CreateTime:  b.CreateTime,
		ModifyTime:  b.ModifyTime,
	}

	// 快照标签关联
	snap.LabelRelations, err = snapshotLabelRelations(tx, bookmarkID, "bookmark")
	if err != nil {
		return nil, "", err
	}

	return snap, b.Title, nil
}

// SnapshotTopic 快照专题（含资料、分享、标签关联）。
func SnapshotTopic(tx *sql.Tx, topicID int64) (*TrashSnapshot, string, error) {
	snap := &TrashSnapshot{}

	t, err := GetTopicByID(topicID)
	if err != nil {
		return nil, "", fmt.Errorf("获取专题失败: %w", err)
	}
	snap.Topic = &TopicSnap{
		TopicID:    t.TopicID,
		Title:      t.Title,
		Question:   t.Question,
		MemberID:   t.MemberID,
		IsPinned:   t.IsPinned,
		CreateTime: t.CreateTime,
		ModifyTime: t.ModifyTime,
	}

	rows, err := tx.Query("SELECT summary_id, topic_id, content, summary_type, order_sort, create_time, modify_time FROM md_topic_summaries WHERE topic_id = ? ORDER BY order_sort, summary_id", topicID)
	if err != nil {
		return nil, "", fmt.Errorf("获取专题小结失败: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var summary TopicSummarySnap
		if err := rows.Scan(&summary.SummaryID, &summary.TopicID, &summary.Content, &summary.SummaryType, &summary.OrderSort, &summary.CreateTime, &summary.ModifyTime); err != nil {
			return nil, "", err
		}
		summary.SummaryType = NormalizeTopicSummaryType(summary.SummaryType)
		snap.TopicSummaries = append(snap.TopicSummaries, summary)
	}

	resourceRows, err := tx.Query("SELECT topic_resource_id, topic_id, resource_type, target_id, title_snapshot, desc_snapshot, order_sort, create_time FROM md_topic_resources WHERE topic_id = ? ORDER BY order_sort, topic_resource_id", topicID)
	if err != nil {
		return nil, "", fmt.Errorf("获取专题资料失败: %w", err)
	}
	defer resourceRows.Close()
	for resourceRows.Next() {
		var resource TopicResourceSnap
		if err := resourceRows.Scan(&resource.TopicResourceID, &resource.TopicID, &resource.ResourceType, &resource.TargetID, &resource.TitleSnapshot, &resource.DescSnapshot, &resource.OrderSort, &resource.CreateTime); err != nil {
			return nil, "", err
		}
		snap.TopicResources = append(snap.TopicResources, resource)
	}

	taskRows, err := tx.Query("SELECT task_id, content, due_date, done, parent_id, topic_id, member_id, complete_time, create_time, modify_time FROM md_tasks WHERE topic_id = ? ORDER BY parent_id, task_id", topicID)
	if err != nil {
		return nil, "", fmt.Errorf("获取专题待办失败: %w", err)
	}
	defer taskRows.Close()
	for taskRows.Next() {
		var task TaskSnap
		var done int
		if err := taskRows.Scan(&task.TaskID, &task.Content, &task.DueDate, &done, &task.ParentID, &task.TopicID, &task.MemberID, &task.CompleteTime, &task.CreateTime, &task.ModifyTime); err != nil {
			return nil, "", err
		}
		task.Done = done == 1
		snap.Tasks = append(snap.Tasks, task)
	}

	commentRows, err := tx.Query(`SELECT comment_id, topic_id, target_type, target_id, member_id,
		parent_comment_id, content, create_time, modify_time
		FROM md_topic_comments WHERE topic_id = ? ORDER BY create_time, comment_id`, topicID)
	if err != nil {
		return nil, "", fmt.Errorf("获取专题评论失败: %w", err)
	}
	defer commentRows.Close()
	for commentRows.Next() {
		var comment TopicCommentSnap
		if err := commentRows.Scan(
			&comment.CommentID, &comment.TopicID, &comment.TargetType, &comment.TargetID,
			&comment.MemberID, &comment.ParentCommentID, &comment.Content,
			&comment.CreateTime, &comment.ModifyTime,
		); err != nil {
			return nil, "", err
		}
		snap.TopicComments = append(snap.TopicComments, comment)
	}

	shareRows, err := tx.Query("SELECT share_id, share_type, share_identify, target_id, member_id, share_time FROM md_shares WHERE share_type = 'topic' AND target_id = ?", topicID)
	if err != nil {
		return nil, "", err
	}
	defer shareRows.Close()
	for shareRows.Next() {
		var s ShareSnap
		if err := shareRows.Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime); err != nil {
			return nil, "", err
		}
		snap.Shares = append(snap.Shares, s)
	}

	return snap, t.Title, nil
}

// SnapshotDocument 快照文档
func SnapshotDocument(tx *sql.Tx, docID int64) (*TrashSnapshot, string, error) {
	snap := &TrashSnapshot{}

	d, err := GetDocumentByID(docID)
	if err != nil {
		return nil, "", fmt.Errorf("获取文档失败: %w", err)
	}
	snap.Document = &DocumentSnap{
		DocumentID:   d.DocumentID,
		DocumentName: d.DocumentName,
		Identify:     d.Identify,
		BookID:       d.BookID,
		ParentID:     d.ParentID,
		OrderSort:    d.OrderSort,
		Markdown:     d.Markdown,
		DocType:      d.DocType,
		MemberID:     d.MemberID,
		CreateTime:   d.CreateTime,
		ModifyTime:   d.ModifyTime,
		ModifyAt:     d.ModifyAt,
		IsOpen:       d.IsOpen,
		ViewCount:    d.ViewCount,
	}

	// 快照分享
	shareRows, err := tx.Query("SELECT share_id, share_type, share_identify, target_id, member_id, share_time FROM md_shares WHERE share_type = 'document' AND target_id = ?", docID)
	if err != nil {
		return nil, "", err
	}
	defer shareRows.Close()
	for shareRows.Next() {
		var s ShareSnap
		if err := shareRows.Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime); err != nil {
			return nil, "", err
		}
		snap.Shares = append(snap.Shares, s)
	}

	return snap, d.DocumentName, nil
}

// SnapshotTask 快照待办及其子待办。
func SnapshotTask(tx *sql.Tx, taskID int64) (*TrashSnapshot, string, error) {
	snap := &TrashSnapshot{}
	rows, err := tx.Query(`
		WITH RECURSIVE subtree(task_id, depth) AS (
			SELECT task_id, 0 FROM md_tasks WHERE task_id = ?
			UNION ALL
			SELECT child.task_id, parent.depth + 1
			FROM md_tasks child
			JOIN subtree parent ON child.parent_id = parent.task_id
		)
		SELECT t.task_id, t.content, t.due_date, t.done, t.parent_id, t.topic_id, t.member_id, t.complete_time, t.create_time, t.modify_time
		FROM md_tasks t
		JOIN subtree s ON s.task_id = t.task_id
		ORDER BY s.depth ASC, t.task_id ASC`, taskID)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	for rows.Next() {
		var t TaskSnap
		var done int
		if err := rows.Scan(&t.TaskID, &t.Content, &t.DueDate, &done, &t.ParentID, &t.TopicID, &t.MemberID, &t.CompleteTime, &t.CreateTime, &t.ModifyTime); err != nil {
			return nil, "", err
		}
		t.Done = done == 1
		if snap.Task == nil {
			root := t
			snap.Task = &root
		}
		snap.Tasks = append(snap.Tasks, t)
	}
	if err := rows.Err(); err != nil {
		return nil, "", err
	}
	if snap.Task == nil {
		return nil, "", fmt.Errorf("待办不存在")
	}
	if snap.Task.TopicID > 0 {
		commentRows, err := tx.Query(`
			WITH RECURSIVE subtree(task_id) AS (
				SELECT task_id FROM md_tasks WHERE task_id = ?
				UNION ALL
				SELECT child.task_id FROM md_tasks child
				JOIN subtree parent ON child.parent_id = parent.task_id
			)
			SELECT comment_id, topic_id, target_type, target_id, member_id,
				parent_comment_id, content, create_time, modify_time
			FROM md_topic_comments
			WHERE topic_id = ? AND target_type = ? AND target_id IN (SELECT task_id FROM subtree)
			ORDER BY create_time, comment_id`, taskID, snap.Task.TopicID, TopicCommentTask)
		if err != nil {
			return nil, "", err
		}
		defer commentRows.Close()
		for commentRows.Next() {
			var comment TopicCommentSnap
			if err := commentRows.Scan(
				&comment.CommentID, &comment.TopicID, &comment.TargetType, &comment.TargetID,
				&comment.MemberID, &comment.ParentCommentID, &comment.Content,
				&comment.CreateTime, &comment.ModifyTime,
			); err != nil {
				return nil, "", err
			}
			snap.TopicComments = append(snap.TopicComments, comment)
		}
	}
	name := taskSnapshotName(snap.Task.Content)
	return snap, name, nil
}

func taskSnapshotName(content string) string {
	name := strings.TrimSpace(strings.Split(content, "\n")[0])
	if name == "" {
		return "未命名待办"
	}
	runes := []rune(name)
	if len(runes) > 60 {
		return string(runes[:60]) + "..."
	}
	return name
}

func snapshotLabelRelations(tx *sql.Tx, resourceID int64, relationType string) ([]LabelRelationSnap, error) {
	rows, err := tx.Query("SELECT id, label_id, resource_id, relation_type FROM md_label_relation WHERE resource_id = ? AND relation_type = ?", resourceID, relationType)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var relations []LabelRelationSnap
	for rows.Next() {
		var r LabelRelationSnap
		if err := rows.Scan(&r.ID, &r.LabelID, &r.ResourceID, &r.RelationType); err != nil {
			return nil, err
		}
		relations = append(relations, r)
	}
	return relations, nil
}
