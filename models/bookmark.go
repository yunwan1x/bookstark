package models

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// SortItem 排序项
type SortItem struct {
	ID        int64 `json:"id"`
	OrderSort int   `json:"order_sort"`
}

// Bookmark 书签
type Bookmark struct {
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

// BookmarkWithLabels 书签（含标签列表）
type BookmarkWithLabels struct {
	BookmarkID  int64     `json:"bookmark_id"`
	Title       string    `json:"title"`
	URL         string    `json:"url"`
	Description string    `json:"description"`
	Favicon     string    `json:"favicon"`
	OrderSort   int       `json:"order_sort"`
	Label       string    `json:"label"`
	Labels      []string  `json:"labels"`
	MemberID    int64     `json:"member_id"`
	IsPublic    bool      `json:"is_public"`
	IsPinned    bool      `json:"is_pinned"`
	NavVisible  bool      `json:"nav_visible"`
	Account     string    `json:"account"`
	CreateTime  time.Time `json:"create_time"`
	ModifyTime  time.Time `json:"modify_time"`
}

// BookmarkQuery 书签查询参数
type BookmarkQuery struct {
	Labels         []string   // 标签名列表（AND 逻辑）
	LabelsOr       []string   // 标签名列表（OR 逻辑）
	Keyword        string     // 关键词
	Site           string     // 站点域名，按 URL 前缀筛选
	MemberID       int64      // 用户ID，0=全部
	IsPublic       *bool      // 公开状态，nil=全部
	IsPinned       *bool      // 置顶状态，nil=全部
	NavVisible     *bool      // 导航页可见，nil=全部
	NoLabel        bool       // 仅无标签书签
	WithAccount    bool       // 是否关联用户账号
	StartTime      *time.Time // 时间起始
	EndTime        *time.Time // 时间截止
	TimeField      string     // 时间字段: "create"(默认) 或 "modify"
	PublicFeedSort string     // Optional public feed ordering: latest or updated.
	Page           int        // 页码，从1开始
	PageSize       int        // 每页条数
}

// BookmarkQueryResult 书签查询结果
type BookmarkQueryResult struct {
	Data  []BookmarkWithLabels `json:"data"`
	Total int                  `json:"total"`
	Page  int                  `json:"page"`
}

// QueryBookmarks 分页查询书签（含标签）
func QueryBookmarks(q BookmarkQuery) (*BookmarkQueryResult, error) {
	if q.Page < 1 {
		q.Page = 1
	}
	if q.PageSize < 1 {
		q.PageSize = 20
	}

	// 构建 WHERE 条件
	var where []string
	var args []interface{}

	if q.MemberID > 0 {
		where = append(where, "b.member_id = ?")
		args = append(args, q.MemberID)
	}
	if q.IsPublic != nil {
		if *q.IsPublic {
			where = append(where, "b.is_public = 1")
		} else {
			where = append(where, "b.is_public = 0")
		}
	}
	if q.IsPinned != nil {
		if *q.IsPinned {
			where = append(where, "b.is_pinned = 1")
		} else {
			where = append(where, "b.is_pinned = 0")
		}
	}
	if q.NavVisible != nil {
		if *q.NavVisible {
			where = append(where, "b.nav_visible = 1")
		} else {
			where = append(where, "b.nav_visible = 0")
		}
	}
	if q.Keyword != "" {
		kw := "%" + q.Keyword + "%"
		where = append(where, "(b.title LIKE ? OR b.url LIKE ? OR b.description LIKE ?)")
		args = append(args, kw, kw, kw)
	}
	if q.Site != "" {
		where = append(where, "(b.url LIKE ? OR b.url LIKE ?)")
		args = append(args, "https://"+q.Site+"/%", "http://"+q.Site+"/%")
	}
	if len(q.Labels) > 0 {
		for _, label := range q.Labels {
			where = append(where, `EXISTS (
				SELECT 1 FROM md_label_relation r
				JOIN md_label l ON r.label_id = l.label_id
				WHERE r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark' AND l.label_name = ?
			)`)
			args = append(args, label)
		}
	}
	if len(q.LabelsOr) > 0 {
		var orParts []string
		for _, label := range q.LabelsOr {
			orParts = append(orParts, `EXISTS (
				SELECT 1 FROM md_label_relation r
				JOIN md_label l ON r.label_id = l.label_id
				WHERE r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark' AND l.label_name = ?
			)`)
			args = append(args, label)
		}
		where = append(where, "("+joinStrings(orParts, " OR ")+")")
	}
	timeCol := "b.create_time"
	if q.TimeField == "modify" {
		timeCol = "b.modify_time"
	}
	if q.StartTime != nil {
		where = append(where, timeCol+" >= ?")
		args = append(args, *q.StartTime)
	}
	if q.EndTime != nil {
		where = append(where, timeCol+" <= ?")
		args = append(args, *q.EndTime)
	}
	if q.NoLabel {
		where = append(where, "NOT EXISTS (SELECT 1 FROM md_label_relation r WHERE r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark')")
	}

	whereClause := ""
	if len(where) > 0 {
		whereClause = "WHERE " + joinStrings(where, " AND ")
	}

	// 查总数
	var total int
	countSQL := "SELECT COUNT(*) FROM md_bookmark b " + whereClause
	if err := DB.QueryRow(countSQL, args...).Scan(&total); err != nil {
		return nil, err
	}

	// 构建 SELECT 字段
	selectFields := "b.bookmark_id, b.title, b.url, b.description, b.favicon, b.order_sort, b.label, b.member_id, b.is_public, b.is_pinned, b.nav_visible, b.create_time, b.modify_time"
	fromClause := "FROM md_bookmark b"
	if q.WithAccount {
		selectFields = "b.bookmark_id, b.title, b.url, b.description, b.favicon, b.order_sort, b.label, b.member_id, b.is_public, b.is_pinned, b.nav_visible, b.create_time, b.modify_time, m.account"
		fromClause = "FROM md_bookmark b LEFT JOIN md_members m ON b.member_id = m.member_id"
	}

	// 分页查询
	offset := (q.Page - 1) * q.PageSize
	orderSQL := "b.is_pinned DESC, b.modify_time DESC"
	if q.PublicFeedSort == "latest" {
		orderSQL = "b.create_time DESC, b.bookmark_id DESC"
	}
	if q.PublicFeedSort == "updated" {
		orderSQL = "b.modify_time DESC, b.bookmark_id DESC"
	}
	dataSQL := "SELECT " + selectFields + " " + fromClause + " " + whereClause +
		" ORDER BY " + orderSQL +
		" LIMIT ? OFFSET ?"
	dataArgs := append(args, q.PageSize, offset)

	rows, err := DB.Query(dataSQL, dataArgs...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var bookmarks []BookmarkWithLabels
	for rows.Next() {
		var b BookmarkWithLabels
		var isPublic int
		var isPinned int
		var navVisible int
		if q.WithAccount {
			if err := rows.Scan(&b.BookmarkID, &b.Title, &b.URL, &b.Description, &b.Favicon, &b.OrderSort, &b.Label, &b.MemberID, &isPublic, &isPinned, &navVisible, &b.CreateTime, &b.ModifyTime, &b.Account); err != nil {
				return nil, err
			}
		} else {
			if err := rows.Scan(&b.BookmarkID, &b.Title, &b.URL, &b.Description, &b.Favicon, &b.OrderSort, &b.Label, &b.MemberID, &isPublic, &isPinned, &navVisible, &b.CreateTime, &b.ModifyTime); err != nil {
				return nil, err
			}
		}
		b.IsPublic = isPublic == 1
		b.IsPinned = isPinned == 1
		b.NavVisible = navVisible == 1
		bookmarks = append(bookmarks, b)
	}

	// 批量填充标签
	if len(bookmarks) > 0 {
		var bookmarkIDs []int64
		for _, b := range bookmarks {
			bookmarkIDs = append(bookmarkIDs, b.BookmarkID)
		}
		labelMap, err := BatchGetLabelsByResources(bookmarkIDs, "bookmark")
		if err != nil {
			log.Printf("QueryBookmarks: BatchGetLabelsByResources failed: %v", err)
		}
		for i := range bookmarks {
			if labels, ok := labelMap[bookmarks[i].BookmarkID]; ok {
				bookmarks[i].Labels = labels
			} else {
				bookmarks[i].Labels = []string{}
			}
		}
	}

	if bookmarks == nil {
		bookmarks = []BookmarkWithLabels{}
	}

	return &BookmarkQueryResult{
		Data:  bookmarks,
		Total: total,
		Page:  q.Page,
	}, nil
}

// joinStrings 用 sep 连接字符串切片
func joinStrings(ss []string, sep string) string {
	if len(ss) == 0 {
		return ""
	}
	result := ss[0]
	for i := 1; i < len(ss); i++ {
		result += sep + ss[i]
	}
	return result
}

// GetBookmarkByID 按 ID 获取书签
func GetBookmarkByID(id int64) (*Bookmark, error) {
	b := &Bookmark{}
	var isPublic int
	var isPinned int
	var navVisible int
	err := DB.QueryRow(
		"SELECT bookmark_id, title, url, description, favicon, order_sort, label, member_id, is_public, is_pinned, nav_visible, create_time, modify_time FROM md_bookmark WHERE bookmark_id = ?",
		id,
	).Scan(&b.BookmarkID, &b.Title, &b.URL, &b.Description, &b.Favicon, &b.OrderSort, &b.Label, &b.MemberID, &isPublic, &isPinned, &navVisible, &b.CreateTime, &b.ModifyTime)
	if err != nil {
		return nil, err
	}
	b.IsPublic = isPublic == 1
	b.IsPinned = isPinned == 1
	b.NavVisible = navVisible == 1
	return b, nil
}

// GetBookmarkByIDTx 在事务中按 ID 获取书签
func GetBookmarkByIDTx(tx *sql.Tx, id int64) (*Bookmark, error) {
	b := &Bookmark{}
	var isPublic int
	var isPinned int
	var navVisible int
	err := tx.QueryRow(
		"SELECT bookmark_id, title, url, description, favicon, order_sort, label, member_id, is_public, is_pinned, nav_visible, create_time, modify_time FROM md_bookmark WHERE bookmark_id = ?",
		id,
	).Scan(&b.BookmarkID, &b.Title, &b.URL, &b.Description, &b.Favicon, &b.OrderSort, &b.Label, &b.MemberID, &isPublic, &isPinned, &navVisible, &b.CreateTime, &b.ModifyTime)
	if err != nil {
		return nil, err
	}
	b.IsPublic = isPublic == 1
	b.IsPinned = isPinned == 1
	b.NavVisible = navVisible == 1
	return b, nil
}

// generateFaviconURL 从 URL 提取 domain 生成 favicon 地址
func generateFaviconURL(rawURL string) string {
	u, err := url.Parse(rawURL)
	if err != nil || u.Host == "" {
		return ""
	}
	scheme := u.Scheme
	if scheme == "" {
		scheme = "https"
	}
	return fmt.Sprintf("%s://%s/favicon.ico", scheme, u.Host)
}

// Insert 创建书签
func (b *Bookmark) Insert() error {
	now := time.Now()
	return b.insertAt(now, now)
}

// InsertWithTime 插入书签并使用 Bookmark 自身的 CreateTime/ModifyTime（而非 time.Now）
func (b *Bookmark) InsertWithTime() error {
	ct := b.CreateTime
	mt := b.ModifyTime
	if ct.IsZero() {
		ct = time.Now()
	}
	if mt.IsZero() {
		mt = ct
	}

	return b.insertAt(ct, mt)
}

// IsBookmarkBusyError includes SQLite's extended BUSY codes (e.g. 517).
func IsBookmarkBusyError(err error) bool {
	var coded interface{ Code() int }
	return errors.As(err, &coded) && coded.Code()&0xff == 5
}

func (b *Bookmark) insertAt(ct, mt time.Time) error {
	if b.Favicon == "" {
		b.Favicon = generateFaviconURL(b.URL)
	}
	// Compute the next sort value inside the write statement, avoiding a
	// deferred read transaction upgrading to a writer with a stale snapshot.
	const query = `INSERT INTO md_bookmark
		(title, url, description, favicon, order_sort, label, member_id, is_public, nav_visible, create_time, modify_time)
		SELECT ?, ?, ?, ?, CASE WHEN ? > 0 THEN ? ELSE
			(SELECT COALESCE(MAX(order_sort), 0) + 1 FROM md_bookmark WHERE member_id = ?) END,
			?, ?, ?, ?, ?, ?
		RETURNING bookmark_id, order_sort`
	for attempt := 0; ; attempt++ {
		var id int64
		var order int
		err := DB.QueryRow(query, b.Title, b.URL, b.Description, b.Favicon,
			b.OrderSort, b.OrderSort, b.MemberID, b.Label, b.MemberID,
			b.IsPublic, b.NavVisible, ct, mt).Scan(&id, &order)
		if err == nil {
			b.BookmarkID, b.OrderSort = id, order
			return nil
		}
		// Each attempt is a fresh, atomic statement. Never retry constraints
		// or other permanent errors. SQLite also applies its busy_timeout.
		if !IsBookmarkBusyError(err) || attempt >= 2 {
			return err
		}
		log.Printf("Bookmark.Insert: database busy member_id=%d retry=%d err=%v", b.MemberID, attempt+1, err)
		time.Sleep(time.Duration(attempt+1) * 50 * time.Millisecond)
	}
}

// Update 更新书签
func (b *Bookmark) Update() error {
	if b.Favicon == "" {
		b.Favicon = generateFaviconURL(b.URL)
	}
	isPublic := 0
	if b.IsPublic {
		isPublic = 1
	}
	navVisible := 0
	if b.NavVisible {
		navVisible = 1
	}
	_, err := DB.Exec(
		"UPDATE md_bookmark SET title = ?, url = ?, description = ?, favicon = ?, order_sort = ?, label = ?, is_public = ?, nav_visible = ?, modify_time = ? WHERE bookmark_id = ?",
		b.Title, b.URL, b.Description, b.Favicon, b.OrderSort, b.Label, isPublic, navVisible, time.Now(), b.BookmarkID,
	)
	return err
}

// TouchBookmarkModifyTime refreshes the modified timestamp for bookmark actions
// that affect ordering but do not otherwise call Bookmark.Update.
func TouchBookmarkModifyTime(id int64) error {
	_, err := DB.Exec("UPDATE md_bookmark SET modify_time = ? WHERE bookmark_id = ?", time.Now(), id)
	return err
}

// ToggleBookmarkPublic 切换书签公开状态
func ToggleBookmarkPublic(id int64, isPublic bool) error {
	pub := 0
	if isPublic {
		pub = 1
	}
	_, err := DB.Exec("UPDATE md_bookmark SET is_public = ? WHERE bookmark_id = ?", pub, id)
	return err
}

// UpdateBookmarkFavicon 仅更新书签的 favicon 字段
func UpdateBookmarkFavicon(id int64, favicon string) error {
	_, err := DB.Exec("UPDATE md_bookmark SET favicon = ? WHERE bookmark_id = ?", favicon, id)
	return err
}

// DeleteBookmark 删除书签（含标签关联和分享记录）
func DeleteBookmark(id int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Check if bookmark exists
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_bookmark WHERE bookmark_id = ?", id).Scan(&count); err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("书签不存在")
	}

	// 快照到回收站
	snap, name, snapErr := SnapshotBookmark(tx, id)
	if snapErr != nil {
		log.Printf("DeleteBookmark: 快照失败: %v", snapErr)
	} else {
		var memberID int64
		if err := tx.QueryRow("SELECT member_id FROM md_bookmark WHERE bookmark_id = ?", id).Scan(&memberID); err == nil {
			if err := CreateTrash(tx, "bookmark", name, snap, memberID); err != nil {
				log.Printf("DeleteBookmark: 写入回收站失败: %v", err)
			}
		}
	}

	// Delete associated share records
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'bookmark' AND target_id = ?", id); err != nil {
		return err
	}
	// Delete associated label relations
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'bookmark'", id); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_bookmark WHERE bookmark_id = ?", id); err != nil {
		return err
	}
	return tx.Commit()
}

