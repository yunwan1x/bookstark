package models

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

const defaultShareCommentDBPath = "data/share_comments.db"

var (
	shareCommentDB     *sql.DB
	shareCommentDBPath = defaultShareCommentDBPath
	shareCommentMu     sync.Mutex
)

type ShareComment struct {
	CommentID         int64     `json:"comment_id"`
	TargetType        string    `json:"target_type"`
	TargetID          int64     `json:"target_id"`
	ShareIdentify     string    `json:"share_identify"`
	ParentCommentID   int64     `json:"parent_comment_id"`
	RootCommentID     int64     `json:"root_comment_id"`
	ReplyToCommentID  int64     `json:"reply_to_comment_id"`
	ReplyToAuthorName string    `json:"reply_to_author_name"`
	AuthorMemberID    int64     `json:"author_member_id"`
	AuthorName        string    `json:"author_name"`
	AuthorEmail       string    `json:"-"`
	Content           string    `json:"content"`
	Status            string    `json:"status"`
	IPHash            string    `json:"-"`
	UserAgentHash     string    `json:"-"`
	CreateTime        time.Time `json:"create_time"`
	ModifyTime        time.Time `json:"modify_time"`
}

type ShareCommentCreate struct {
	TargetType        string
	TargetID          int64
	ShareIdentify     string
	ParentCommentID   int64
	ReplyToCommentID  int64
	ReplyToAuthorName string
	AuthorMemberID    int64
	AuthorName        string
	AuthorEmail       string
	Content           string
	IPHash            string
	UserAgentHash     string
}

type ShareCommentThread struct {
	Comment ShareComment
	Replies []ShareComment
}

func SetShareCommentDBPath(path string) error {
	shareCommentMu.Lock()
	defer shareCommentMu.Unlock()
	if shareCommentDB != nil {
		if err := shareCommentDB.Close(); err != nil {
			return err
		}
		shareCommentDB = nil
	}
	if strings.TrimSpace(path) == "" {
		shareCommentDBPath = defaultShareCommentDBPath
	} else {
		shareCommentDBPath = path
	}
	return nil
}

func CloseShareCommentDB() error {
	shareCommentMu.Lock()
	defer shareCommentMu.Unlock()
	if shareCommentDB == nil {
		return nil
	}
	err := shareCommentDB.Close()
	shareCommentDB = nil
	return err
}

func InitShareCommentDB() error {
	shareCommentMu.Lock()
	defer shareCommentMu.Unlock()
	return initShareCommentDBLocked()
}

func initShareCommentDBLocked() error {
	if shareCommentDB != nil {
		return nil
	}
	dir := filepath.Dir(shareCommentDBPath)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("create share comments db dir: %w", err)
		}
	}
	db, err := sql.Open("sqlite", sqliteDSN(shareCommentDBPath))
	if err != nil {
		return fmt.Errorf("open share comments db: %w", err)
	}
	if _, err := db.Exec("PRAGMA journal_mode=DELETE"); err != nil {
		db.Close()
		return fmt.Errorf("set share comments journal mode: %w", err)
	}
	if _, err := db.Exec("PRAGMA synchronous=NORMAL"); err != nil {
		db.Close()
		return fmt.Errorf("set share comments synchronous: %w", err)
	}
	if _, err := db.Exec("PRAGMA busy_timeout=3000"); err != nil {
		db.Close()
		return fmt.Errorf("set share comments busy_timeout: %w", err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	if err := createShareCommentTables(db); err != nil {
		db.Close()
		return err
	}
	shareCommentDB = db
	return nil
}

func createShareCommentTables(db *sql.DB) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS md_share_comments (
			comment_id INTEGER PRIMARY KEY AUTOINCREMENT,
			target_type TEXT NOT NULL,
			target_id INTEGER NOT NULL,
			share_identify TEXT NOT NULL DEFAULT '',
			parent_comment_id INTEGER NOT NULL DEFAULT 0,
			root_comment_id INTEGER NOT NULL DEFAULT 0,
			reply_to_comment_id INTEGER NOT NULL DEFAULT 0,
			reply_to_author_name TEXT NOT NULL DEFAULT '',
			author_member_id INTEGER NOT NULL DEFAULT 0,
			author_name TEXT NOT NULL DEFAULT '',
			author_email TEXT NOT NULL DEFAULT '',
			content TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'visible',
			ip_hash TEXT NOT NULL DEFAULT '',
			user_agent_hash TEXT NOT NULL DEFAULT '',
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_share_comments_target ON md_share_comments(target_type, target_id, status, create_time)`,
		`CREATE INDEX IF NOT EXISTS idx_share_comments_share_identify ON md_share_comments(share_identify, status, create_time)`,
		`CREATE INDEX IF NOT EXISTS idx_share_comments_author ON md_share_comments(author_member_id, status, create_time)`,
	}
	for _, stmt := range statements {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("create share comments table: %w", err)
		}
	}
	if err := migrateShareCommentReplyColumns(db); err != nil {
		return err
	}
	_, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_share_comments_thread ON md_share_comments(target_type, target_id, root_comment_id, parent_comment_id, status, create_time)`)
	return err
}

