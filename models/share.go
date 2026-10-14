package models

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"strings"
	"time"
)

type Share struct {
	ShareID       int64     `json:"share_id"`
	ShareType     string    `json:"share_type"`
	ShareIdentify string    `json:"share_identify"`
	TargetID      int64     `json:"target_id"`
	MemberID      int64     `json:"member_id"`
	ShareTime     time.Time `json:"share_time"`
	IsPinned      bool      `json:"is_pinned"`
	EditToken     string    `json:"edit_token,omitempty"`
}

type ShareItem struct {
	ShareID       int64     `json:"share_id"`
	ShareType     string    `json:"share_type"`
	ShareIdentify string    `json:"share_identify"`
	TargetID      int64     `json:"target_id"`
	Title         string    `json:"title"`
	Author        string    `json:"author"`
	ShareTime     time.Time `json:"share_time"`
	Labels        []string  `json:"labels"`
	BookName      string    `json:"book_name,omitempty"`
	HasPassword   bool      `json:"has_password"`
	IsPinned      bool      `json:"is_pinned"`
	BlogType      string    `json:"blog_type,omitempty"`
	DocType       string    `json:"doc_type,omitempty"`
	Content       string    `json:"content,omitempty"`
	DocCount      int       `json:"doc_count,omitempty"`
	Description   string    `json:"description,omitempty"`
}

type ShareDetail struct {
	ShareItem
	Content     string         `json:"content"`
	ContentURL  string         `json:"content_url,omitempty"`
	HasPassword bool           `json:"has_password"`
	DocType     string         `json:"doc_type,omitempty"`
	DocTree     []*DocTreeNode `json:"doc_tree,omitempty"`
}

func CreateShare(shareType string, targetID, memberID int64, editToken string) (*Share, error) {
	identify := fmt.Sprintf("share-%d", time.Now().UnixNano())
	now := time.Now()
	result, err := DB.Exec(
		"INSERT OR IGNORE INTO md_shares (share_type, share_identify, target_id, member_id, share_time, edit_token) VALUES (?, ?, ?, ?, ?, ?)",
		shareType, identify, targetID, memberID, now, editToken,
	)
	if err != nil {
		return nil, err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		log.Printf("CreateShare: RowsAffected failed: %v", err)
	}
	if rowsAffected == 0 {
		// Record already exists, fetch the existing one
		existing, err := GetShareByTypeAndTarget(shareType, targetID)
		if err != nil {
			return nil, err
		}
		return existing, nil
	}

	return &Share{ShareType: shareType, ShareIdentify: identify, TargetID: targetID, MemberID: memberID, ShareTime: now, EditToken: editToken}, nil
}

func GetShareByTypeAndTarget(shareType string, targetID int64) (*Share, error) {
	s := &Share{}
	err := DB.QueryRow(
		"SELECT share_id, share_type, share_identify, target_id, member_id, share_time, is_pinned, edit_token FROM md_shares WHERE share_type = ? AND target_id = ?",
		shareType, targetID,
	).Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime, &s.IsPinned, &s.EditToken)
	if err != nil {
		return nil, err
	}
	return s, nil
}

func DeleteShare(shareType string, targetID int64) error {
	_, err := DB.Exec("DELETE FROM md_shares WHERE share_type = ? AND target_id = ?", shareType, targetID)
	return err
}

// Removing a public blog's share row alone would leave it in the public feed.
// Explicitly make it private in the same transaction; never delete the content.
func UnpublishPublicShare(shareType string, targetID int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if shareType == "blog" {
		if _, err = tx.Exec("UPDATE md_blogs SET visibility=0 WHERE blog_id=?", targetID); err != nil {
			return err
		}
	}
	if _, err = tx.Exec("DELETE FROM md_shares WHERE share_type=? AND target_id=?", shareType, targetID); err != nil {
		return err
	}
	return tx.Commit()
}