// SortBookmarks 批量更新书签排序
func SortBookmarks(items []SortItem) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, item := range items {
		if _, err := tx.Exec("UPDATE md_bookmark SET order_sort = ? WHERE bookmark_id = ?", item.OrderSort, item.ID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// ListBookmarkLabels 获取所有书签使用的标签名（去重）
func ListBookmarkLabels(memberID ...int64) ([]string, error) {
	query := `
		SELECT DISTINCT l.label_name
		FROM md_label l
		JOIN md_label_relation r ON l.label_id = r.label_id
		JOIN md_bookmark b ON r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark'`
	var args []interface{}
	if len(memberID) > 0 && memberID[0] > 0 {
		query += ` WHERE b.member_id = ? AND b.nav_visible = 1`
		args = append(args, memberID[0])
	} else {
		query += ` WHERE b.nav_visible = 1`
	}
	query += ` ORDER BY l.label_name LIMIT ` + strconv.Itoa(GetLabelListLimit())

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	return names, nil
}

// ListPublicBookmarkLabels 获取公开书签使用的标签名（去重）
func ListPublicBookmarkLabels() ([]string, error) {
	query := `
		SELECT DISTINCT l.label_name
		FROM md_label l
		JOIN md_label_relation r ON l.label_id = r.label_id
		JOIN md_bookmark b ON r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark'
		WHERE b.is_public = 1 AND b.nav_visible = 1
		ORDER BY l.label_name LIMIT ` + strconv.Itoa(GetLabelListLimit())

	rows, err := DB.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	return names, nil
}

// BookmarkLabelCount 书签标签（含数量，用于高级搜索面板）
type BookmarkLabelCount struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// ListBookmarkLabelsWithCount 获取标签列表（含书签数量）
func ListBookmarkLabelsWithCount(memberID ...int64) ([]BookmarkLabelCount, error) {
	query := `
		SELECT l.label_name, COUNT(DISTINCT b.bookmark_id) as cnt
		FROM md_label l
		JOIN md_label_relation r ON l.label_id = r.label_id
		JOIN md_bookmark b ON r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark'`
	var args []interface{}
	if len(memberID) > 0 && memberID[0] > 0 {
		query += ` WHERE b.member_id = ?`
		args = append(args, memberID[0])
	}
	query += ` GROUP BY l.label_name ORDER BY l.label_name LIMIT ` + strconv.Itoa(GetLabelListLimit())

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var labels []BookmarkLabelCount
	for rows.Next() {
		var lc BookmarkLabelCount
		if err := rows.Scan(&lc.Name, &lc.Count); err != nil {
			return nil, err
		}
		labels = append(labels, lc)
	}
	return labels, nil
}

// ListPublicBookmarkLabelsWithCount 获取公开书签标签列表（含书签数量）
func ListPublicBookmarkLabelsWithCount() ([]BookmarkLabelCount, error) {
	query := `
		SELECT l.label_name, COUNT(DISTINCT b.bookmark_id) as cnt
		FROM md_label l
		JOIN md_label_relation r ON l.label_id = r.label_id
		JOIN md_bookmark b ON r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark'
		WHERE b.is_public = 1
		GROUP BY l.label_name ORDER BY l.label_name LIMIT ` + strconv.Itoa(GetLabelListLimit())

	rows, err := DB.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var labels []BookmarkLabelCount
	for rows.Next() {
		var lc BookmarkLabelCount
		if err := rows.Scan(&lc.Name, &lc.Count); err != nil {
			return nil, err
		}
		labels = append(labels, lc)
	}
	return labels, nil
}

// BatchDeleteBookmarks 批量删除书签
func BatchDeleteBookmarks(ids []int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, id := range ids {
		// 快照到回收站
		snap, name, snapErr := SnapshotBookmark(tx, id)
		if snapErr != nil {
			log.Printf("BatchDeleteBookmarks: 快照书签 %d 失败: %v", id, snapErr)
		} else {
			var memberID int64
			if err := tx.QueryRow("SELECT member_id FROM md_bookmark WHERE bookmark_id = ?", id).Scan(&memberID); err == nil {
				if err := CreateTrash(tx, "bookmark", name, snap, memberID); err != nil {
					log.Printf("BatchDeleteBookmarks: 写入回收站失败: %v", err)
				}
			}
		}

		if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'bookmark'", id); err != nil {
			return err
		}
		if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'bookmark' AND target_id = ?", id); err != nil {
			return err
		}
		if _, err := tx.Exec("DELETE FROM md_bookmark WHERE bookmark_id = ?", id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// BatchSetPublic 批量设置书签公开状态
func BatchSetPublic(ids []int64, isPublic bool) error {
	pub := 0
	if isPublic {
		pub = 1
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, id := range ids {
		if _, err := tx.Exec("UPDATE md_bookmark SET is_public = ? WHERE bookmark_id = ?", pub, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// BatchAddLabels 批量为书签添加标签
func BatchAddLabels(ids []int64, labelNames []string) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, id := range ids {
		// 获取当前标签
		existing, err := GetLabelsByResource(id, "bookmark")
		if err != nil {
			log.Printf("BatchAddLabels: GetLabelsByResource failed for id=%d: %v", id, err)
		}
		existingSet := make(map[string]bool)
		for _, l := range existing {
			existingSet[l] = true
		}
		// 合并新标签
		var merged []string
		merged = append(merged, existing...)
		for _, name := range labelNames {
			if !existingSet[name] {
				merged = append(merged, name)
			}
		}
		// 更新 label 字段
		labelStr := joinStrings(merged, ",")
		if _, err := tx.Exec("UPDATE md_bookmark SET label = ?, modify_time = ? WHERE bookmark_id = ?", labelStr, time.Now(), id); err != nil {
			return err
		}
		// 重建标签关联
		if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'bookmark'", id); err != nil {
			return err
		}
		for _, name := range merged {
			var labelID int64
			err := tx.QueryRow("SELECT label_id FROM md_label WHERE label_name = ?", name).Scan(&labelID)
			if err != nil {
				res, err2 := tx.Exec("INSERT INTO md_label (label_name) VALUES (?)", name)
				if err2 != nil {
					return err2
				}
				labelID, _ = res.LastInsertId()
				if labelID == 0 {
					log.Printf("label Insert: LastInsertId returned 0")
				}
			}
			if _, err := tx.Exec("INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, 'bookmark', datetime('now'))", labelID, id); err != nil {
				return err
			}
		}
	}
	return tx.Commit()
}

// BatchRemoveLabels 批量为书签移除标签
func BatchRemoveLabels(ids []int64, labelNames []string) error {
	removeSet := make(map[string]bool)
	for _, n := range labelNames {
		removeSet[n] = true
	}

	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, id := range ids {
		existing, err := GetLabelsByResource(id, "bookmark")
		if err != nil {
			log.Printf("BatchRemoveLabels: GetLabelsByResource failed for id=%d: %v", id, err)
		}
		var remaining []string
		for _, l := range existing {
			if !removeSet[l] {
				remaining = append(remaining, l)
			}
		}
		// 更新 label 字段
		labelStr := joinStrings(remaining, ",")
		if _, err := tx.Exec("UPDATE md_bookmark SET label = ?, modify_time = ? WHERE bookmark_id = ?", labelStr, time.Now(), id); err != nil {
			return err
		}
		// 重建标签关联
		if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'bookmark'", id); err != nil {
			return err
		}
		for _, name := range remaining {
			var labelID int64
			err := tx.QueryRow("SELECT label_id FROM md_label WHERE label_name = ?", name).Scan(&labelID)
			if err != nil {
				res, err2 := tx.Exec("INSERT INTO md_label (label_name) VALUES (?)", name)
				if err2 != nil {
					return err2
				}
				labelID, _ = res.LastInsertId()
				if labelID == 0 {
					log.Printf("label Insert: LastInsertId returned 0")
				}
			}
			if _, err := tx.Exec("INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, 'bookmark', datetime('now'))", labelID, id); err != nil {
				return err
			}
		}
	}
	return tx.Commit()
}

// BatchSetPinned 批量设置书签置顶状态
func BatchSetPinned(ids []int64, isPinned bool) error {
	p := 0
	if isPinned {
		p = 1
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, id := range ids {
		if _, err := tx.Exec("UPDATE md_bookmark SET is_pinned = ?, modify_time = ? WHERE bookmark_id = ?", p, time.Now(), id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// BatchSetNavVisible 批量设置书签导航页可见状态
func BatchSetNavVisible(ids []int64, navVisible bool) error {
	nv := 0
	if navVisible {
		nv = 1
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, id := range ids {
		if _, err := tx.Exec("UPDATE md_bookmark SET nav_visible = ?, modify_time = ? WHERE bookmark_id = ?", nv, time.Now(), id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// GetBookmarkByURLAndMember 按 URL 和用户查询书签
func GetBookmarkByURLAndMember(url string, memberID int64) (*BookmarkWithLabels, error) {
	b := &BookmarkWithLabels{}
	var isPublic int
	var isPinned int
	var navVisible int
	err := DB.QueryRow(
		"SELECT bookmark_id, title, url, description, favicon, order_sort, label, member_id, is_public, is_pinned, nav_visible, create_time, modify_time FROM md_bookmark WHERE url = ? AND member_id = ?",
		url, memberID,
	).Scan(&b.BookmarkID, &b.Title, &b.URL, &b.Description, &b.Favicon, &b.OrderSort, &b.Label, &b.MemberID, &isPublic, &isPinned, &navVisible, &b.CreateTime, &b.ModifyTime)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	b.IsPublic = isPublic == 1
	b.IsPinned = isPinned == 1
	b.NavVisible = navVisible == 1
	labels, err := GetLabelsByResource(b.BookmarkID, "bookmark")
	if err != nil {
		log.Printf("GetBookmarkByURLAndMember: GetLabelsByResource failed: %v", err)
	}
	b.Labels = labels
	return b, nil
}

// ToggleBookmarkPin 切换书签置顶状态
func ToggleBookmarkPin(id int64) (bool, error) {
	var current int
	err := DB.QueryRow("SELECT is_pinned FROM md_bookmark WHERE bookmark_id = ?", id).Scan(&current)
	if err != nil {
		return false, err
	}
	newVal := 1
	if current == 1 {
		newVal = 0
	}
	if _, err := DB.Exec("UPDATE md_bookmark SET is_pinned = ?, modify_time = ? WHERE bookmark_id = ?", newVal, time.Now(), id); err != nil {
		return false, err
	}
	return newVal == 1, nil
}

// ToggleBookmarkNavVisible 切换书签导航可见性
func ToggleBookmarkNavVisible(id int64, visible bool) error {
	v := 0
	if visible {
		v = 1
	}
	_, err := DB.Exec("UPDATE md_bookmark SET nav_visible = ?, modify_time = ? WHERE bookmark_id = ?", v, time.Now(), id)
	return err
}

// BookmarkGroup 分组书签结果
type BookmarkGroup struct {
	Name      string               `json:"name"`
	Bookmarks []BookmarkWithLabels `json:"bookmarks"`
}

// BookmarksGroupedResult 分组聚合结果
type BookmarksGroupedResult struct {
	Groups    []BookmarkGroup      `json:"groups"`
	Ungrouped []BookmarkWithLabels `json:"ungrouped"`
	Pinned    []BookmarkWithLabels `json:"pinned"`
	AllLabels []string             `json:"all_labels"`
	Total     int                  `json:"total"`
}

// QueryBookmarksGrouped 查询分组聚合的书签（导航主页用）
func QueryBookmarksGrouped(memberID int64, isPublic bool, keyword string, groupFilter string, labels []string) (*BookmarksGroupedResult, error) {
	var where []string
	var args []interface{}

	where = append(where, "b.nav_visible = 1")

	if memberID > 0 {
		where = append(where, "b.member_id = ?")
		args = append(args, memberID)
	}
	if isPublic {
		where = append(where, "b.is_public = 1")
	}
	if keyword != "" {
		kw := "%" + keyword + "%"
		where = append(where, "(b.title LIKE ? OR b.url LIKE ? OR b.description LIKE ?)")
		args = append(args, kw, kw, kw)
	}
	if len(labels) > 0 {
		for _, label := range labels {
			where = append(where, `EXISTS (
				SELECT 1 FROM md_label_relation r
				JOIN md_label l ON r.label_id = l.label_id
				WHERE r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark' AND l.label_name = ?
			)`)
			args = append(args, label)
		}
	}

	whereClause := "WHERE " + joinStrings(where, " AND ")

	query := "SELECT b.bookmark_id, b.title, b.url, b.description, b.favicon, b.order_sort, b.label, b.member_id, b.is_public, b.is_pinned, b.nav_visible, b.create_time, b.modify_time FROM md_bookmark b " +
		whereClause +
		fmt.Sprintf(" ORDER BY b.is_pinned DESC, b.modify_time DESC LIMIT %d", GetNavMaxItems())

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var all []BookmarkWithLabels
	for rows.Next() {
		var b BookmarkWithLabels
		var isPublic int
		var isPinned int
		var navVisible int
		if err := rows.Scan(&b.BookmarkID, &b.Title, &b.URL, &b.Description, &b.Favicon, &b.OrderSort, &b.Label, &b.MemberID, &isPublic, &isPinned, &navVisible, &b.CreateTime, &b.ModifyTime); err != nil {
			return nil, err
		}
		b.IsPublic = isPublic == 1
		b.IsPinned = isPinned == 1
		b.NavVisible = navVisible == 1
		all = append(all, b)
	}
	rows.Close()

	// 批量填充标签
	if len(all) > 0 {
		var ids []int64
		for _, b := range all {
			ids = append(ids, b.BookmarkID)
		}
		labelMap, err := BatchGetLabelsByResources(ids, "bookmark")
		if err != nil {
			log.Printf("QueryBookmarksGrouped: BatchGetLabelsByResources failed: %v", err)
		}
		for i := range all {
			if labels, ok := labelMap[all[i].BookmarkID]; ok {
				all[i].Labels = labels
			} else {
				all[i].Labels = []string{}
			}
		}
	}

	// 分组
	var pinned []BookmarkWithLabels
	var grouped map[string][]BookmarkWithLabels = make(map[string][]BookmarkWithLabels)
	var ungrouped []BookmarkWithLabels
	var groupOrder []string

	for _, b := range all {
		if b.IsPinned {
			pinned = append(pinned, b)
			continue
		}
		groupName := ""
		for _, lbl := range b.Labels {
			if idx := strings.Index(lbl, "/"); idx > 0 {
				groupName = lbl[:idx]
				break
			}
		}
		if groupFilter != "" && groupName != groupFilter {
			continue
		}
		if groupName == "" {
			ungrouped = append(ungrouped, b)
		} else {
			if _, exists := grouped[groupName]; !exists {
				groupOrder = append(groupOrder, groupName)
			}
			grouped[groupName] = append(grouped[groupName], b)
		}
	}

	// 按书签数降序排列分组
	sort.Slice(groupOrder, func(i, j int) bool {
		return len(grouped[groupOrder[i]]) > len(grouped[groupOrder[j]])
	})

	var groups []BookmarkGroup
	for _, name := range groupOrder {
		groups = append(groups, BookmarkGroup{Name: name, Bookmarks: grouped[name]})
	}

	// 获取标签列表
	var allLabels []string
	if memberID > 0 && !isPublic {
		allLabels, _ = ListBookmarkLabels(memberID)
	} else if isPublic {
		allLabels, _ = ListPublicBookmarkLabels()
	}
	if allLabels == nil {
		allLabels = []string{}
	}

	if pinned == nil {
		pinned = []BookmarkWithLabels{}
	}
	if ungrouped == nil {
		ungrouped = []BookmarkWithLabels{}
	}
	if groups == nil {
		groups = []BookmarkGroup{}
	}

	return &BookmarksGroupedResult{
		Groups:    groups,
		Ungrouped: ungrouped,
		Pinned:    pinned,
		AllLabels: allLabels,
		Total:     len(all),
	}, nil
}

// ListBookmarkTagNames 获取书签使用的标签名列表（去重）
func ListBookmarkTagNames(memberID int64) ([]string, error) {
	rows, err := DB.Query(`
		SELECT DISTINCT l.label_name
		FROM md_label l
		JOIN md_label_relation lr ON l.label_id = lr.label_id
		JOIN md_bookmark b ON lr.resource_id = b.bookmark_id AND lr.relation_type = 'bookmark'
		WHERE b.member_id = ?
		ORDER BY l.label_name LIMIT 1000
	`, memberID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	return names, nil
}

// CountBookmarksByMember counts how many of the given IDs belong to the member
func CountBookmarksByMember(ids []int64, memberID int64) (int, error) {
	if len(ids) == 0 {
		return 0, nil
	}
	placeholders := ""
	args := []interface{}{memberID}
	for i, id := range ids {
		if i > 0 {
			placeholders += ","
		}
		placeholders += "?"
		args = append(args, id)
	}
	var count int
	err := DB.QueryRow(
		"SELECT COUNT(*) FROM md_bookmark WHERE member_id = ? AND bookmark_id IN ("+placeholders+")",
		args...,
	).Scan(&count)
	return count, err
}

// QueryBookmarkIDsByFilter 根据筛选条件查询所有匹配的书签ID（不分页）
func QueryBookmarkIDsByFilter(q BookmarkQuery) ([]int64, error) {
	var where []string
	var args []interface{}

	if q.MemberID > 0 {
		where = append(where, "b.member_id = ?")
		args = append(args, q.MemberID)
	}
	if q.IsPublic != nil {
		if *q.IsPublic {
			where = append(where, "b.is_public = 1")
		} else {
			where = append(where, "b.is_public = 0")
		}
	}
	if q.IsPinned != nil {
		if *q.IsPinned {
			where = append(where, "b.is_pinned = 1")
		} else {
			where = append(where, "b.is_pinned = 0")
		}
	}
	if q.NavVisible != nil {
		if *q.NavVisible {
			where = append(where, "b.nav_visible = 1")
		} else {
			where = append(where, "b.nav_visible = 0")
		}
	}
	if q.Keyword != "" {
		kw := "%" + q.Keyword + "%"
		where = append(where, "(b.title LIKE ? OR b.url LIKE ? OR b.description LIKE ?)")
		args = append(args, kw, kw, kw)
	}
	if q.Site != "" {
		where = append(where, "(b.url LIKE ? OR b.url LIKE ?)")
		args = append(args, "https://"+q.Site+"/%", "http://"+q.Site+"/%")
	}
	if len(q.Labels) > 0 {
		for _, label := range q.Labels {
			where = append(where, `EXISTS (
				SELECT 1 FROM md_label_relation r
				JOIN md_label l ON r.label_id = l.label_id
				WHERE r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark' AND l.label_name = ?
			)`)
			args = append(args, label)
		}
	}
	if len(q.LabelsOr) > 0 {
		var orParts []string
		for _, label := range q.LabelsOr {
			orParts = append(orParts, `EXISTS (
				SELECT 1 FROM md_label_relation r
				JOIN md_label l ON r.label_id = l.label_id
				WHERE r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark' AND l.label_name = ?
			)`)
			args = append(args, label)
		}
		where = append(where, "("+joinStrings(orParts, " OR ")+")")
	}
	timeCol := "b.create_time"
	if q.TimeField == "modify" {
		timeCol = "b.modify_time"
	}
	if q.StartTime != nil {
		where = append(where, timeCol+" >= ?")
		args = append(args, *q.StartTime)
	}
	if q.EndTime != nil {
		where = append(where, timeCol+" <= ?")
		args = append(args, *q.EndTime)
	}
	if q.NoLabel {
		where = append(where, "NOT EXISTS (SELECT 1 FROM md_label_relation r WHERE r.resource_id = b.bookmark_id AND r.relation_type = 'bookmark')")
	}

	whereClause := ""
	if len(where) > 0 {
		whereClause = "WHERE " + joinStrings(where, " AND ")
	}

	rows, err := DB.Query("SELECT b.bookmark_id FROM md_bookmark b "+whereClause+" ORDER BY b.bookmark_id", args...)
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