func migrateShareCommentReplyColumns(db *sql.DB) error {
	columns := map[string]bool{}
	rows, err := db.Query(`PRAGMA table_info(md_share_comments)`)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var cid int
		var name, colType string
		var notNull int
		var defaultValue any
		var pk int
		if err := rows.Scan(&cid, &name, &colType, &notNull, &defaultValue, &pk); err != nil {
			return err
		}
		columns[name] = true
	}
	if err := rows.Err(); err != nil {
		return err
	}
	addColumns := []struct {
		name string
		sql  string
	}{
		{"parent_comment_id", `ALTER TABLE md_share_comments ADD COLUMN parent_comment_id INTEGER NOT NULL DEFAULT 0`},
		{"root_comment_id", `ALTER TABLE md_share_comments ADD COLUMN root_comment_id INTEGER NOT NULL DEFAULT 0`},
		{"reply_to_comment_id", `ALTER TABLE md_share_comments ADD COLUMN reply_to_comment_id INTEGER NOT NULL DEFAULT 0`},
		{"reply_to_author_name", `ALTER TABLE md_share_comments ADD COLUMN reply_to_author_name TEXT NOT NULL DEFAULT ''`},
	}
	for _, col := range addColumns {
		if !columns[col.name] {
			if _, err := db.Exec(col.sql); err != nil {
				return err
			}
		}
	}
	_, err = db.Exec(`UPDATE md_share_comments SET root_comment_id = comment_id WHERE parent_comment_id = 0 AND root_comment_id = 0`)
	return err
}

func ShareCommentsEnabled() bool {
	return GetSettingWithDefault("share_comments_enabled", "1") == "1"
}

func ShareCommentMaxLength() int {
	if DB == nil {
		return 2000
	}
	n, err := strconv.Atoi(GetSettingWithDefault("share_comment_max_length", "2000"))
	if err != nil || n < 100 || n > 5000 {
		return 2000
	}
	return n
}

func ShareCommentHash(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:16])
}