// GetShareMemberID returns the member_id of a share record
func GetShareMemberID(shareType string, targetID int64) (int64, error) {
	var memberID int64
	err := DB.QueryRow("SELECT member_id FROM md_shares WHERE share_type = ? AND target_id = ?", shareType, targetID).Scan(&memberID)
	if err != nil {
		return 0, err
	}
	return memberID, nil
}

func GetShareStatus(shareType string, ids []int64) (map[int64]bool, error) {
	if len(ids) == 0 {
		return map[int64]bool{}, nil
	}
	query := "SELECT target_id FROM md_shares WHERE share_type = ? AND target_id IN ("
	args := []any{shareType}
	for i, id := range ids {
		if i > 0 {
			query += ","
		}
		query += "?"
		args = append(args, id)
	}
	query += ")"

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[int64]bool)
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		result[id] = true
	}
	return result, nil
}

// ListSharesPaged returns paginated shares. filter: "article", "note", "book", or "" (all).
type PublicFeedOptions struct {
	Label string
	Sort  string
}

func ListSharesPaged(page, pageSize int, keyword, filter string, options ...PublicFeedOptions) ([]ShareItem, int64, error) {
	blogSharePart := `SELECT s.share_id, s.share_type, s.share_identify, s.target_id, s.share_time,
			b.blog_title AS title, m.account AS author, '' AS book_name,
			CASE WHEN b.password != '' THEN 1 ELSE 0 END AS has_password,
			CASE WHEN s.is_pinned = 1 OR b.is_pinned = 1 THEN 1 ELSE 0 END AS is_pinned,
			COALESCE(b.blog_type, 'article') AS blog_type,
			COALESCE(b.editor_type, 'markdown') AS doc_type,
			COALESCE(b.blog_content, '') AS content, 0 AS doc_count, COALESCE(b.blog_desc, '') AS description
		FROM md_shares s
		JOIN md_blogs b ON s.target_id=b.blog_id
		LEFT JOIN md_members m ON s.member_id=m.member_id
		WHERE s.share_type='blog' AND COALESCE(b.visibility, 0) = 1`

	bookSharePart := `SELECT s.share_id, s.share_type, s.share_identify, s.target_id, s.share_time,
			bk.book_name AS title, m.account AS author, '' AS book_name,
			0 AS has_password, COALESCE(s.is_pinned, 0) AS is_pinned,
			'' AS blog_type, '' AS doc_type, '' AS content,
			COALESCE(bk.doc_count, 0) AS doc_count, COALESCE(bk.description, '') AS description
		FROM md_shares s
		JOIN md_books bk ON s.target_id=bk.book_id
		LEFT JOIN md_members m ON s.member_id=m.member_id
		WHERE s.share_type='book'`

	publicBlogPart := `SELECT -b.blog_id, 'blog', b.blog_identify, b.blog_id, b.modify_time,
			b.blog_title, m.account, '',
			CASE WHEN b.password != '' THEN 1 ELSE 0 END,
			COALESCE(b.is_pinned, 0), COALESCE(b.blog_type, 'article'),
			COALESCE(b.editor_type, 'markdown'), COALESCE(b.blog_content, ''), 0, COALESCE(b.blog_desc, '')
		FROM md_blogs b
		LEFT JOIN md_members m ON b.member_id=m.member_id
		WHERE COALESCE(b.visibility, 0) = 1
			AND b.blog_id NOT IN (SELECT target_id FROM md_shares WHERE share_type='blog')`

	if len(options) > 0 {
		blogSharePart = strings.Replace(blogSharePart, "s.share_time,", "s.share_time, COALESCE(b.modify_time,s.share_time) AS updated_time,", 1)
		bookSharePart = strings.Replace(bookSharePart, "s.share_time,", "s.share_time, COALESCE(bk.modify_time,s.share_time) AS updated_time,", 1)
		publicBlogPart = strings.Replace(publicBlogPart, "b.modify_time,", "b.create_time, COALESCE(b.modify_time,b.create_time) AS updated_time,", 1)
	}
	var parts []string
	switch filter {
	case "article":
		parts = []string{
			blogSharePart + " AND COALESCE(b.blog_type, 'article') = 'article'",
			publicBlogPart + " AND COALESCE(b.blog_type, 'article') = 'article'",
		}
	case "note":
		parts = []string{
			blogSharePart + " AND b.blog_type = 'note'",
			publicBlogPart + " AND b.blog_type = 'note'",
		}
	case "book":
		parts = []string{bookSharePart}
	default:
		parts = []string{blogSharePart, bookSharePart, publicBlogPart}
	}

	baseQuery := `SELECT share_id, share_type, share_identify, target_id, share_time, title, author, book_name, has_password, is_pinned, blog_type, doc_type, content, doc_count, description FROM (` +
		strings.Join(parts, " UNION ALL ") + `)`
	if len(options) > 0 {
		baseQuery = strings.Replace(baseQuery, "SELECT share_id,", "SELECT updated_time, share_id,", 1)
	}

	countQuery := `SELECT COUNT(*) FROM (` + baseQuery + `)`

	var args []any
	where := ""
	if keyword != "" {
		kw := "%" + keyword + "%"
		switch filter {
		case "book":
			where = ` WHERE title LIKE ?`
			args = append(args, kw)
		case "article", "note":
			where = ` WHERE (title LIKE ? OR description LIKE ? OR target_id IN (SELECT r.resource_id FROM md_label_relation r JOIN md_label l ON r.label_id=l.label_id WHERE l.label_name LIKE ? AND r.relation_type='blog'))`
			args = append(args, kw, kw, kw)
		default:
			where = ` WHERE (
				(share_type='blog' AND (title LIKE ? OR description LIKE ? OR target_id IN (SELECT r.resource_id FROM md_label_relation r JOIN md_label l ON r.label_id=l.label_id WHERE l.label_name LIKE ? AND r.relation_type='blog')))
				OR (share_type='book' AND title LIKE ?)
			)`
			args = append(args, kw, kw, kw, kw)
		}
	}

	if len(options) > 0 && options[0].Label != "" {
		if where == "" {
			where = " WHERE "
		} else {
			where += " AND "
		}
		where += `EXISTS (SELECT 1 FROM md_label_relation r JOIN md_label l ON l.label_id=r.label_id WHERE r.resource_id=target_id AND r.relation_type=share_type AND l.label_name=?)`
		args = append(args, options[0].Label)
	}
	var total int64
	if err := DB.QueryRow(countQuery+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	query := baseQuery + where + " ORDER BY is_pinned DESC, share_time DESC LIMIT ? OFFSET ?"
	if len(options) > 0 {
		order := "share_time"
		if options[0].Sort == "updated" {
			order = "updated_time"
		}
		query = "SELECT share_id, share_type, share_identify, target_id, share_time, title, author, book_name, has_password, is_pinned, blog_type, doc_type, content, doc_count, description FROM (" + baseQuery + where + ") ORDER BY is_pinned DESC, " + order + " DESC, share_id DESC LIMIT ? OFFSET ?"
	}
	args = append(args, pageSize, offset)

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []ShareItem
	for rows.Next() {
		var item ShareItem
		var hasPwd int
		var isPinned int
		if err := rows.Scan(&item.ShareID, &item.ShareType, &item.ShareIdentify, &item.TargetID, &item.ShareTime, &item.Title, &item.Author, &item.BookName, &hasPwd, &isPinned, &item.BlogType, &item.DocType, &item.Content, &item.DocCount, &item.Description); err != nil {
			return nil, 0, err
		}
		item.HasPassword = hasPwd == 1
		item.IsPinned = isPinned == 1
		item.Labels = []string{}
		// Apply same preview extraction as blog list
		if item.ShareType == "blog" {
			if item.HasPassword {
				item.Description = ""
				item.Content = "内容已加密"
			} else if item.Description != "" {
				item.Content = item.Description
			} else if item.DocType == "html" {
				item.Content = ""
			} else if item.BlogType == "note" {
				item.Content = extractTextPreview(item.DocType, item.Content)
			} else {
				item.Content = extractTextPreview(item.DocType, item.Content)
				runes := []rune(item.Content)
				if len(runes) > 200 {
					item.Content = string(runes[:200])
				}
			}
		} else {
			item.Content = ""
		}
		items = append(items, item)
	}
	rows.Close()

	// Batch load labels for blog-type and book-type shares
	var blogIDs []int64
	var bookIDs []int64
	for _, item := range items {
		if item.ShareType == "blog" {
			blogIDs = append(blogIDs, item.TargetID)
		} else if item.ShareType == "book" {
			bookIDs = append(bookIDs, item.TargetID)
		}
	}
	if len(blogIDs) > 0 {
		labelMap, err := BatchGetLabelsByResources(blogIDs, "blog")
		if err != nil {
			log.Printf("ListSharesPaged: BatchGetLabelsByResources for blogs failed: %v", err)
		}
		for i := range items {
			if items[i].ShareType == "blog" {
				if labels, ok := labelMap[items[i].TargetID]; ok {
					items[i].Labels = labels
				}
			}
		}
	}
	if len(bookIDs) > 0 {
		labelMap, err := BatchGetLabelsByResources(bookIDs, "book")
		if err != nil {
			log.Printf("ListSharesPaged: BatchGetLabelsByResources for books failed: %v", err)
		}
		for i := range items {
			if items[i].ShareType == "book" {
				if labels, ok := labelMap[items[i].TargetID]; ok {
					items[i].Labels = labels
				}
			}
		}
	}
	return items, total, nil
}

func GetShareDetailByIdentify(identify string) (*ShareDetail, error) {
	// First try to find in md_shares
	var s Share
	err := DB.QueryRow("SELECT share_id, share_type, share_identify, target_id, member_id, share_time, is_pinned FROM md_shares WHERE share_identify = ?", identify).
		Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime, &s.IsPinned)

	if err == nil {
		// Found in md_shares — existing logic
		var account string
		if err := DB.QueryRow("SELECT account FROM md_members WHERE member_id = ?", s.MemberID).Scan(&account); err != nil {
			log.Printf("GetShareDetailByIdentify: query account for member_id=%d: %v", s.MemberID, err)
		}

		detail := &ShareDetail{
			ShareItem: ShareItem{
				ShareID:       s.ShareID,
				ShareType:     s.ShareType,
				ShareIdentify: s.ShareIdentify,
				TargetID:      s.TargetID,
				Author:        account,
				ShareTime:     s.ShareTime,
				IsPinned:      s.IsPinned,
			},
		}

		if s.ShareType == "blog" {
			blog, err := GetBlogByID(s.TargetID)
			if err != nil {
				return nil, err
			}
			if blog.Visibility != 1 {
				return nil, fmt.Errorf("not found")
			}
			detail.Title = blog.BlogTitle
			detail.DocType = blog.EditorType
			detail.HasPassword = blog.HasPassword()
			if blog.HasPassword() {
				detail.Content = ""
			} else {
				detail.Description = blog.BlogDesc
				detail.Content = blog.BlogContent
			}
			labels, err := GetLabelsByResource(s.TargetID, "blog")
			if err != nil {
				log.Printf("GetShareDetailByIdentify: GetLabelsByResource failed: %v", err)
			}
			if labels == nil {
				labels = []string{}
			}
			detail.Labels = labels
		} else if s.ShareType == "book" {
			book, err := GetBookByID(s.TargetID)
			if err != nil {
				return nil, err
			}
			detail.Title = book.BookName
			detail.BookName = book.BookName
			detail.DocCount = book.DocCount
			tree, err := GetDocTree(s.TargetID)
			if err != nil {
				log.Printf("GetShareDetailByIdentify: GetDocTree failed: %v", err)
			}
			detail.DocTree = tree
			labels, err := GetLabelsByResource(s.TargetID, "book")
			if err != nil {
				log.Printf("GetShareDetailByIdentify: GetLabelsByResource for book failed: %v", err)
			}
			if labels == nil {
				labels = []string{}
			}
			detail.Labels = labels
		} else {
			doc, err := GetDocumentByID(s.TargetID)
			if err != nil {
				return nil, err
			}
			detail.Title = doc.DocumentName
			detail.Content = doc.Markdown
			detail.DocType = doc.DocType
			docLabels, lblErr := GetLabelsByResource(s.TargetID, "document")
			if lblErr != nil {
				log.Printf("GetShareDetailByIdentify: GetLabelsByResource for document failed: %v", lblErr)
			}
			if docLabels == nil {
				docLabels = []string{}
			}
			detail.Labels = docLabels
			var bookName string
			if err := DB.QueryRow("SELECT book_name FROM md_books WHERE book_id = ?", doc.BookID).Scan(&bookName); err != nil {
				log.Printf("GetShareDetailByIdentify: query book_name for book_id=%d: %v", doc.BookID, err)
			}
			detail.BookName = bookName
		}

		return detail, nil
	}

	// Not in md_shares — try as a public note (blog_identify)
	var blog Blog
	err = DB.QueryRow(
		"SELECT blog_id, blog_title, blog_identify, member_id, blog_content, COALESCE(blog_desc,''), password, modify_time, modify_at, create_time, version, COALESCE(blog_type,'article'), COALESCE(editor_type,'markdown'), COALESCE(visibility,0), COALESCE(is_pinned,0), COALESCE(pin_order,0) FROM md_blogs WHERE blog_identify = ?",
		identify,
	).Scan(&blog.BlogID, &blog.BlogTitle, &blog.BlogIdentify, &blog.MemberID, &blog.BlogContent, &blog.BlogDesc, &blog.Password, &blog.ModifyTime, &blog.ModifyAt, &blog.CreateTime, &blog.Version, &blog.BlogType, &blog.EditorType, &blog.Visibility, &blog.IsPinned, &blog.PinOrder)
	if err != nil {
		return nil, err
	}

	// Only allow access to public blogs
	if blog.Visibility != 1 {
		return nil, fmt.Errorf("not found")
	}

	var account string
	if err := DB.QueryRow("SELECT account FROM md_members WHERE member_id = ?", blog.MemberID).Scan(&account); err != nil {
		log.Printf("GetShareDetailByIdentify: query account for member_id=%d: %v", blog.MemberID, err)
	}

	detail := &ShareDetail{
		ShareItem: ShareItem{
			ShareID:       -blog.BlogID,
			ShareType:     "blog",
			ShareIdentify: blog.BlogIdentify,
			TargetID:      blog.BlogID,
			Title:         blog.BlogTitle,
			Author:        account,
			ShareTime:     blog.ModifyTime,
			IsPinned:      blog.IsPinned != 0,
			BlogType:      blog.BlogType,
			DocType:       blog.EditorType,
		},
		DocType: blog.EditorType,
	}

	if blog.HasPassword() {
		detail.HasPassword = true
		detail.Content = ""
	} else {
		detail.Description = blog.BlogDesc
		detail.Content = blog.BlogContent
	}

	labels, err := GetLabelsByResource(blog.BlogID, "blog")
	if err != nil {
		log.Printf("GetShareDetailByIdentify: GetLabelsByResource for public note failed: %v", err)
	}
	if labels == nil {
		labels = []string{}
	}
	detail.Labels = labels

	return detail, nil
}

