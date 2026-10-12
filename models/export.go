package models

import (
	"archive/zip"
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// ========== 导出数据结构 ==========

type ExportManifest struct {
	Version    int         `json:"version"`
	ExportTime string      `json:"export_time"`
	Source     string      `json:"source"`
	Stats      ExportStats `json:"stats"`
}

type ExportStats struct {
	Books       int `json:"books"`
	Documents   int `json:"documents"`
	Blogs       int `json:"blogs"`
	Bookmarks   int `json:"bookmarks"`
	Tasks       int `json:"tasks"`
	Topics      int `json:"topics"`
	Labels      int `json:"labels"`
	FriendLinks int `json:"friend_links"`
	Uploads     int `json:"uploads"`
}

// ExportUpload 是一条上传文件的元数据，对应 md_uploads 一行。
// 文件本体（含缩略图）以二进制形式写入 zip 的 uploads/ 子目录，
// 路径与 StoragePath / ThumbPath 一致（相对 data/uploads/）。
type ExportUpload struct {
	FileName    string `json:"file_name"`
	StoragePath string `json:"storage_path"`
	FileHash    string `json:"file_hash"`
	FileSize    int64  `json:"file_size"`
	MimeType    string `json:"mime_type"`
	Width       int    `json:"width"`
	Height      int    `json:"height"`
	ThumbPath   string `json:"thumb_path"`
	ThumbSize   int64  `json:"thumb_size"`
	Category    string `json:"category"`
	CreateTime  string `json:"create_time"`
}

type ExportBook struct {
	BookName           string      `json:"book_name"`
	Identify           string      `json:"identify"`
	Description        string      `json:"description"`
	Label              string      `json:"label"`
	OrderIndex         int         `json:"order_index"`
	IsUseFirstDocument int         `json:"is_use_first_document"`
	CreateTime         string      `json:"create_time"`
	ModifyTime         string      `json:"modify_time"`
	Documents          []ExportDoc `json:"documents"`
}

type ExportDoc struct {
	DocumentName   string `json:"document_name"`
	Identify       string `json:"identify"`
	ParentIdentify string `json:"parent_identify"`
	OrderSort      int    `json:"order_sort"`
	DocType        string `json:"doc_type"`
	Markdown       string `json:"markdown"`
	IsOpen         int    `json:"is_open"`
	CreateTime     string `json:"create_time"`
	ModifyTime     string `json:"modify_time"`
}

type ExportBlog struct {
	BlogTitle    string `json:"blog_title"`
	BlogIdentify string `json:"blog_identify"`
	BlogContent  string `json:"blog_content"`
	BlogDesc     string `json:"blog_desc,omitempty"`
	Password     string `json:"password"`
	BlogType     string `json:"blog_type"`
	Visibility   int    `json:"visibility"`
	IsPinned     int    `json:"is_pinned"`
	PinOrder     int    `json:"pin_order"`
	Version      int    `json:"version"`
	CreateTime   string `json:"create_time"`
	ModifyTime   string `json:"modify_time"`
}

type ExportBookmark struct {
	Title       string `json:"title"`
	URL         string `json:"url"`
	Description string `json:"description"`
	Favicon     string `json:"favicon"`
	OrderSort   int    `json:"order_sort"`
	Label       string `json:"label"`
	IsPublic    int    `json:"is_public"`
	IsPinned    int    `json:"is_pinned"`
	NavVisible  int    `json:"nav_visible"`
	CreateTime  string `json:"create_time"`
	ModifyTime  string `json:"modify_time"`
}

type ExportTask struct {
	TaskID       int64  `json:"task_id"`
	Content      string `json:"content"`
	DueDate      string `json:"due_date"`
	Done         bool   `json:"done"`
	ParentID     int64  `json:"parent_id"`
	TopicID      int64  `json:"topic_id,omitempty"`
	CompleteTime string `json:"complete_time"`
	CreateTime   string `json:"create_time"`
	ModifyTime   string `json:"modify_time"`
}

type ExportTopic struct {
	TopicID    int64                 `json:"topic_id"`
	Title      string                `json:"title"`
	Question   string                `json:"question"`
	IsPinned   bool                  `json:"is_pinned"`
	CreateTime string                `json:"create_time"`
	ModifyTime string                `json:"modify_time"`
	Summaries  []ExportTopicSummary  `json:"summaries"`
	Resources  []ExportTopicResource `json:"resources"`
	Comments   []ExportTopicComment  `json:"comments,omitempty"`
}

type ExportTopicSummary struct {
	SummaryID   int64  `json:"summary_id,omitempty"`
	Content     string `json:"content"`
	SummaryType string `json:"summary_type"`
	OrderSort   int    `json:"order_sort"`
	CreateTime  string `json:"create_time"`
	ModifyTime  string `json:"modify_time"`
}

type ExportTopicResource struct {
	TopicResourceID int64  `json:"topic_resource_id,omitempty"`
	ResourceType    string `json:"resource_type"`
	TargetIdentify  string `json:"target_identify"`
	TitleSnapshot   string `json:"title_snapshot"`
	DescSnapshot    string `json:"desc_snapshot"`
	OrderSort       int    `json:"order_sort"`
	CreateTime      string `json:"create_time"`
}

type ExportTopicComment struct {
	CommentID       int64  `json:"comment_id,omitempty"`
	TargetType      string `json:"target_type"`
	TargetID        int64  `json:"target_id"`
	ParentCommentID int64  `json:"parent_comment_id,omitempty"`
	Content         string `json:"content"`
	CreateTime      string `json:"create_time"`
	ModifyTime      string `json:"modify_time"`
}

type ExportLabels struct {
	Labels    []ExportLabel    `json:"labels"`
	Relations []ExportLabelRel `json:"relations"`
}

type ExportLabel struct {
	LabelName string `json:"label_name"`
}

type ExportLabelRel struct {
	LabelName        string `json:"label_name"`
	ResourceType     string `json:"resource_type"`
	ResourceIdentify string `json:"resource_identify"`
}

type ExportFriendLink struct {
	GroupName   string `json:"group_name,omitempty"`
	GroupOrder  int    `json:"group_order,omitempty"`
	QRCode      string `json:"qr_code,omitempty"`
	Description string `json:"description,omitempty"`
	LinkName    string `json:"link_name"`
	LinkURL     string `json:"link_url"`
	SortWeight  int    `json:"sort_weight"`
	IsEnabled   int    `json:"is_enabled"`
	CreateTime  string `json:"create_time"`
	ModifyTime  string `json:"modify_time"`
}

type ExportData struct {
	Manifest    ExportManifest
	Books       []ExportBook
	Blogs       []ExportBlog
	Bookmarks   []ExportBookmark
	Tasks       []ExportTask
	Topics      []ExportTopic
	Labels      ExportLabels
	FriendLinks []ExportFriendLink
	Uploads     []ExportUpload
}

// ========== 导入数据结构 ==========

type ImportConflict struct {
	Type      string `json:"type"`
	Identify  string `json:"identify"`
	Name      string `json:"name"`
	LocalName string `json:"local_name"`
}

type ImportCheckResult struct {
	ImportID      string           `json:"import_id"`
	Manifest      ExportManifest   `json:"manifest"`
	Conflicts     []ImportConflict `json:"conflicts"`
	ImportSummary ExportStats      `json:"import_summary"`
}

type ImportResolution struct {
	Type     string `json:"type"`
	Identify string `json:"identify"`
	Strategy string `json:"strategy"`
}

type ImportExecuteRequest struct {
	ImportID       string             `json:"import_id"`
	TargetMemberID int64              `json:"target_member_id"`
	Resolutions    []ImportResolution `json:"resolutions"`
}

type ImportResult struct {
	BooksImported       int           `json:"books_imported"`
	BooksSkipped        int           `json:"books_skipped"`
	DocumentsImported   int           `json:"documents_imported"`
	BlogsImported       int           `json:"blogs_imported"`
	BlogsSkipped        int           `json:"blogs_skipped"`
	BookmarksImported   int           `json:"bookmarks_imported"`
	BookmarksRenamed    int           `json:"bookmarks_renamed"`
	TasksImported       int           `json:"tasks_imported"`
	TopicsImported      int           `json:"topics_imported"`
	LabelsImported      int           `json:"labels_imported"`
	LabelsSkipped       int           `json:"labels_skipped"`
	FriendLinksImported int           `json:"friend_links_imported"`
	UploadsImported     int           `json:"uploads_imported"`
	UploadsSkipped      int           `json:"uploads_skipped"`
	Errors              []ImportError `json:"errors,omitempty"`
}

type ImportError struct {
	Type    string `json:"type"`
	Message string `json:"message"`
}

// ========== 临时导入会话管理 ==========

type importSession struct {
	AdminID   int64
	FilePath  string
	CreatedAt time.Time
	Consumed  bool
	Data      *ExportData
}

var (
	importSessionsMu sync.Mutex
	importSessions   = make(map[string]*importSession)
)

func init() {
	// 启动时清理过期临时文件
	cleanupImportSessions()
}

func cleanupImportSessions() {
	importSessionsMu.Lock()
	defer importSessionsMu.Unlock()
	cutoff := time.Now().Add(-30 * time.Minute)
	for id, s := range importSessions {
		if s.Consumed || s.CreatedAt.Before(cutoff) {
			if s.FilePath != "" {
				_ = removeFile(s.FilePath)
			}
			delete(importSessions, id)
		}
	}
}

func removeFile(path string) error {
	return os.Remove(path)
}

func StoreImportSession(adminID int64, data *ExportData, zipPath string) string {
	id := uuid.New().String()
	importSessionsMu.Lock()
	importSessions[id] = &importSession{
		AdminID:   adminID,
		FilePath:  zipPath,
		CreatedAt: time.Now(),
		Data:      data,
	}
	importSessionsMu.Unlock()
	return id
}

func GetImportSession(id string, adminID int64) *ExportData {
	importSessionsMu.Lock()
	defer importSessionsMu.Unlock()
	s, ok := importSessions[id]
	if !ok || s.AdminID != adminID || s.Consumed {
		return nil
	}
	return s.Data
}

// GetImportSessionZipPath 取出该 session 关联的临时 zip 路径，供 ImportExecute 读 uploads/。
func GetImportSessionZipPath(id string, adminID int64) string {
	importSessionsMu.Lock()
	defer importSessionsMu.Unlock()
	s, ok := importSessions[id]
	if !ok || s.AdminID != adminID || s.Consumed {
		return ""
	}
	return s.FilePath
}

func ConsumeImportSession(id string, adminID int64) bool {
	importSessionsMu.Lock()
	defer importSessionsMu.Unlock()
	s, ok := importSessions[id]
	if !ok || s.AdminID != adminID || s.Consumed {
		return false
	}
	s.Consumed = true
	zipPath := s.FilePath
	// 延迟清理，不阻塞
	go func() {
		time.Sleep(5 * time.Second)
		importSessionsMu.Lock()
		delete(importSessions, id)
		importSessionsMu.Unlock()
		if zipPath != "" {
			_ = removeFile(zipPath)
		}
	}()
	return true
}

// ========== 导出查询 ==========

// ExportAllData 导出数据。memberID 为 0 时导出全站，非 0 时导出指定用户的数据。
func ExportAllData(memberID int64) (*ExportData, error) {
	data := &ExportData{}
	now := time.Now().Format(time.RFC3339)
	data.Manifest = ExportManifest{
		Version:    1,
		ExportTime: now,
		Source:     "bookstark",
	}

	// 书籍 + 文档
	books, err := exportBooks(memberID)
	if err != nil {
		return nil, fmt.Errorf("导出书籍失败: %w", err)
	}
	data.Books = books
	docCount := 0
	for _, b := range books {
		docCount += len(b.Documents)
	}
	data.Manifest.Stats.Documents = docCount

	// 博客
	blogs, err := exportBlogs(memberID)
	if err != nil {
		return nil, fmt.Errorf("导出博客失败: %w", err)
	}
	data.Blogs = blogs

	// 书签
	bookmarks, err := exportBookmarks(memberID)
	if err != nil {
		return nil, fmt.Errorf("导出书签失败: %w", err)
	}
	data.Bookmarks = bookmarks

	// 待办
	tasks, err := exportTasks(memberID)
	if err != nil {
		return nil, fmt.Errorf("导出待办失败: %w", err)
	}
	data.Tasks = tasks

	// 专题（本体 + 小结 + 资料引用）
	topics, err := exportTopics(memberID)
	if err != nil {
		return nil, fmt.Errorf("导出专题失败: %w", err)
	}
	data.Topics = topics

	// 标签 + 关系
	labels, err := exportLabels(memberID)
	if err != nil {
		return nil, fmt.Errorf("导出标签失败: %w", err)
	}
	data.Labels = labels

	// 友链
	friendLinks, err := exportFriendLinks()
	if err != nil {
		return nil, fmt.Errorf("导出友链失败: %w", err)
	}
	data.FriendLinks = friendLinks

	data.Manifest.Stats.Books = len(data.Books)
	data.Manifest.Stats.Blogs = len(data.Blogs)
	data.Manifest.Stats.Bookmarks = len(data.Bookmarks)
	data.Manifest.Stats.Tasks = len(data.Tasks)
	data.Manifest.Stats.Topics = len(data.Topics)
	data.Manifest.Stats.Labels = len(data.Labels.Labels)
	data.Manifest.Stats.FriendLinks = len(data.FriendLinks)

	return data, nil
}

func exportBooks(memberID int64) ([]ExportBook, error) {
	query := "SELECT book_id, book_name, identify, order_index, description, label, is_use_first_document, create_time, COALESCE(modify_time,'') FROM md_books"
	args := []interface{}{}
	if memberID > 0 {
		query += " WHERE member_id = ?"
		args = append(args, memberID)
	}
	query += " ORDER BY book_id"
	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var books []ExportBook
	for rows.Next() {
		var b ExportBook
		var bookID int64
		if err := rows.Scan(&bookID, &b.BookName, &b.Identify, &b.OrderIndex, &b.Description, &b.Label, &b.IsUseFirstDocument, &b.CreateTime, &b.ModifyTime); err != nil {
			return nil, err
		}

		// 查询文档
		docs, err := exportDocuments(bookID)
		if err != nil {
			return nil, err
		}
		b.Documents = docs
		books = append(books, b)
	}
	return books, rows.Err()
}

func exportDocuments(bookID int64) ([]ExportDoc, error) {
	rows, err := DB.Query("SELECT document_id, document_name, identify, parent_id, order_sort, COALESCE(doc_type,'markdown'), markdown, is_open, create_time, COALESCE(modify_time,'') FROM md_documents WHERE book_id = ? ORDER BY order_sort, document_id", bookID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	type docRow struct {
		ExportDoc
		ID       int64
		ParentID int64
	}
	var allDocs []docRow
	idMap := make(map[int64]string) // id -> identify

	for rows.Next() {
		var d docRow
		if err := rows.Scan(&d.ID, &d.DocumentName, &d.Identify, &d.ParentID, &d.OrderSort, &d.DocType, &d.Markdown, &d.IsOpen, &d.CreateTime, &d.ModifyTime); err != nil {
			return nil, err
		}
		idMap[d.ID] = d.Identify
		allDocs = append(allDocs, d)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	result := make([]ExportDoc, 0, len(allDocs))
	for _, d := range allDocs {
		ed := d.ExportDoc
		if d.ParentID > 0 {
			ed.ParentIdentify = idMap[d.ParentID]
		}
		result = append(result, ed)
	}
	return result, nil
}

func exportBlogs(memberID int64) ([]ExportBlog, error) {
	query := "SELECT blog_title, blog_identify, blog_content, COALESCE(blog_desc,''), password, COALESCE(blog_type,'article'), COALESCE(visibility,0), COALESCE(is_pinned,0), COALESCE(pin_order,0), version, create_time, COALESCE(modify_time,'') FROM md_blogs"
	args := []interface{}{}
	if memberID > 0 {
		query += " WHERE member_id = ?"
		args = append(args, memberID)
	}
	query += " ORDER BY blog_id"
	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var blogs []ExportBlog
	for rows.Next() {
		var b ExportBlog
		if err := rows.Scan(&b.BlogTitle, &b.BlogIdentify, &b.BlogContent, &b.BlogDesc, &b.Password, &b.BlogType, &b.Visibility, &b.IsPinned, &b.PinOrder, &b.Version, &b.CreateTime, &b.ModifyTime); err != nil {
			return nil, err
		}
		blogs = append(blogs, b)
	}
	return blogs, rows.Err()
}

func exportBookmarks(memberID int64) ([]ExportBookmark, error) {
	query := "SELECT title, url, description, favicon, order_sort, label, is_public, is_pinned, nav_visible, create_time, COALESCE(modify_time,'') FROM md_bookmark"
	args := []interface{}{}
	if memberID > 0 {
		query += " WHERE member_id = ?"
		args = append(args, memberID)
	}
	query += " ORDER BY bookmark_id"
	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var bookmarks []ExportBookmark
	for rows.Next() {
		var b ExportBookmark
		var isPublic, isPinned, navVisible int
		if err := rows.Scan(&b.Title, &b.URL, &b.Description, &b.Favicon, &b.OrderSort, &b.Label, &isPublic, &isPinned, &navVisible, &b.CreateTime, &b.ModifyTime); err != nil {
			return nil, err
		}
		b.IsPublic = isPublic
		b.IsPinned = isPinned
		b.NavVisible = navVisible
		bookmarks = append(bookmarks, b)
	}
	return bookmarks, rows.Err()
}

func exportTasks(memberID int64) ([]ExportTask, error) {
	query := "SELECT task_id, content, due_date, done, parent_id, topic_id, complete_time, create_time, modify_time FROM md_tasks"
	args := []interface{}{}
	if memberID > 0 {
		query += " WHERE member_id = ?"
		args = append(args, memberID)
	}
	query += " ORDER BY parent_id ASC, task_id ASC"
	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tasks []ExportTask
	for rows.Next() {
		var t ExportTask
		var done int
		var complete sql.NullTime
		var createTime, modifyTime time.Time
		if err := rows.Scan(&t.TaskID, &t.Content, &t.DueDate, &done, &t.ParentID, &t.TopicID, &complete, &createTime, &modifyTime); err != nil {
			return nil, err
		}
		t.Done = done == 1
		if complete.Valid {
			t.CompleteTime = complete.Time.Format(time.RFC3339)
		}
		t.CreateTime = createTime.Format(time.RFC3339)
		t.ModifyTime = modifyTime.Format(time.RFC3339)
		tasks = append(tasks, t)
	}
	return tasks, rows.Err()
}

func exportTopics(memberID int64) ([]ExportTopic, error) {
	query := "SELECT topic_id, title, question, is_pinned, create_time, modify_time FROM md_topics"
	args := []interface{}{}
	if memberID > 0 {
		query += " WHERE member_id = ?"
		args = append(args, memberID)
	}
	query += " ORDER BY topic_id"
	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var topics []ExportTopic
	for rows.Next() {
		var topic ExportTopic
		var pinned int
		var createTime, modifyTime time.Time
		if err := rows.Scan(&topic.TopicID, &topic.Title, &topic.Question, &pinned, &createTime, &modifyTime); err != nil {
			return nil, err
		}
		topic.IsPinned = pinned == 1
		topic.CreateTime = createTime.Format(time.RFC3339)
		topic.ModifyTime = modifyTime.Format(time.RFC3339)

		summaries, err := exportTopicSummaries(topic.TopicID)
		if err != nil {
			return nil, err
		}
		resources, err := exportTopicResources(topic.TopicID)
		if err != nil {
			return nil, err
		}
		comments, err := exportTopicComments(topic.TopicID)
		if err != nil {
			return nil, err
		}
		topic.Summaries = summaries
		topic.Resources = resources
		topic.Comments = comments
		topics = append(topics, topic)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return topics, nil
}

func exportTopicSummaries(topicID int64) ([]ExportTopicSummary, error) {
	rows, err := DB.Query(`
		SELECT summary_id, content, summary_type, order_sort, create_time, modify_time
		FROM md_topic_summaries
		WHERE topic_id = ?
		ORDER BY order_sort ASC, summary_id ASC`, topicID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var summaries []ExportTopicSummary
	for rows.Next() {
		var item ExportTopicSummary
		var createTime, modifyTime time.Time
		if err := rows.Scan(&item.SummaryID, &item.Content, &item.SummaryType, &item.OrderSort, &createTime, &modifyTime); err != nil {
			return nil, err
		}
		item.CreateTime = createTime.Format(time.RFC3339)
		item.ModifyTime = modifyTime.Format(time.RFC3339)
		summaries = append(summaries, item)
	}
	return summaries, rows.Err()
}

func exportTopicResources(topicID int64) ([]ExportTopicResource, error) {
	rows, err := DB.Query(`
		SELECT topic_resource_id, resource_type, target_id, title_snapshot, desc_snapshot, order_sort, create_time
		FROM md_topic_resources
		WHERE topic_id = ?
		ORDER BY order_sort ASC, topic_resource_id ASC`, topicID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var resources []ExportTopicResource
	for rows.Next() {
		var item ExportTopicResource
		var targetID int64
		var createTime time.Time
		if err := rows.Scan(&item.TopicResourceID, &item.ResourceType, &targetID, &item.TitleSnapshot, &item.DescSnapshot, &item.OrderSort, &createTime); err != nil {
			return nil, err
		}
		identify, err := exportTopicResourceTargetIdentify(item.ResourceType, targetID)
		if err != nil {
			log.Printf("exportTopicResources: 跳过失效专题资料 topic=%d type=%s target=%d: %v", topicID, item.ResourceType, targetID, err)
			continue
		}
		item.TargetIdentify = identify
		item.CreateTime = createTime.Format(time.RFC3339)
		resources = append(resources, item)
	}
	return resources, rows.Err()
}

func exportTopicComments(topicID int64) ([]ExportTopicComment, error) {
	rows, err := DB.Query(`
		SELECT comment_id, target_type, target_id, parent_comment_id, content, create_time, modify_time
		FROM md_topic_comments
		WHERE topic_id = ?
		ORDER BY create_time ASC, comment_id ASC`, topicID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var comments []ExportTopicComment
	for rows.Next() {
		var item ExportTopicComment
		var createTime, modifyTime time.Time
		if err := rows.Scan(&item.CommentID, &item.TargetType, &item.TargetID, &item.ParentCommentID, &item.Content, &createTime, &modifyTime); err != nil {
			return nil, err
		}
		item.CreateTime = createTime.Format(time.RFC3339)
		item.ModifyTime = modifyTime.Format(time.RFC3339)
		comments = append(comments, item)
	}
	return comments, rows.Err()
}

func exportTopicResourceTargetIdentify(resourceType string, targetID int64) (string, error) {
	switch resourceType {
	case TopicResourceDocument:
		var docIdentify, bookIdentify string
		err := DB.QueryRow(`
			SELECT d.identify, b.identify
			FROM md_documents d JOIN md_books b ON b.book_id = d.book_id
			WHERE d.document_id = ?`, targetID).Scan(&docIdentify, &bookIdentify)
		if err != nil {
			return "", err
		}
		return bookIdentify + "/" + docIdentify, nil
	case TopicResourceNote, TopicResourceArticle:
		var identify string
		if err := DB.QueryRow("SELECT blog_identify FROM md_blogs WHERE blog_id = ?", targetID).Scan(&identify); err != nil {
			return "", err
		}
		return identify, nil
	case TopicResourceBookmark:
		var url string
		if err := DB.QueryRow("SELECT url FROM md_bookmark WHERE bookmark_id = ?", targetID).Scan(&url); err != nil {
			return "", err
		}
		return url, nil
	case TopicResourceTask:
		return strconv.FormatInt(targetID, 10), nil
	default:
		return "", fmt.Errorf("不支持的专题资料类型: %s", resourceType)
	}
}

func exportLabels(memberID int64) (ExportLabels, error) {
	result := ExportLabels{}

	// 标签（全量导出，标签是全局共享的）
	labelRows, err := DB.Query("SELECT label_name FROM md_label ORDER BY label_id")
	if err != nil {
		return result, err
	}
	defer labelRows.Close()
	for labelRows.Next() {
		var l ExportLabel
		if err := labelRows.Scan(&l.LabelName); err != nil {
			return result, err
		}
		result.Labels = append(result.Labels, l)
	}

	// 标签关系
	relQuery := "SELECT l.label_name, r.relation_type, r.resource_id FROM md_label_relation r JOIN md_label l ON r.label_id = l.label_id"
	var relArgs []interface{}
	if memberID > 0 {
		// 只导出该用户资源关联的标签关系
		relQuery += " WHERE (" +
			"(r.relation_type = 'book' AND r.resource_id IN (SELECT book_id FROM md_books WHERE member_id = ?))" +
			" OR (r.relation_type = 'blog' AND r.resource_id IN (SELECT blog_id FROM md_blogs WHERE member_id = ?))" +
			" OR (r.relation_type = 'bookmark' AND r.resource_id IN (SELECT bookmark_id FROM md_bookmark WHERE member_id = ?))" +
			" OR (r.relation_type = 'document' AND r.resource_id IN (SELECT d.document_id FROM md_documents d JOIN md_books b ON d.book_id = b.book_id WHERE b.member_id = ?))" +
			")"
		relArgs = append(relArgs, memberID, memberID, memberID, memberID)
	}
	relQuery += " ORDER BY r.id"
	relRows, err := DB.Query(relQuery, relArgs...)
	if err != nil {
		return result, err
	}
	defer relRows.Close()

	for relRows.Next() {
		var rel ExportLabelRel
		var resourceID int64
		if err := relRows.Scan(&rel.LabelName, &rel.ResourceType, &resourceID); err != nil {
			return result, err
		}
		// 根据 resource_type 查找 identify
		identify, err := getResourceIdentify(rel.ResourceType, resourceID)
		if err != nil || identify == "" {
			continue
		}
		rel.ResourceIdentify = identify
		result.Relations = append(result.Relations, rel)
	}
	return result, relRows.Err()
}

func getResourceIdentify(relationType string, resourceID int64) (string, error) {
	switch relationType {
	case "book":
		var identify string
		err := DB.QueryRow("SELECT identify FROM md_books WHERE book_id = ?", resourceID).Scan(&identify)
		return identify, err
	case "blog":
		var identify string
		err := DB.QueryRow("SELECT blog_identify FROM md_blogs WHERE blog_id = ?", resourceID).Scan(&identify)
		return identify, err
	case "bookmark":
		var url string
		err := DB.QueryRow("SELECT url FROM md_bookmark WHERE bookmark_id = ?", resourceID).Scan(&url)
		return url, err
	case "document":
		// 文档使用 book_identify/document_identify 格式
		var docIdentify string
		var bookID int64
		err := DB.QueryRow("SELECT identify, book_id FROM md_documents WHERE document_id = ?", resourceID).Scan(&docIdentify, &bookID)
		if err != nil {
			return "", err
		}
		var bookIdentify string
		err = DB.QueryRow("SELECT identify FROM md_books WHERE book_id = ?", bookID).Scan(&bookIdentify)
		if err != nil {
			return "", err
		}
		return bookIdentify + "/" + docIdentify, nil
	}
	return "", fmt.Errorf("unknown relation type: %s", relationType)
}

func exportFriendLinks() ([]ExportFriendLink, error) {
	rows, err := DB.Query(`SELECT f.link_name, f.link_url, f.sort_weight, f.is_enabled, f.create_time, COALESCE(f.modify_time,''), COALESCE(d.group_name,''), COALESCE(d.group_order,0), COALESCE(d.qr_code,''), COALESCE(d.description,'') FROM md_friend_links f LEFT JOIN md_friend_link_details d ON f.link_id=d.link_id ORDER BY f.sort_weight, f.link_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var links []ExportFriendLink
	for rows.Next() {
		var l ExportFriendLink
		if err := rows.Scan(&l.LinkName, &l.LinkURL, &l.SortWeight, &l.IsEnabled, &l.CreateTime, &l.ModifyTime, &l.GroupName, &l.GroupOrder, &l.QRCode, &l.Description); err != nil {
			return nil, err
		}
		links = append(links, l)
	}
	return links, rows.Err()
}

// ========== ZIP 安全验证 ==========

var allowedZipEntries = map[string]bool{
	"manifest.json":     true,
	"books.json":        true,
	"blogs.json":        true,
	"bookmarks.json":    true,
	"tasks.json":        true,
	"topics.json":       true,
	"labels.json":       true,
	"friend_links.json": true,
	"uploads.json":      true,
}

// 单个上传文件大小上限（200MB），与导入 zip 的元数据条目限制保持一致。
const importUploadFileLimit = 200 * 1024 * 1024

func ValidateZipEntries(zipReader *zip.Reader) error {
	for _, f := range zipReader.File {
		if strings.Contains(f.Name, "..") || strings.HasPrefix(f.Name, "/") {
			return fmt.Errorf("ZIP 包含不安全的路径: %s", f.Name)
		}
		// 允许的元数据 JSON
		if allowedZipEntries[f.Name] {
			if f.UncompressedSize64 > 200*1024*1024 {
				return fmt.Errorf("文件 %s 解压后过大（超过 200MB）", f.Name)
			}
			continue
		}
		// 允许 uploads/ 下的任意二进制文件（hash 命名，导出时是固定结构）
		if strings.HasPrefix(f.Name, "uploads/") {
			if f.UncompressedSize64 > importUploadFileLimit {
				return fmt.Errorf("上传文件 %s 解压后过大（超过 200MB）", f.Name)
			}
			continue
		}
		return fmt.Errorf("ZIP 包含不认识的文件: %s", f.Name)
	}
	return nil
}

// ========== 导入数据解析 ==========

func ParseImportData(zipReader *zip.Reader) (*ExportData, error) {
	if err := ValidateZipEntries(zipReader); err != nil {
		return nil, err
	}

	data := &ExportData{}

	fileMap := make(map[string]*zip.File)
	for _, f := range zipReader.File {
		fileMap[f.Name] = f
	}

	// manifest.json
	if f, ok := fileMap["manifest.json"]; ok {
		if err := readZipJSON(f, &data.Manifest); err != nil {
			return nil, fmt.Errorf("解析 manifest.json 失败: %w", err)
		}
		if data.Manifest.Version > 1 {
			return nil, fmt.Errorf("不支持的导出格式版本: %d", data.Manifest.Version)
		}
	} else {
		return nil, fmt.Errorf("缺少 manifest.json")
	}

	// books.json
	if f, ok := fileMap["books.json"]; ok {
		if err := readZipJSON(f, &data.Books); err != nil {
			return nil, fmt.Errorf("解析 books.json 失败: %w", err)
		}
	}

	// blogs.json
	if f, ok := fileMap["blogs.json"]; ok {
		if err := readZipJSON(f, &data.Blogs); err != nil {
			return nil, fmt.Errorf("解析 blogs.json 失败: %w", err)
		}
	}

	// bookmarks.json
	if f, ok := fileMap["bookmarks.json"]; ok {
		if err := readZipJSON(f, &data.Bookmarks); err != nil {
			return nil, fmt.Errorf("解析 bookmarks.json 失败: %w", err)
		}
	}

	// tasks.json（可选，旧版本导出包不含此项）
	if f, ok := fileMap["tasks.json"]; ok {
		if err := readZipJSON(f, &data.Tasks); err != nil {
			return nil, fmt.Errorf("解析 tasks.json 失败: %w", err)
		}
	}

	// topics.json（可选，旧版本导出包不含此项）
	if f, ok := fileMap["topics.json"]; ok {
		if err := readZipJSON(f, &data.Topics); err != nil {
			return nil, fmt.Errorf("解析 topics.json 失败: %w", err)
		}
	}

	// labels.json
	if f, ok := fileMap["labels.json"]; ok {
		if err := readZipJSON(f, &data.Labels); err != nil {
			return nil, fmt.Errorf("解析 labels.json 失败: %w", err)
		}
	}

	// friend_links.json
	if f, ok := fileMap["friend_links.json"]; ok {
		if err := readZipJSON(f, &data.FriendLinks); err != nil {
			return nil, fmt.Errorf("解析 friend_links.json 失败: %w", err)
		}
	}

	// uploads.json（可选，旧版本导出包不含此项）
	if f, ok := fileMap["uploads.json"]; ok {
		if err := readZipJSON(f, &data.Uploads); err != nil {
			return nil, fmt.Errorf("解析 uploads.json 失败: %w", err)
		}
	}

	return data, nil
}

func readZipJSON(f *zip.File, v interface{}) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	// 限制读取大小
	limited := io.LimitReader(rc, 200*1024*1024)
	return json.NewDecoder(limited).Decode(v)
}

// ========== 导入数据验证 ==========

var identifyRegex = regexp.MustCompile(`^[^\s]+$`)

func ValidateImportData(data *ExportData) error {
	for _, b := range data.Books {
		if strings.TrimSpace(b.BookName) == "" {
			return fmt.Errorf("书籍名称不能为空")
		}
		if strings.TrimSpace(b.Identify) == "" {
			return fmt.Errorf("书籍 identify 不能为空")
		}
		for _, d := range b.Documents {
			if strings.TrimSpace(d.DocumentName) == "" {
				return fmt.Errorf("文档名称不能为空")
			}
			if strings.TrimSpace(d.Identify) == "" {
				return fmt.Errorf("文档 identify 不能为空")
			}
		}
	}
	for _, b := range data.Blogs {
		if strings.TrimSpace(b.BlogTitle) == "" {
			return fmt.Errorf("博客标题不能为空")
		}
		if strings.TrimSpace(b.BlogIdentify) == "" {
			return fmt.Errorf("博客 identify 不能为空")
		}
	}
	for _, b := range data.Bookmarks {
		if strings.TrimSpace(b.URL) == "" {
			return fmt.Errorf("书签 URL 不能为空")
		}
	}
	for _, t := range data.Tasks {
		if strings.TrimSpace(t.Content) == "" {
			return fmt.Errorf("待办内容不能为空")
		}
	}
	for _, topic := range data.Topics {
		if strings.TrimSpace(topic.Title) == "" {
			return fmt.Errorf("专题标题不能为空")
		}
		for _, summary := range topic.Summaries {
			if strings.TrimSpace(summary.Content) == "" {
				return fmt.Errorf("专题小结内容不能为空")
			}
			if !ValidTopicSummaryType(summary.SummaryType) {
				return fmt.Errorf("不支持的专题小结类型: %s", summary.SummaryType)
			}
		}
		for _, resource := range topic.Resources {
			if !ValidTopicResourceType(resource.ResourceType) {
				return fmt.Errorf("不支持的专题资料类型: %s", resource.ResourceType)
			}
		}
	}
	for _, l := range data.Labels.Labels {
		if strings.TrimSpace(l.LabelName) == "" {
			return fmt.Errorf("标签名称不能为空")
		}
	}
	return nil
}

// ========== 冲突检测 ==========

func ImportCheckData(data *ExportData, targetMemberID int64) (*ImportCheckResult, error) {
	result := &ImportCheckResult{
		Manifest: data.Manifest,
	}

	// 统计
	result.ImportSummary = ExportStats{
		Books:       len(data.Books),
		Blogs:       len(data.Blogs),
		Bookmarks:   len(data.Bookmarks),
		Tasks:       len(data.Tasks),
		Topics:      len(data.Topics),
		Labels:      len(data.Labels.Labels),
		FriendLinks: len(data.FriendLinks),
		Uploads:     len(data.Uploads),
	}
	docCount := 0
	for _, b := range data.Books {
		docCount += len(b.Documents)
	}
	result.ImportSummary.Documents = docCount

	// 书籍冲突
	for _, b := range data.Books {
		var localName string
		err := DB.QueryRow("SELECT book_name FROM md_books WHERE identify = ?", b.Identify).Scan(&localName)
		if err == nil {
			result.Conflicts = append(result.Conflicts, ImportConflict{
				Type:      "book",
				Identify:  b.Identify,
				Name:      b.BookName,
				LocalName: localName,
			})
		}
	}

	// 博客冲突
	for _, b := range data.Blogs {
		var localName string
		err := DB.QueryRow("SELECT blog_title FROM md_blogs WHERE blog_identify = ?", b.BlogIdentify).Scan(&localName)
		if err == nil {
			result.Conflicts = append(result.Conflicts, ImportConflict{
				Type:      "blog",
				Identify:  b.BlogIdentify,
				Name:      b.BlogTitle,
				LocalName: localName,
			})
		}
	}

	// 书签冲突
	for _, b := range data.Bookmarks {
		var localTitle string
		err := DB.QueryRow("SELECT title FROM md_bookmark WHERE url = ? AND member_id = ?", b.URL, targetMemberID).Scan(&localTitle)
		if err == nil {
			result.Conflicts = append(result.Conflicts, ImportConflict{
				Type:      "bookmark",
				Identify:  b.URL,
				Name:      b.Title,
				LocalName: localTitle,
			})
		}
	}

	// 标签冲突
	for _, l := range data.Labels.Labels {
		var exists int
		err := DB.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_name = ?", l.LabelName).Scan(&exists)
		if err == nil && exists > 0 {
			result.Conflicts = append(result.Conflicts, ImportConflict{
				Type:      "label",
				Identify:  l.LabelName,
				Name:      l.LabelName,
				LocalName: l.LabelName,
			})
		}
	}

	result.ImportSummary.FriendLinks = len(data.FriendLinks)

	return result, nil
}

// ========== 导入执行 ==========

// ImportExecuteData 执行导入。zipPath 可选：传非空字符串时会把 zip 内 uploads/
// 下的二进制文件写回 data/uploads/，并把对应 md_uploads 元数据 upsert 到表里。
// 传空字符串则与旧版行为相同（不处理 uploads，老 zip 兼容）。
func ImportExecuteData(data *ExportData, targetMemberID int64, resolutions []ImportResolution, zipPath string) (*ImportResult, error) {
	result := &ImportResult{}

	// 构建冲突解决映射
	resolutionMap := make(map[string]string) // "type:identify" -> strategy
	for _, r := range resolutions {
		key := r.Type + ":" + r.Identify
		resolutionMap[key] = r.Strategy
	}

	getStrategy := func(typeName, identify string) string {
		return resolutionMap[typeName+":"+identify]
	}

	// 1. 导入标签
	labelIDMap, err := importLabels(data, targetMemberID, getStrategy, result)
	if err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "label", Message: err.Error()})
	}

	// 2. 导入友链
	if err := importFriendLinks(data, targetMemberID, result); err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "friend_link", Message: err.Error()})
	}

	// 3. 导入书籍+文档
	bookIDMap, docIDMap, err := importBooks(data, targetMemberID, getStrategy, result)
	if err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "book", Message: err.Error()})
	}

	// 4. 导入博客
	blogIDMap, err := importBlogs(data, targetMemberID, getStrategy, result)
	if err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "blog", Message: err.Error()})
	}

	// 5. 导入书签
	bookmarkIDMap, err := importBookmarks(data, targetMemberID, getStrategy, result)
	if err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "bookmark", Message: err.Error()})
	}

	// 6. 导入专题本体和小结
	topicIDMap, topicSummaryIDMap, err := importTopics(data, targetMemberID, result)
	if err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "topic", Message: err.Error()})
	}

	// 7. 导入待办
	taskIDMap, err := importTasks(data, targetMemberID, topicIDMap, result)
	if err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "task", Message: err.Error()})
	}

	// 8. 导入专题资料引用
	topicResourceIDMap, err := importTopicResources(data, topicIDMap, docIDMap, blogIDMap, bookmarkIDMap, taskIDMap, result)
	if err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "topic_resource", Message: err.Error()})
	}

	// 9. 导入专题评论
	if err := importTopicComments(data, targetMemberID, topicIDMap, topicSummaryIDMap, topicResourceIDMap, taskIDMap); err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "topic_comment", Message: err.Error()})
	}

	// 10. 导入标签关系
	if err := importLabelRelations(data, labelIDMap, bookIDMap, blogIDMap, bookmarkIDMap, docIDMap); err != nil {
		result.Errors = append(result.Errors, ImportError{Type: "label_relation", Message: err.Error()})
	}

	// 10. 同步标签字段
	syncAllLabelFields(bookIDMap, bookmarkIDMap)

	// 11. 导入 uploads（文件本体 + md_uploads 元数据）
	if zipPath != "" && len(data.Uploads) > 0 {
		if err := importUploadsFromZip(zipPath, data.Uploads, targetMemberID, result); err != nil {
			result.Errors = append(result.Errors, ImportError{Type: "upload", Message: err.Error()})
		}
	}

	return result, nil
}

// importUploadsFromZip 把 zip 内 uploads/<storage_path> 写回 data/uploads/<storage_path>，
// 同时 upsert md_uploads 元数据。已存在同 hash 的记录则跳过（不覆盖现有文件）。
func importUploadsFromZip(zipPath string, uploads []ExportUpload, targetMemberID int64, result *ImportResult) error {
	zr, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("打开导入 zip 失败: %w", err)
	}
	defer zr.Close()

	zipFiles := make(map[string]*zip.File, len(zr.File))
	for _, f := range zr.File {
		zipFiles[f.Name] = f
	}

	if err := os.MkdirAll(UploadBaseDir, 0755); err != nil {
		return fmt.Errorf("创建 uploads 目录失败: %w", err)
	}

	extractOne := func(rel string) error {
		if rel == "" {
			return nil
		}
		zf, ok := zipFiles["uploads/"+rel]
		if !ok {
			return nil
		}
		dst := UploadBaseDir + "/" + rel
		// 同名已存在则跳过；这里以"先到先得"为准，避免覆盖远端实例的数据
		if _, err := os.Stat(dst); err == nil {
			return nil
		}
		if err := os.MkdirAll(filepathDir(dst), 0755); err != nil {
			return fmt.Errorf("mkdir %s: %w", filepathDir(dst), err)
		}
		rc, err := zf.Open()
		if err != nil {
			return fmt.Errorf("打开 zip 内 %s: %w", zf.Name, err)
		}
		defer rc.Close()
		out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
		if err != nil {
			return fmt.Errorf("创建 %s: %w", dst, err)
		}
		if _, err := io.Copy(out, rc); err != nil {
			out.Close()
			_ = os.Remove(dst)
			return fmt.Errorf("写入 %s: %w", dst, err)
		}
		return out.Close()
	}

	for _, u := range uploads {
		// 元数据 dedup：同 hash 已存在 → 跳过
		existing, _ := GetUploadByHash(u.FileHash)
		if existing != nil {
			result.UploadsSkipped++
			continue
		}
		if err := extractOne(u.StoragePath); err != nil {
			result.Errors = append(result.Errors, ImportError{Type: "upload", Message: err.Error()})
			continue
		}
		if err := extractOne(u.ThumbPath); err != nil {
			result.Errors = append(result.Errors, ImportError{Type: "upload", Message: err.Error()})
			// 缩略图丢失不阻塞主流程
		}
		ct, _ := time.Parse(time.RFC3339, u.CreateTime)
		if ct.IsZero() {
			ct = time.Now()
		}
		row := &Upload{
			FileName:    u.FileName,
			StoragePath: u.StoragePath,
			FileHash:    u.FileHash,
			FileSize:    u.FileSize,
			MimeType:    u.MimeType,
			Width:       u.Width,
			Height:      u.Height,
			ThumbPath:   u.ThumbPath,
			ThumbSize:   u.ThumbSize,
			Category:    u.Category,
			MemberID:    targetMemberID,
			CreateTime:  ct,
		}
		if _, err := InsertUpload(row); err != nil {
			result.Errors = append(result.Errors, ImportError{Type: "upload", Message: fmt.Sprintf("insert upload %s: %v", u.FileName, err)})
			continue
		}
		result.UploadsImported++
	}
	return nil
}

// filepathDir 是 path/filepath.Dir 的轻量替代，避免在文件顶部再加 import；
// uploads 路径都是 / 分隔，hash 子目录形如 "ab/cdef..."。
func filepathDir(p string) string {
	for i := len(p) - 1; i >= 0; i-- {
		if p[i] == '/' || p[i] == os.PathSeparator {
			return p[:i]
		}
	}
	return "."
}

func getResolutionStrategy(typeName, identify string, getStrategy func(string, string) string) string {
	s := getStrategy(typeName, identify)
	if s == "" {
		s = "skip" // 默认跳过
	}
	return s
}

// --- 标签导入 ---

func importLabels(data *ExportData, _ int64, getStrategy func(string, string) string, result *ImportResult) (map[string]int64, error) {
	labelIDMap := make(map[string]int64) // label_name -> new label_id

	tx, err := DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	for _, l := range data.Labels.Labels {
		strategy := getResolutionStrategy("label", l.LabelName, getStrategy)

		var existingID int64
		err := tx.QueryRow("SELECT label_id FROM md_label WHERE label_name = ?", l.LabelName).Scan(&existingID)

		if err == nil {
			// 标签已存在
			switch strategy {
			case "overwrite":
				// 删除旧标签及其关系，创建新标签
				if _, err := tx.Exec("DELETE FROM md_label_relation WHERE label_id = ?", existingID); err != nil {
					return nil, fmt.Errorf("删除标签关系失败: %w", err)
				}
				if _, err := tx.Exec("DELETE FROM md_label WHERE label_id = ?", existingID); err != nil {
					return nil, fmt.Errorf("删除标签失败: %w", err)
				}
				res, err := tx.Exec("INSERT INTO md_label (label_name) VALUES (?)", l.LabelName)
				if err != nil {
					return nil, fmt.Errorf("创建标签失败: %w", err)
				}
				newID, _ := res.LastInsertId()
				labelIDMap[l.LabelName] = newID
				result.LabelsImported++
			case "skip":
				labelIDMap[l.LabelName] = existingID
				result.LabelsSkipped++
			case "rename":
				newName := findUniqueLabelName(tx, l.LabelName+" (导入)")
				res, err := tx.Exec("INSERT INTO md_label (label_name) VALUES (?)", newName)
				if err != nil {
					return nil, fmt.Errorf("创建标签失败: %w", err)
				}
				newID, _ := res.LastInsertId()
				labelIDMap[l.LabelName] = existingID // 原名映射到已有ID
				labelIDMap[newName] = newID
				result.LabelsImported++
			}
		} else {
			// 标签不存在，直接创建
			res, err := tx.Exec("INSERT INTO md_label (label_name) VALUES (?)", l.LabelName)
			if err != nil {
				return nil, fmt.Errorf("创建标签失败: %w", err)
			}
			newID, _ := res.LastInsertId()
			labelIDMap[l.LabelName] = newID
			result.LabelsImported++
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return labelIDMap, nil
}

func findUniqueLabelName(tx *sql.Tx, baseName string) string {
	name := baseName
	for i := 2; ; i++ {
		var count int
		err := tx.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_name = ?", name).Scan(&count)
		if err != nil || count == 0 {
			return name
		}
		name = fmt.Sprintf("%s%d", baseName, i)
	}
}

// --- 友链导入 ---

func importFriendLinks(data *ExportData, adminID int64, result *ImportResult) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, fl := range data.FriendLinks {
		item := FriendLink{LinkName: fl.LinkName, LinkURL: fl.LinkURL, GroupName: fl.GroupName, GroupOrder: fl.GroupOrder, QRCode: fl.QRCode, Description: fl.Description}
		if err := item.Validate(); err != nil {
			return err
		}
		inserted, err := tx.Exec(
			"INSERT INTO md_friend_links (link_name, link_url, sort_weight, is_enabled, create_time, modify_time, created_by, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
			fl.LinkName, fl.LinkURL, fl.SortWeight, fl.IsEnabled, fl.CreateTime, fl.ModifyTime, adminID, adminID,
		)
		if err != nil {
			log.Printf("importFriendLinks: 插入友链失败: %v", err)
			continue
		}
		id, err := inserted.LastInsertId()
		if err != nil {
			return err
		}
		if _, err = tx.Exec(`INSERT INTO md_friend_link_details(link_id,group_name,group_order,qr_code,description) VALUES(?,?,?,?,?)`, id, fl.GroupName, fl.GroupOrder, fl.QRCode, fl.Description); err != nil {
			return err
		}
		result.FriendLinksImported++
	}

	return tx.Commit()
}

// --- 书籍+文档导入 ---

func importBooks(data *ExportData, targetMemberID int64, getStrategy func(string, string) string, result *ImportResult) (map[string]int64, map[string]int64, error) {
	bookIDMap := make(map[string]int64) // book_identify -> book_id
	docIDMap := make(map[string]int64)  // "book_identify/doc_identify" -> doc_id

	for _, b := range data.Books {
		strategy := getResolutionStrategy("book", b.Identify, getStrategy)

		var existingBookID int64
		err := DB.QueryRow("SELECT book_id FROM md_books WHERE identify = ?", b.Identify).Scan(&existingBookID)

		if err == nil {
			switch strategy {
			case "overwrite":
				if err := deleteBookForOverwrite(existingBookID); err != nil {
					log.Printf("importBooks: 删除书籍 %d 失败: %v", existingBookID, err)
					result.BooksSkipped++
					continue
				}
			case "skip":
				result.BooksSkipped++
				continue
			case "rename":
				b.Identify = findUniqueBookIdentify(b.Identify + "-imported")
				b.BookName = findUniqueBookName(b.BookName+" (导入)", targetMemberID)
			}
		}

		tx, err := DB.Begin()
		if err != nil {
			return nil, nil, err
		}

		bookID, err := insertBook(tx, b, targetMemberID)
		if err != nil {
			tx.Rollback()
			log.Printf("importBooks: 插入书籍失败: %v", err)
			result.BooksSkipped++
			continue
		}
		bookIDMap[b.Identify] = bookID

		// 插入文档
		identifyToID := make(map[string]int64)
		docCount := 0
		for _, d := range b.Documents {
			docID, err := insertDocument(tx, d, bookID, targetMemberID)
			if err != nil {
				log.Printf("importBooks: 插入文档失败: %v", err)
				continue
			}
			identifyToID[d.Identify] = docID
			docIDMap[b.Identify+"/"+d.Identify] = docID
			docCount++
		}

		// 更新 parent_id
		for _, d := range b.Documents {
			if d.ParentIdentify != "" {
				parentID, ok := identifyToID[d.ParentIdentify]
				if ok {
					if _, err := tx.Exec("UPDATE md_documents SET parent_id = ? WHERE document_id = ?", parentID, identifyToID[d.Identify]); err != nil {
						log.Printf("importBooks: 更新 parent_id 失败: %v", err)
					}
				}
			}
		}

		// 更新 doc_count
		if _, err := tx.Exec("UPDATE md_books SET doc_count = ? WHERE book_id = ?", docCount, bookID); err != nil {
			log.Printf("importBooks: 更新 doc_count 失败: %v", err)
		}

		if err := tx.Commit(); err != nil {
			return nil, nil, err
		}

		result.BooksImported++
		result.DocumentsImported += docCount
	}

	return bookIDMap, docIDMap, nil
}

func deleteBookForOverwrite(bookID int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// 删除文档级标签关系
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id IN (SELECT document_id FROM md_documents WHERE book_id = ?) AND relation_type = 'document'", bookID); err != nil {
		return err
	}
	// 删除书籍级标签关系
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'book'", bookID); err != nil {
		return err
	}
	// 删除文档分享
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'document' AND target_id IN (SELECT document_id FROM md_documents WHERE book_id = ?)", bookID); err != nil {
		return err
	}
	// 删除书籍分享
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'book' AND target_id = ?", bookID); err != nil {
		return err
	}
	// 删除文档
	if _, err := tx.Exec("DELETE FROM md_documents WHERE book_id = ?", bookID); err != nil {
		return err
	}
	// 删除书籍
	if _, err := tx.Exec("DELETE FROM md_books WHERE book_id = ?", bookID); err != nil {
		return err
	}
	return tx.Commit()
}

func findUniqueBookIdentify(base string) string {
	name := base
	for i := 2; ; i++ {
		var count int
		err := DB.QueryRow("SELECT COUNT(*) FROM md_books WHERE identify = ?", name).Scan(&count)
		if err != nil || count == 0 {
			return name
		}
		name = fmt.Sprintf("%s-%d", base, i)
	}
}

func findUniqueBookName(base string, memberID int64) string {
	name := base
	for i := 2; ; i++ {
		var count int
		err := DB.QueryRow("SELECT COUNT(*) FROM md_books WHERE book_name = ? AND member_id = ?", name, memberID).Scan(&count)
		if err != nil || count == 0 {
			return name
		}
		name = fmt.Sprintf("%s%d", base, i)
	}
}

func insertBook(tx *sql.Tx, b ExportBook, memberID int64) (int64, error) {
	now := time.Now()
	result, err := tx.Exec(
		"INSERT INTO md_books (book_name, identify, description, label, order_index, is_use_first_document, member_id, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
		b.BookName, b.Identify, b.Description, b.Label, b.OrderIndex, b.IsUseFirstDocument, memberID, now, now,
	)
	if err != nil {
		return 0, err
	}
	return result.LastInsertId()
}

func insertDocument(tx *sql.Tx, d ExportDoc, bookID, memberID int64) (int64, error) {
	docType := d.DocType
	if docType == "" {
		docType = "markdown"
	}
	now := time.Now()
	result, err := tx.Exec(
		"INSERT INTO md_documents (document_name, identify, book_id, parent_id, order_sort, markdown, doc_type, member_id, create_time, modify_time, modify_at, is_open) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, 0, ?)",
		d.DocumentName, d.Identify, bookID, d.OrderSort, d.Markdown, docType, memberID, now, now, d.IsOpen,
	)
	if err != nil {
		return 0, err
	}
	return result.LastInsertId()
}

// --- 博客导入 ---

func importBlogs(data *ExportData, targetMemberID int64, getStrategy func(string, string) string, result *ImportResult) (map[string]int64, error) {
	blogIDMap := make(map[string]int64)

	tx, err := DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	for _, b := range data.Blogs {
		strategy := getResolutionStrategy("blog", b.BlogIdentify, getStrategy)

		var existingBlogID int64
		err := DB.QueryRow("SELECT blog_id FROM md_blogs WHERE blog_identify = ?", b.BlogIdentify).Scan(&existingBlogID)

		if err == nil {
			switch strategy {
			case "overwrite":
				// 删除关联数据
				if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'blog'", existingBlogID); err != nil {
					log.Printf("importBlogs: 删除标签关系失败: %v", err)
				}
				if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'blog' AND target_id = ?", existingBlogID); err != nil {
					log.Printf("importBlogs: 删除分享失败: %v", err)
				}
				if _, err := tx.Exec("DELETE FROM md_blogs WHERE blog_id = ?", existingBlogID); err != nil {
					log.Printf("importBlogs: 删除博客失败: %v", err)
					result.BlogsSkipped++
					continue
				}
			case "skip":
				result.BlogsSkipped++
				continue
			case "rename":
				b.BlogIdentify = findUniqueBlogIdentify(b.BlogIdentify + "-imported")
				b.BlogTitle = findUniqueBlogTitle(b.BlogTitle+" (导入)", targetMemberID)
			}
		}

		now := time.Now().Format("2006-01-02 15:04:05")
		version := 1
		if strategy == "overwrite" {
			version = b.Version
		}
		result2, err := tx.Exec(
			"INSERT INTO md_blogs (blog_title, blog_identify, member_id, blog_content, blog_desc, password, modify_time, create_time, version, blog_type, visibility, is_pinned, pin_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			b.BlogTitle, b.BlogIdentify, targetMemberID, b.BlogContent, strings.TrimSpace(b.BlogDesc), b.Password, now, now, version, b.BlogType, b.Visibility, b.IsPinned, b.PinOrder,
		)
		if err != nil {
			log.Printf("importBlogs: 插入博客失败: %v", err)
			result.BlogsSkipped++
			continue
		}
		blogID, _ := result2.LastInsertId()
		blogIDMap[b.BlogIdentify] = blogID
		result.BlogsImported++
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return blogIDMap, nil
}

func findUniqueBlogIdentify(base string) string {
	name := base
	for i := 2; ; i++ {
		var count int
		err := DB.QueryRow("SELECT COUNT(*) FROM md_blogs WHERE blog_identify = ?", name).Scan(&count)
		if err != nil || count == 0 {
			return name
		}
		name = fmt.Sprintf("%s-%d", base, i)
	}
}

func findUniqueBlogTitle(base string, memberID int64) string {
	name := base
	for i := 2; ; i++ {
		var count int
		err := DB.QueryRow("SELECT COUNT(*) FROM md_blogs WHERE blog_title = ? AND member_id = ?", name, memberID).Scan(&count)
		if err != nil || count == 0 {
			return name
		}
		name = fmt.Sprintf("%s%d", base, i)
	}
}

// --- 书签导入 ---

func importBookmarks(data *ExportData, targetMemberID int64, getStrategy func(string, string) string, result *ImportResult) (map[string]int64, error) {
	bookmarkIDMap := make(map[string]int64) // url -> bookmark_id

	tx, err := DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	for _, b := range data.Bookmarks {
		strategy := getResolutionStrategy("bookmark", b.URL, getStrategy)

		var existingID int64
		err := DB.QueryRow("SELECT bookmark_id FROM md_bookmark WHERE url = ? AND member_id = ?", b.URL, targetMemberID).Scan(&existingID)

		if err == nil {
			switch strategy {
			case "overwrite":
				// 删除关联数据
				if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'bookmark'", existingID); err != nil {
					log.Printf("importBookmarks: 删除标签关系失败: %v", err)
				}
				if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'bookmark' AND target_id = ?", existingID); err != nil {
					log.Printf("importBookmarks: 删除分享失败: %v", err)
				}
				if _, err := tx.Exec("DELETE FROM md_bookmark WHERE bookmark_id = ?", existingID); err != nil {
					log.Printf("importBookmarks: 删除书签失败: %v", err)
					continue
				}
			case "skip":
				continue
			case "rename":
				// 书签 URL 不可修改，rename 等同于 skip
				continue
			}
		}

		now := time.Now()
		res, err := tx.Exec(
			"INSERT INTO md_bookmark (title, url, description, favicon, order_sort, label, member_id, is_public, is_pinned, nav_visible, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			b.Title, b.URL, b.Description, b.Favicon, b.OrderSort, b.Label, targetMemberID, b.IsPublic, b.IsPinned, b.NavVisible, now, now,
		)
		if err != nil {
			log.Printf("importBookmarks: 插入书签失败: %v", err)
			continue
		}
		bookmarkID, _ := res.LastInsertId()
		bookmarkIDMap[b.URL] = bookmarkID
		result.BookmarksImported++
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return bookmarkIDMap, nil
}

// --- 待办导入 ---

func importTasks(data *ExportData, targetMemberID int64, topicIDMap map[int64]int64, result *ImportResult) (map[int64]int64, error) {
	idMap := make(map[int64]int64, len(data.Tasks))
	if len(data.Tasks) == 0 {
		return idMap, nil
	}
	tx, err := DB.Begin()
	if err != nil {
		return idMap, err
	}
	defer tx.Rollback()

	remaining := append([]ExportTask(nil), data.Tasks...)
	for len(remaining) > 0 {
		progressed := false
		next := remaining[:0]
		for _, t := range remaining {
			parentID := int64(0)
			if t.ParentID > 0 {
				var ok bool
				parentID, ok = idMap[t.ParentID]
				if !ok {
					next = append(next, t)
					continue
				}
			}
			done := 0
			if t.Done {
				done = 1
			}
			topicID := int64(0)
			if t.TopicID > 0 {
				topicID = topicIDMap[t.TopicID]
			}
			now := time.Now()
			createTime := parseExportTime(t.CreateTime, now)
			modifyTime := parseExportTime(t.ModifyTime, createTime)
			var complete interface{}
			if t.CompleteTime != "" {
				ct := parseExportTime(t.CompleteTime, time.Time{})
				if !ct.IsZero() {
					complete = ct
				}
			}
			res, err := tx.Exec(
				"INSERT INTO md_tasks (content, due_date, done, parent_id, topic_id, member_id, complete_time, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
				t.Content, t.DueDate, done, parentID, topicID, targetMemberID, complete, createTime, modifyTime,
			)
			if err != nil {
				log.Printf("importTasks: 插入待办失败: %v", err)
				continue
			}
			newID, _ := res.LastInsertId()
			idMap[t.TaskID] = newID
			result.TasksImported++
			progressed = true
		}
		if !progressed {
			for _, t := range next {
				done := 0
				if t.Done {
					done = 1
				}
				topicID := int64(0)
				if t.TopicID > 0 {
					topicID = topicIDMap[t.TopicID]
				}
				now := time.Now()
				createTime := parseExportTime(t.CreateTime, now)
				modifyTime := parseExportTime(t.ModifyTime, createTime)
				var complete interface{}
				if t.CompleteTime != "" {
					ct := parseExportTime(t.CompleteTime, time.Time{})
					if !ct.IsZero() {
						complete = ct
					}
				}
				res, err := tx.Exec(
					"INSERT INTO md_tasks (content, due_date, done, parent_id, topic_id, member_id, complete_time, create_time, modify_time) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?)",
					t.Content, t.DueDate, done, topicID, targetMemberID, complete, createTime, modifyTime,
				)
				if err != nil {
					log.Printf("importTasks: 插入孤立待办失败: %v", err)
					continue
				}
				newID, _ := res.LastInsertId()
				idMap[t.TaskID] = newID
				result.TasksImported++
			}
			break
		}
		remaining = next
	}
	return idMap, tx.Commit()
}

func importTopics(data *ExportData, targetMemberID int64, result *ImportResult) (map[int64]int64, map[int64]int64, error) {
	idMap := make(map[int64]int64, len(data.Topics))
	summaryIDMap := make(map[int64]int64)
	if len(data.Topics) == 0 {
		return idMap, summaryIDMap, nil
	}
	tx, err := DB.Begin()
	if err != nil {
		return idMap, summaryIDMap, err
	}
	defer tx.Rollback()

	for _, topic := range data.Topics {
		now := time.Now()
		createTime := parseExportTime(topic.CreateTime, now)
		modifyTime := parseExportTime(topic.ModifyTime, createTime)
		res, err := tx.Exec(`
			INSERT INTO md_topics (title, question, member_id, is_pinned, create_time, modify_time)
			VALUES (?, ?, ?, ?, ?, ?)`,
			strings.TrimSpace(topic.Title), strings.TrimSpace(topic.Question), targetMemberID, boolToInt(topic.IsPinned), createTime, modifyTime)
		if err != nil {
			log.Printf("importTopics: 插入专题失败: %v", err)
			continue
		}
		newTopicID, _ := res.LastInsertId()
		idMap[topic.TopicID] = newTopicID
		result.TopicsImported++

		for _, summary := range topic.Summaries {
			summaryCreate := parseExportTime(summary.CreateTime, createTime)
			summaryModify := parseExportTime(summary.ModifyTime, summaryCreate)
			res, err := tx.Exec(`
				INSERT INTO md_topic_summaries (topic_id, content, summary_type, order_sort, create_time, modify_time)
				VALUES (?, ?, ?, ?, ?, ?)`,
				newTopicID, strings.TrimSpace(summary.Content), NormalizeTopicSummaryType(summary.SummaryType), summary.OrderSort, summaryCreate, summaryModify)
			if err != nil {
				log.Printf("importTopics: 插入专题小结失败: %v", err)
			} else if summary.SummaryID > 0 {
				newSummaryID, _ := res.LastInsertId()
				summaryIDMap[summary.SummaryID] = newSummaryID
			}
		}
	}
	return idMap, summaryIDMap, tx.Commit()
}

func importTopicResources(data *ExportData, topicIDMap map[int64]int64, docIDMap, blogIDMap, bookmarkIDMap map[string]int64, taskIDMap map[int64]int64, result *ImportResult) (map[int64]int64, error) {
	resourceIDMap := make(map[int64]int64)
	if len(data.Topics) == 0 {
		return resourceIDMap, nil
	}
	tx, err := DB.Begin()
	if err != nil {
		return resourceIDMap, err
	}
	defer tx.Rollback()

	for _, topic := range data.Topics {
		newTopicID, ok := topicIDMap[topic.TopicID]
		if !ok || newTopicID == 0 {
			continue
		}
		for _, resource := range topic.Resources {
			targetID := resolveImportedTopicResourceTarget(resource, docIDMap, blogIDMap, bookmarkIDMap, taskIDMap)
			if targetID == 0 {
				continue
			}
			createTime := parseExportTime(resource.CreateTime, time.Now())
			res, err := tx.Exec(`
				INSERT OR IGNORE INTO md_topic_resources (topic_id, resource_type, target_id, title_snapshot, desc_snapshot, order_sort, create_time)
				VALUES (?, ?, ?, ?, ?, ?, ?)`,
				newTopicID, resource.ResourceType, targetID, resource.TitleSnapshot, resource.DescSnapshot, resource.OrderSort, createTime)
			if err != nil {
				log.Printf("importTopicResources: 插入专题资料失败: %v", err)
			} else if resource.TopicResourceID > 0 {
				newResourceID, _ := res.LastInsertId()
				if newResourceID == 0 {
					_ = tx.QueryRow(`SELECT topic_resource_id FROM md_topic_resources
						WHERE topic_id = ? AND resource_type = ? AND target_id = ?`,
						newTopicID, resource.ResourceType, targetID).Scan(&newResourceID)
				}
				resourceIDMap[resource.TopicResourceID] = newResourceID
			}
		}
	}
	return resourceIDMap, tx.Commit()
}

func importTopicComments(data *ExportData, targetMemberID int64, topicIDMap, summaryIDMap, resourceIDMap, taskIDMap map[int64]int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	commentIDMap := make(map[int64]int64)
	pending := make([]struct {
		topicID int64
		item    ExportTopicComment
	}, 0)
	resolveTarget := func(item ExportTopicComment) int64 {
		switch NormalizeTopicCommentTargetType(item.TargetType) {
		case TopicCommentSummary:
			return summaryIDMap[item.TargetID]
		case TopicCommentResource:
			return resourceIDMap[item.TargetID]
		case TopicCommentTask:
			return taskIDMap[item.TargetID]
		default:
			return 0
		}
	}
	insert := func(topicID int64, item ExportTopicComment, parentID int64) error {
		targetID := resolveTarget(item)
		if targetID == 0 || strings.TrimSpace(item.Content) == "" {
			return nil
		}
		createTime := parseExportTime(item.CreateTime, time.Now())
		modifyTime := parseExportTime(item.ModifyTime, createTime)
		res, err := tx.Exec(`INSERT INTO md_topic_comments
			(topic_id, target_type, target_id, member_id, parent_comment_id, content, create_time, modify_time)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			topicID, NormalizeTopicCommentTargetType(item.TargetType), targetID, targetMemberID,
			parentID, strings.TrimSpace(item.Content), createTime, modifyTime)
		if err != nil {
			return err
		}
		if item.CommentID > 0 {
			newID, _ := res.LastInsertId()
			commentIDMap[item.CommentID] = newID
		}
		return nil
	}

	for _, topic := range data.Topics {
		newTopicID := topicIDMap[topic.TopicID]
		if newTopicID == 0 {
			continue
		}
		for _, item := range topic.Comments {
			if item.ParentCommentID > 0 {
				pending = append(pending, struct {
					topicID int64
					item    ExportTopicComment
				}{newTopicID, item})
				continue
			}
			if err := insert(newTopicID, item, 0); err != nil {
				return err
			}
		}
	}
	for _, entry := range pending {
		parentID := commentIDMap[entry.item.ParentCommentID]
		if parentID == 0 {
			continue
		}
		if err := insert(entry.topicID, entry.item, parentID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func resolveImportedTopicResourceTarget(resource ExportTopicResource, docIDMap, blogIDMap, bookmarkIDMap map[string]int64, taskIDMap map[int64]int64) int64 {
	switch resource.ResourceType {
	case TopicResourceDocument:
		return docIDMap[resource.TargetIdentify]
	case TopicResourceNote, TopicResourceArticle:
		return blogIDMap[resource.TargetIdentify]
	case TopicResourceBookmark:
		return bookmarkIDMap[resource.TargetIdentify]
	case TopicResourceTask:
		oldTaskID, err := strconv.ParseInt(resource.TargetIdentify, 10, 64)
		if err != nil {
			return 0
		}
		return taskIDMap[oldTaskID]
	default:
		return 0
	}
}

func parseExportTime(raw string, fallback time.Time) time.Time {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return fallback
	}
	layouts := []string{time.RFC3339Nano, time.RFC3339, "2006-01-02 15:04:05", "2006-01-02T15:04:05Z07:00"}
	for _, layout := range layouts {
		if t, err := time.Parse(layout, raw); err == nil {
			return t
		}
	}
	return fallback
}

// --- 标签关系导入 ---

func importLabelRelations(data *ExportData, labelIDMap map[string]int64, bookIDMap map[string]int64, blogIDMap map[string]int64, bookmarkIDMap map[string]int64, docIDMap map[string]int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, rel := range data.Labels.Relations {
		labelID, ok := labelIDMap[rel.LabelName]
		if !ok {
			continue
		}

		var resourceID int64
		switch rel.ResourceType {
		case "book":
			resourceID = bookIDMap[rel.ResourceIdentify]
		case "blog":
			resourceID = blogIDMap[rel.ResourceIdentify]
		case "bookmark":
			resourceID = bookmarkIDMap[rel.ResourceIdentify]
		case "document":
			resourceID = docIDMap[rel.ResourceIdentify]
		}

		if resourceID == 0 {
			continue
		}

		if _, err := tx.Exec("INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, ?, datetime('now'))", labelID, resourceID, rel.ResourceType); err != nil {
			log.Printf("importLabelRelations: 插入标签关系失败: %v", err)
		}
	}

	return tx.Commit()
}

// --- 同步标签字段 ---

func syncAllLabelFields(bookIDMap map[string]int64, bookmarkIDMap map[string]int64) {
	for _, bookID := range bookIDMap {
		if err := SyncResourceLabelField(bookID, "book"); err != nil {
			log.Printf("syncAllLabelFields: 同步书籍标签失败 (book_id=%d): %v", bookID, err)
		}
	}
	for _, bookmarkID := range bookmarkIDMap {
		if err := SyncResourceLabelField(bookmarkID, "bookmark"); err != nil {
			log.Printf("syncAllLabelFields: 同步书签标签失败 (bookmark_id=%d): %v", bookmarkID, err)
		}
	}
}

// ========== 导出为 ZIP ==========

// WriteExportZip 流式把导出数据写到任意 io.Writer。
// 与旧的 BuildExportZip 不同，本函数不在内存里堆完整个 zip，
// 适合直接传 gin.ResponseWriter，避免 GB 级 uploads 时 OOM。
//
// 行为：
//   - JSON 元数据用默认 deflate 压缩（密度高、文本可压缩比好）。
//   - uploads/ 下的二进制（图片）用 zip.Store 不压缩，CPU 省、体积差不到 1%。
//   - includeUploads=false 时不写 uploads.json / uploads/，体积小，旧导入器也兼容。
//   - memberID > 0 时只导出该用户的 md_uploads（取自上下文：被书籍/笔记引用更精确，但
//     对单用户来说，简化为按 member_id 过滤就够了）。
func WriteExportZip(w io.Writer, data *ExportData, includeUploads bool, memberID int64) error {
	zw := zip.NewWriter(w)

	writeJSON := func(name string, v interface{}) error {
		f, err := zw.Create(name)
		if err != nil {
			return err
		}
		enc := json.NewEncoder(f)
		enc.SetIndent("", "  ")
		return enc.Encode(v)
	}

	// uploads 元数据要先准备好，才能正确填 manifest.stats.uploads
	var uploads []ExportUpload
	if includeUploads {
		var err error
		uploads, err = exportUploads(memberID)
		if err != nil {
			_ = zw.Close()
			return fmt.Errorf("查询 uploads 元数据失败: %w", err)
		}
		data.Manifest.Stats.Uploads = len(uploads)
		data.Uploads = uploads
	}

	if err := writeJSON("manifest.json", data.Manifest); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 manifest.json 失败: %w", err)
	}
	if err := writeJSON("books.json", data.Books); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 books.json 失败: %w", err)
	}
	if err := writeJSON("blogs.json", data.Blogs); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 blogs.json 失败: %w", err)
	}
	if err := writeJSON("bookmarks.json", data.Bookmarks); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 bookmarks.json 失败: %w", err)
	}
	if err := writeJSON("tasks.json", data.Tasks); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 tasks.json 失败: %w", err)
	}
	if err := writeJSON("topics.json", data.Topics); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 topics.json 失败: %w", err)
	}
	if err := writeJSON("labels.json", data.Labels); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 labels.json 失败: %w", err)
	}
	if err := writeJSON("friend_links.json", data.FriendLinks); err != nil {
		_ = zw.Close()
		return fmt.Errorf("写入 friend_links.json 失败: %w", err)
	}

	if includeUploads {
		if err := writeJSON("uploads.json", data.Uploads); err != nil {
			_ = zw.Close()
			return fmt.Errorf("写入 uploads.json 失败: %w", err)
		}
		// 物理文件 + 缩略图，已压缩格式直接 Store
		seen := make(map[string]bool, len(uploads)*2)
		copyOne := func(rel string) error {
			if rel == "" || seen[rel] {
				return nil
			}
			seen[rel] = true
			full := UploadBaseDir + "/" + rel
			f, err := os.Open(full)
			if err != nil {
				if os.IsNotExist(err) {
					log.Printf("WriteExportZip: 跳过缺失文件 %s", full)
					return nil
				}
				return fmt.Errorf("打开 %s: %w", full, err)
			}
			defer f.Close()
			fh := &zip.FileHeader{Name: "uploads/" + rel, Method: zip.Store}
			ze, err := zw.CreateHeader(fh)
			if err != nil {
				return fmt.Errorf("zip.CreateHeader %s: %w", rel, err)
			}
			if _, err := io.Copy(ze, f); err != nil {
				return fmt.Errorf("拷贝 %s: %w", rel, err)
			}
			return nil
		}
		for _, u := range uploads {
			if err := copyOne(u.StoragePath); err != nil {
				_ = zw.Close()
				return err
			}
			if err := copyOne(u.ThumbPath); err != nil {
				_ = zw.Close()
				return err
			}
		}
	}

	return zw.Close()
}

// BuildExportZip 仍然保留：把流式版本写到内存 buffer 返回，方便测试或非 HTTP 调用。
// 生产路径建议直接用 WriteExportZip 流式写响应，避免 OOM。
func BuildExportZip(data *ExportData) (*bytes.Buffer, error) {
	buf := new(bytes.Buffer)
	if err := WriteExportZip(buf, data, false, 0); err != nil {
		return nil, err
	}
	return buf, nil
}

// exportUploads 查询 md_uploads 元数据。memberID > 0 时按用户过滤，0 时全站。
func exportUploads(memberID int64) ([]ExportUpload, error) {
	query := `SELECT file_name, storage_path, file_hash, file_size, mime_type,
		width, height, COALESCE(thumb_path,''), thumb_size, category,
		create_time
		FROM md_uploads`
	args := []interface{}{}
	if memberID > 0 {
		query += " WHERE member_id = ?"
		args = append(args, memberID)
	}
	query += " ORDER BY upload_id"

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []ExportUpload
	for rows.Next() {
		var u ExportUpload
		var ct sql.NullTime
		if err := rows.Scan(&u.FileName, &u.StoragePath, &u.FileHash, &u.FileSize,
			&u.MimeType, &u.Width, &u.Height, &u.ThumbPath, &u.ThumbSize, &u.Category, &ct); err != nil {
			return nil, err
		}
		if ct.Valid {
			u.CreateTime = ct.Time.UTC().Format(time.RFC3339)
		}
		result = append(result, u)
	}
	return result, rows.Err()
}

// ========== 从 HTTP 请求解析 ZIP ==========

// importUploadDir 存放导入会话期间的临时 zip 文件，会话过期/消费后自动清理。
const importUploadDir = "data/imports"

// importMaxBytes 是导入 zip 的最大字节数，覆盖典型整站导出（含 uploads）。
const importMaxBytes = int64(5 * 1024 * 1024 * 1024) // 5 GiB

// ParseImportZip 从 multipart 请求里解析导入 zip。
// 与旧实现的区别：先把 zip 落到 data/imports/<uuid>.zip，再用 zip.OpenReader 打开，
// 避免 GB 量级的 zip 一次性读到内存 OOM；同时保留路径供 ImportExecute 阶段
// 读 uploads/ 子条目（check 与 execute 是两次独立 HTTP 请求）。
//
// 返回的 zipPath 由调用方传入 StoreImportSession，会话生命周期内有效。
func ParseImportZip(r *http.Request) (*ExportData, string, error) {
	file, _, err := r.FormFile("file")
	if err != nil {
		return nil, "", fmt.Errorf("读取上传文件失败: %w", err)
	}
	defer file.Close()

	if err := os.MkdirAll(importUploadDir, 0755); err != nil {
		return nil, "", fmt.Errorf("创建临时目录失败: %w", err)
	}
	zipPath := importUploadDir + "/" + uuid.New().String() + ".zip"
	out, err := os.OpenFile(zipPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return nil, "", fmt.Errorf("创建临时文件失败: %w", err)
	}
	limited := io.LimitReader(file, importMaxBytes+1)
	n, err := io.Copy(out, limited)
	closeErr := out.Close()
	if err != nil {
		_ = os.Remove(zipPath)
		return nil, "", fmt.Errorf("写入临时文件失败: %w", err)
	}
	if closeErr != nil {
		_ = os.Remove(zipPath)
		return nil, "", fmt.Errorf("关闭临时文件失败: %w", closeErr)
	}
	if n > importMaxBytes {
		_ = os.Remove(zipPath)
		return nil, "", fmt.Errorf("导入文件过大（超过 %d 字节）", importMaxBytes)
	}

	reader, err := zip.OpenReader(zipPath)
	if err != nil {
		_ = os.Remove(zipPath)
		return nil, "", fmt.Errorf("解压 ZIP 失败: %w", err)
	}
	defer reader.Close()

	data, err := ParseImportData(&reader.Reader)
	if err != nil {
		_ = os.Remove(zipPath)
		return nil, "", err
	}
	return data, zipPath, nil
}