func CreateShareComment(input ShareCommentCreate) (*ShareComment, error) {
	if err := InitShareCommentDB(); err != nil {
		return nil, err
	}
	input.TargetType = strings.TrimSpace(input.TargetType)
	input.ShareIdentify = strings.TrimSpace(input.ShareIdentify)
	input.ReplyToAuthorName = normalizeShareCommentText(input.ReplyToAuthorName, false)
	input.AuthorName = normalizeShareCommentText(input.AuthorName, false)
	input.AuthorEmail = normalizeShareCommentText(input.AuthorEmail, false)
	input.Content = normalizeShareCommentText(input.Content, true)
	if input.TargetType != "blog" && input.TargetType != "book" && input.TargetType != "document" {
		return nil, fmt.Errorf("invalid target type")
	}
	if input.TargetID <= 0 {
		return nil, fmt.Errorf("invalid target id")
	}
	if input.AuthorName == "" || utf8.RuneCountInString(input.AuthorName) > 40 {
		return nil, fmt.Errorf("invalid author name")
	}
	if hasScriptableShareCommentInput(input.AuthorName) {
		return nil, fmt.Errorf("invalid author name")
	}
	if input.AuthorEmail != "" && utf8.RuneCountInString(input.AuthorEmail) > 200 {
		return nil, fmt.Errorf("invalid author email")
	}
	if input.AuthorEmail != "" && hasScriptableShareCommentInput(input.AuthorEmail) {
		return nil, fmt.Errorf("invalid author email")
	}
	if input.Content == "" || utf8.RuneCountInString(input.Content) > ShareCommentMaxLength() {
		return nil, fmt.Errorf("invalid content")
	}
	if hasScriptableShareCommentInput(input.Content) {
		return nil, fmt.Errorf("invalid content")
	}
	rootCommentID, replyToCommentID, replyToAuthorName, err := resolveShareCommentReplyTarget(input)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	res, err := shareCommentDB.Exec(`
		INSERT INTO md_share_comments (
			target_type, target_id, share_identify, parent_comment_id, root_comment_id, reply_to_comment_id,
			reply_to_author_name, author_member_id, author_name, author_email,
			content, status, ip_hash, user_agent_hash, create_time, modify_time
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'visible', ?, ?, ?, ?)`,
		input.TargetType, input.TargetID, input.ShareIdentify, input.ParentCommentID, rootCommentID, replyToCommentID,
		replyToAuthorName, input.AuthorMemberID, input.AuthorName,
		input.AuthorEmail, input.Content, input.IPHash, input.UserAgentHash, now, now,
	)
	if err != nil {
		return nil, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return nil, err
	}
	if input.ParentCommentID == 0 {
		if _, err := shareCommentDB.Exec(`UPDATE md_share_comments SET root_comment_id = ? WHERE comment_id = ?`, id, id); err != nil {
			return nil, err
		}
	}
	return GetShareCommentByID(id)
}

func resolveShareCommentReplyTarget(input ShareCommentCreate) (int64, int64, string, error) {
	if input.ParentCommentID <= 0 && input.ReplyToCommentID <= 0 {
		return 0, 0, "", nil
	}
	if input.ParentCommentID <= 0 {
		return 0, 0, "", fmt.Errorf("invalid parent comment")
	}
	parent, err := GetShareCommentByID(input.ParentCommentID)
	if err != nil {
		return 0, 0, "", fmt.Errorf("invalid parent comment")
	}
	if parent.TargetType != input.TargetType || parent.TargetID != input.TargetID || parent.Status == "deleted" {
		return 0, 0, "", fmt.Errorf("invalid parent comment")
	}
	rootID := parent.RootCommentID
	if rootID == 0 {
		rootID = parent.CommentID
	}
	if parent.ParentCommentID != 0 {
		rootID = parent.RootCommentID
	}
	replyToID := input.ReplyToCommentID
	if replyToID <= 0 {
		replyToID = parent.CommentID
	}
	replyTo, err := GetShareCommentByID(replyToID)
	if err != nil {
		return 0, 0, "", fmt.Errorf("invalid reply target")
	}
	replyRootID := replyTo.RootCommentID
	if replyRootID == 0 {
		replyRootID = replyTo.CommentID
	}
	if replyTo.TargetType != input.TargetType || replyTo.TargetID != input.TargetID || replyTo.Status == "deleted" || replyRootID != rootID {
		return 0, 0, "", fmt.Errorf("invalid reply target")
	}
	replyToAuthorName := input.ReplyToAuthorName
	if replyToAuthorName == "" {
		replyToAuthorName = replyTo.AuthorName
	}
	return rootID, replyToID, replyToAuthorName, nil
}