func ToggleSharePin(shareType string, targetID int64) (bool, error) {
	var current int
	err := DB.QueryRow("SELECT is_pinned FROM md_shares WHERE share_type = ? AND target_id = ?", shareType, targetID).Scan(&current)
	if err == sql.ErrNoRows {
		// No share record — auto-create one for public blogs (visibility=1)
		if shareType == "blog" {
			var identify string
			var memberID int64
			if e := DB.QueryRow("SELECT blog_identify, member_id FROM md_blogs WHERE blog_id = ? AND visibility = 1", targetID).Scan(&identify, &memberID); e != nil {
				return false, fmt.Errorf("该内容尚未公开分享，无法置顶")
			}
			// Clear all other pinned items (both md_shares and md_blogs)
			DB.Exec("UPDATE md_shares SET is_pinned = 0 WHERE share_type = ? AND is_pinned = 1", shareType)
			DB.Exec("UPDATE md_blogs SET is_pinned = 0 WHERE is_pinned = 1")
			_, err = DB.Exec("INSERT INTO md_shares (share_type, share_identify, target_id, member_id, share_time, is_pinned) VALUES (?, ?, ?, ?, datetime('now'), 1)", shareType, identify, targetID, memberID)
			if err != nil {
				return false, err
			}
			return true, nil
		}
		return false, fmt.Errorf("该内容尚未公开分享，无法置顶")
	}
	if err != nil {
		return false, err
	}
	if current == 0 {
		// Pinning: clear all other pinned items first to ensure exclusivity
		DB.Exec("UPDATE md_shares SET is_pinned = 0 WHERE share_type = ? AND is_pinned = 1", shareType)
		DB.Exec("UPDATE md_blogs SET is_pinned = 0 WHERE is_pinned = 1")
		if _, err := DB.Exec("UPDATE md_shares SET is_pinned = 1 WHERE share_type = ? AND target_id = ?", shareType, targetID); err != nil {
			return false, err
		}
		return true, nil
	}
	// Unpinning: clear both md_shares and md_blogs
	if _, err := DB.Exec("UPDATE md_shares SET is_pinned = 0 WHERE share_type = ? AND target_id = ?", shareType, targetID); err != nil {
		return false, err
	}
	DB.Exec("UPDATE md_blogs SET is_pinned = 0 WHERE blog_id = ?", targetID)
	return false, nil
}