func normalizeShareCommentText(value string, multiline bool) string {
	value = strings.TrimSpace(value)
	value = strings.Map(func(r rune) rune {
		if r == '\x00' {
			return -1
		}
		if multiline && (r == '\n' || r == '\r' || r == '\t') {
			return r
		}
		if !multiline && r == '\t' {
			return ' '
		}
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, value)
	if !multiline {
		return strings.TrimSpace(strings.Join(strings.Fields(value), " "))
	}
	value = strings.ReplaceAll(value, "\r\n", "\n")
	value = strings.ReplaceAll(value, "\r", "\n")
	return strings.TrimSpace(value)
}

func hasScriptableShareCommentInput(value string) bool {
	compact := strings.ToLower(value)
	compact = strings.ReplaceAll(compact, "\x00", "")
	compact = strings.ReplaceAll(compact, "\t", "")
	compact = strings.ReplaceAll(compact, "\n", "")
	compact = strings.ReplaceAll(compact, "\r", "")
	dangerous := []string{
		"<script",
		"</script",
		"<iframe",
		"<object",
		"<embed",
		"<svg",
		"<math",
		"<img",
		"<video",
		"<audio",
		"<link",
		"<meta",
		"<style",
		"<form",
		"<input",
		"javascript:",
		"vbscript:",
		"data:text/html",
		"data:image/svg",
	}
	for _, token := range dangerous {
		if strings.Contains(compact, token) {
			return true
		}
	}
	for _, marker := range []string{" onerror=", " onload=", " onclick=", " onmouseover=", " onfocus=", " onsubmit=", " formaction="} {
		if strings.Contains(" "+compact, marker) {
			return true
		}
	}
	return false
}

func GetShareCommentByID(commentID int64) (*ShareComment, error) {
	if err := InitShareCommentDB(); err != nil {
		return nil, err
	}
	row := shareCommentDB.QueryRow(`
		SELECT comment_id, target_type, target_id, share_identify, author_member_id, author_name,
			parent_comment_id, root_comment_id, reply_to_comment_id, reply_to_author_name,
			author_email, content, status, ip_hash, user_agent_hash, create_time, modify_time
		FROM md_share_comments
		WHERE comment_id = ?`,
		commentID,
	)
	var c ShareComment
	if err := row.Scan(&c.CommentID, &c.TargetType, &c.TargetID, &c.ShareIdentify, &c.AuthorMemberID,
		&c.AuthorName, &c.ParentCommentID, &c.RootCommentID, &c.ReplyToCommentID, &c.ReplyToAuthorName,
		&c.AuthorEmail, &c.Content, &c.Status, &c.IPHash, &c.UserAgentHash,
		&c.CreateTime, &c.ModifyTime); err != nil {
		return nil, err
	}
	return &c, nil
}

func ListShareComments(targetType string, targetID int64, page, pageSize int) ([]ShareComment, int64, error) {
	if err := InitShareCommentDB(); err != nil {
		return nil, 0, err
	}
	targetType = strings.TrimSpace(targetType)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	var total int64
	if err := shareCommentDB.QueryRow(`
		SELECT COUNT(1)
		FROM md_share_comments
		WHERE target_type = ? AND target_id = ? AND status = 'visible'`,
		targetType, targetID,
	).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := shareCommentDB.Query(`
		SELECT comment_id, target_type, target_id, share_identify, author_member_id, author_name,
			author_email, content, status, ip_hash, user_agent_hash, create_time, modify_time
		FROM md_share_comments
		WHERE target_type = ? AND target_id = ? AND status = 'visible'
		ORDER BY create_time ASC, comment_id ASC
		LIMIT ? OFFSET ?`,
		targetType, targetID, pageSize, (page-1)*pageSize,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]ShareComment, 0)
	for rows.Next() {
		var c ShareComment
		if err := rows.Scan(&c.CommentID, &c.TargetType, &c.TargetID, &c.ShareIdentify, &c.AuthorMemberID,
			&c.AuthorName, &c.AuthorEmail, &c.Content, &c.Status, &c.IPHash, &c.UserAgentHash,
			&c.CreateTime, &c.ModifyTime); err != nil {
			return nil, 0, err
		}
		items = append(items, c)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func ListShareCommentThreads(targetType string, targetID int64, page, pageSize int) ([]ShareCommentThread, int64, error) {
	if err := InitShareCommentDB(); err != nil {
		return nil, 0, err
	}
	targetType = strings.TrimSpace(targetType)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	whereRoot := `
		target_type = ? AND target_id = ? AND parent_comment_id = 0
		AND (
			status = 'visible'
			OR EXISTS (
				SELECT 1 FROM md_share_comments r
				WHERE r.target_type = md_share_comments.target_type
					AND r.target_id = md_share_comments.target_id
					AND r.root_comment_id = md_share_comments.comment_id
					AND r.parent_comment_id != 0
					AND r.status = 'visible'
			)
		)`
	var total int64
	if err := shareCommentDB.QueryRow(`SELECT COUNT(1) FROM md_share_comments WHERE `+whereRoot, targetType, targetID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := shareCommentDB.Query(`
		SELECT comment_id, target_type, target_id, share_identify, parent_comment_id, root_comment_id,
			reply_to_comment_id, reply_to_author_name, author_member_id, author_name, author_email,
			content, status, ip_hash, user_agent_hash, create_time, modify_time
		FROM md_share_comments
		WHERE `+whereRoot+`
		ORDER BY create_time ASC, comment_id ASC
		LIMIT ? OFFSET ?`,
		targetType, targetID, pageSize, (page-1)*pageSize,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	threads := make([]ShareCommentThread, 0)
	rootIDs := make([]int64, 0)
	for rows.Next() {
		comment, err := scanShareComment(rows)
		if err != nil {
			return nil, 0, err
		}
		threads = append(threads, ShareCommentThread{Comment: comment, Replies: []ShareComment{}})
		rootIDs = append(rootIDs, comment.CommentID)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	for i, rootID := range rootIDs {
		replies, err := listShareCommentReplies(targetType, targetID, rootID)
		if err != nil {
			return nil, 0, err
		}
		threads[i].Replies = replies
	}
	return threads, total, nil
}

func ListShareCommentsAdmin(page, pageSize int, keyword, status, targetType string) ([]ShareComment, int64, error) {
	if err := InitShareCommentDB(); err != nil {
		return nil, 0, err
	}
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	keyword = strings.TrimSpace(keyword)
	status = strings.TrimSpace(status)
	targetType = strings.TrimSpace(targetType)

	where := []string{"1=1"}
	args := make([]any, 0, 6)
	if targetType == "blog" || targetType == "book" || targetType == "document" {
		where = append(where, "target_type = ?")
		args = append(args, targetType)
	}
	if status == "visible" || status == "deleted" {
		where = append(where, "status = ?")
		args = append(args, status)
	}
	if keyword != "" {
		like := "%" + keyword + "%"
		where = append(where, "(content LIKE ? OR author_name LIKE ? OR share_identify LIKE ? OR reply_to_author_name LIKE ?)")
		args = append(args, like, like, like, like)
	}
	whereSQL := strings.Join(where, " AND ")

	var total int64
	if err := shareCommentDB.QueryRow(`SELECT COUNT(1) FROM md_share_comments WHERE `+whereSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	queryArgs := append([]any{}, args...)
	queryArgs = append(queryArgs, pageSize, (page-1)*pageSize)
	rows, err := shareCommentDB.Query(`
		SELECT comment_id, target_type, target_id, share_identify, parent_comment_id, root_comment_id,
			reply_to_comment_id, reply_to_author_name, author_member_id, author_name, author_email,
			content, status, ip_hash, user_agent_hash, create_time, modify_time
		FROM md_share_comments
		WHERE `+whereSQL+`
		ORDER BY create_time DESC, comment_id DESC
		LIMIT ? OFFSET ?`,
		queryArgs...,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]ShareComment, 0)
	for rows.Next() {
		comment, err := scanShareComment(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, comment)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

type shareCommentScanner interface {
	Scan(dest ...any) error
}

func scanShareComment(scanner shareCommentScanner) (ShareComment, error) {
	var c ShareComment
	err := scanner.Scan(&c.CommentID, &c.TargetType, &c.TargetID, &c.ShareIdentify, &c.ParentCommentID,
		&c.RootCommentID, &c.ReplyToCommentID, &c.ReplyToAuthorName, &c.AuthorMemberID, &c.AuthorName,
		&c.AuthorEmail, &c.Content, &c.Status, &c.IPHash, &c.UserAgentHash, &c.CreateTime, &c.ModifyTime)
	return c, err
}

func listShareCommentReplies(targetType string, targetID, rootCommentID int64) ([]ShareComment, error) {
	rows, err := shareCommentDB.Query(`
		SELECT comment_id, target_type, target_id, share_identify, parent_comment_id, root_comment_id,
			reply_to_comment_id, reply_to_author_name, author_member_id, author_name, author_email,
			content, status, ip_hash, user_agent_hash, create_time, modify_time
		FROM md_share_comments
		WHERE target_type = ? AND target_id = ? AND root_comment_id = ? AND parent_comment_id != 0 AND status = 'visible'
		ORDER BY create_time ASC, comment_id ASC`,
		targetType, targetID, rootCommentID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]ShareComment, 0)
	for rows.Next() {
		comment, err := scanShareComment(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, comment)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return items, nil
}

func SoftDeleteShareComment(commentID int64) error {
	if err := InitShareCommentDB(); err != nil {
		return err
	}
	_, err := shareCommentDB.Exec(
		`UPDATE md_share_comments SET status = 'deleted', modify_time = ? WHERE comment_id = ?`,
		time.Now(), commentID,
	)
	return err
}

func HardDeleteShareComments(commentIDs []int64) (int64, error) {
	if err := InitShareCommentDB(); err != nil {
		return 0, err
	}
	seen := map[int64]bool{}
	ids := make([]int64, 0, len(commentIDs))
	for _, id := range commentIDs {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		return 0, nil
	}

	tx, err := shareCommentDB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	var affected int64
	for _, id := range ids {
		var comment ShareComment
		err := tx.QueryRow(`
			SELECT comment_id, target_type, target_id, share_identify, parent_comment_id, root_comment_id,
				reply_to_comment_id, reply_to_author_name, author_member_id, author_name, author_email,
				content, status, ip_hash, user_agent_hash, create_time, modify_time
			FROM md_share_comments
			WHERE comment_id = ?`,
			id,
		).Scan(&comment.CommentID, &comment.TargetType, &comment.TargetID, &comment.ShareIdentify, &comment.ParentCommentID,
			&comment.RootCommentID, &comment.ReplyToCommentID, &comment.ReplyToAuthorName, &comment.AuthorMemberID, &comment.AuthorName,
			&comment.AuthorEmail, &comment.Content, &comment.Status, &comment.IPHash, &comment.UserAgentHash, &comment.CreateTime, &comment.ModifyTime)
		if err == sql.ErrNoRows {
			continue
		}
		if err != nil {
			return 0, err
		}

		var res sql.Result
		if comment.ParentCommentID == 0 {
			res, err = tx.Exec(`DELETE FROM md_share_comments WHERE comment_id = ? OR root_comment_id = ?`, comment.CommentID, comment.CommentID)
		} else {
			res, err = tx.Exec(`DELETE FROM md_share_comments WHERE comment_id = ?`, comment.CommentID)
		}
		if err != nil {
			return 0, err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return 0, err
		}
		affected += n
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return affected, nil
}