func CleanupSharesForPrivateBlog(blogID int64) {
	_, err := DB.Exec("DELETE FROM md_shares WHERE share_type='blog' AND target_id=?", blogID)
	if err != nil {
		log.Printf("CleanupSharesForPrivateBlog failed: blog_id=%d err=%v", blogID, err)
	}
}

func AutoCreateShareForPublicBlog(blog *Blog) {
	if blog.Visibility != 1 {
		return
	}
	existing, _ := GetShareByTypeAndTarget("blog", blog.BlogID)
	if existing != nil {
		return
	}
	CreateShare("blog", blog.BlogID, blog.MemberID, "")
}

func GenerateEditToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func SetEditToken(shareType string, targetID int64, token string) error {
	_, err := DB.Exec(
		"UPDATE md_shares SET edit_token = ? WHERE share_type = ? AND target_id = ?",
		token, shareType, targetID,
	)
	return err
}

func GetEditToken(shareType string, targetID int64) (string, error) {
	var token string
	err := DB.QueryRow(
		"SELECT edit_token FROM md_shares WHERE share_type = ? AND target_id = ?",
		shareType, targetID,
	).Scan(&token)
	if err != nil {
		return "", err
	}
	return token, nil
}

func GetShareByIdentifyWithToken(identify string) (*Share, error) {
	var s Share
	err := DB.QueryRow(
		"SELECT share_id, share_type, share_identify, target_id, member_id, share_time, is_pinned, edit_token FROM md_shares WHERE share_identify = ?",
		identify,
	).Scan(&s.ShareID, &s.ShareType, &s.ShareIdentify, &s.TargetID, &s.MemberID, &s.ShareTime, &s.IsPinned, &s.EditToken)
	if err != nil {
		return nil, err
	}
	return &s, nil
}
