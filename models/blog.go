package models

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"golang.org/x/crypto/pbkdf2"
)

const (
	encPrefix   = "ENC:v1:"
	pbkdf2Iters = 100000
	keyLen      = 32 // AES-256
	saltLen     = 16
	nonceLen    = 12 // GCM standard nonce
)

// EncryptContent encrypts plaintext with the given password using AES-256-GCM.
// Returns a string in the format: ENC:v1:<base64(salt)>:<base64(nonce)>:<base64(ciphertext)>
func EncryptContent(password, plaintext string) (string, error) {
	if password == "" {
		return plaintext, nil
	}
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("生成盐失败: %w", err)
	}
	key := pbkdf2.Key([]byte(password), salt, pbkdf2Iters, keyLen, sha256.New)
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("创建加密块失败: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("创建GCM失败: %w", err)
	}
	nonce := make([]byte, nonceLen)
	if _, err := rand.Read(nonce); err != nil {
		return "", fmt.Errorf("生成nonce失败: %w", err)
	}
	ciphertext := gcm.Seal(nil, nonce, []byte(plaintext), nil)
	return encPrefix + base64.StdEncoding.EncodeToString(salt) + ":" +
		base64.StdEncoding.EncodeToString(nonce) + ":" +
		base64.StdEncoding.EncodeToString(ciphertext), nil
}

// DecryptContent decrypts content encrypted by EncryptContent.
func DecryptContent(password, encrypted string) (string, error) {
	if password == "" || !strings.HasPrefix(encrypted, encPrefix) {
		return encrypted, nil
	}
	data := encrypted[len(encPrefix):]
	parts := strings.SplitN(data, ":", 3)
	if len(parts) != 3 {
		return "", fmt.Errorf("加密数据格式错误")
	}
	salt, err := base64.StdEncoding.DecodeString(parts[0])
	if err != nil {
		return "", fmt.Errorf("解码盐失败: %w", err)
	}
	nonce, err := base64.StdEncoding.DecodeString(parts[1])
	if err != nil {
		return "", fmt.Errorf("解码nonce失败: %w", err)
	}
	ciphertext, err := base64.StdEncoding.DecodeString(parts[2])
	if err != nil {
		return "", fmt.Errorf("解码密文失败: %w", err)
	}
	key := pbkdf2.Key([]byte(password), salt, pbkdf2Iters, keyLen, sha256.New)
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("创建解密块失败: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("创建GCM失败: %w", err)
	}
	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", fmt.Errorf("解密失败，密码可能不正确")
	}
	return string(plaintext), nil
}

// IsEncrypted checks if content is encrypted (starts with ENC:v1:)
func IsEncrypted(content string) bool {
	return strings.HasPrefix(content, encPrefix)
}

type Blog struct {
	BlogID           int64     `json:"blog_id"`
	BlogTitle        string    `json:"blog_title"`
	BlogIdentify     string    `json:"blog_identify"`
	MemberID         int64     `json:"member_id"`
	BlogContent      string    `json:"blog_content"`
	BlogDesc         string    `json:"blog_desc"`
	Password         string    `json:"-"`
	ModifyTime       time.Time `json:"modify_time"`
	ModifyAt         int64     `json:"modify_at"`
	CreateTime       time.Time `json:"create_time"`
	Version          int       `json:"version"`
	BlogType         string    `json:"blog_type"`
	EditorType       string    `json:"editor_type"`
	Visibility       int       `json:"visibility"`
	IsPinned         int       `json:"is_pinned"`
	PinOrder         int       `json:"pin_order"`
	LocationName     string    `json:"location_name,omitempty"`
	Latitude         *float64  `json:"latitude,omitempty"`
	Longitude        *float64  `json:"longitude,omitempty"`
	LocationAccuracy *float64  `json:"location_accuracy,omitempty"`
}

type BlogWithLabels struct {
	BlogID           int64     `json:"blog_id"`
	BlogTitle        string    `json:"blog_title"`
	BlogIdentify     string    `json:"blog_identify"`
	MemberID         int64     `json:"member_id"`
	ModifyTime       time.Time `json:"modify_time"`
	CreateTime       time.Time `json:"create_time"`
	Version          int       `json:"version"`
	BlogType         string    `json:"blog_type"`
	EditorType       string    `json:"editor_type"`
	Visibility       int       `json:"visibility"`
	IsPinned         int       `json:"is_pinned"`
	PinOrder         int       `json:"pin_order"`
	LocationName     string    `json:"location_name,omitempty"`
	Latitude         *float64  `json:"latitude,omitempty"`
	Longitude        *float64  `json:"longitude,omitempty"`
	LocationAccuracy *float64  `json:"location_accuracy,omitempty"`
	BlogDesc         string    `json:"blog_desc"`
	ContentPreview   string    `json:"content_preview,omitempty"`
	Labels           []string  `json:"labels"`
	HasPassword      bool      `json:"has_password"`
}

var (
	htmlTagRe         = regexp.MustCompile(`<[^>]*>`)
	htmlStyleScriptRe = regexp.MustCompile(`(?s)<style[^>]*>.*?</style>|<script[^>]*>.*?</script>`)
	mindmapTopicRe    = regexp.MustCompile(`"topic":"([^"]+)"`)
	excalidrawTextRe  = regexp.MustCompile(`"text":"([^"]+)"`)
)

func extractTextPreview(editorType, raw string) string {
	if raw == "" {
		return ""
	}
	switch editorType {
	case RichDocumentType:
		return extractRichDocumentText(raw)
	case "spreadsheet":
		return extractSpreadsheetText(raw)
	case PresentationType:
		return ""
	case "mindmap":
		return extractMindmapText(raw)
	case "drawing":
		return extractDrawingText(raw)
	case "html":
		return extractHtmlText(raw)
	default:
		return raw
	}
}

func extractDrawingText(raw string) string {
	matches := excalidrawTextRe.FindAllStringSubmatch(raw, 30)
	var parts []string
	for _, m := range matches {
		t := strings.TrimSpace(m[1])
		if t != "" {
			parts = append(parts, t)
		}
	}
	result := strings.Join(parts, " | ")
	if len([]rune(result)) > 200 {
		return string([]rune(result)[:200])
	}
	return result
}

func extractHtmlText(raw string) string {
	// Remove <style> and <script> blocks (content + tags) first
	text := htmlStyleScriptRe.ReplaceAllString(raw, "")
	// Then remove all remaining HTML tags
	text = htmlTagRe.ReplaceAllString(text, " ")
	text = strings.Join(strings.Fields(text), " ")
	if len([]rune(text)) > 200 {
		return string([]rune(text)[:200])
	}
	return text
}

func extractSpreadsheetText(raw string) string {
	seen := make(map[string]bool)
	var parts []string
	appendValue := func(value any) {
		if len(parts) >= 30 || value == nil {
			return
		}
		v := strings.TrimSpace(fmt.Sprint(value))
		if v == "" || seen[v] {
			return
		}
		seen[v] = true
		parts = append(parts, v)
	}

	var snapshot struct {
		SheetOrder []string `json:"sheetOrder"`
		Sheets     map[string]struct {
			CellData map[string]map[string]struct {
				Value any `json:"v"`
			} `json:"cellData"`
		} `json:"sheets"`
	}
	if json.Unmarshal([]byte(raw), &snapshot) == nil && len(snapshot.Sheets) > 0 {
		for _, sheetID := range snapshot.SheetOrder {
			sheet, ok := snapshot.Sheets[sheetID]
			if !ok {
				continue
			}
			for _, row := range sheet.CellData {
				for _, cell := range row {
					appendValue(cell.Value)
				}
			}
		}
	}
	result := strings.Join(parts, " | ")
	if len([]rune(result)) > 200 {
		return string([]rune(result)[:200])
	}
	return result
}

func extractMindmapText(raw string) string {
	matches := mindmapTopicRe.FindAllStringSubmatch(raw, 30)
	var parts []string
	for _, m := range matches {
		t := strings.TrimSpace(m[1])
		if t != "" {
			parts = append(parts, t)
		}
	}
	result := strings.Join(parts, " → ")
	if len([]rune(result)) > 200 {
		return string([]rune(result)[:200])
	}
	return result
}

func float64Ptr(v sql.NullFloat64) *float64 {
	if !v.Valid {
		return nil
	}
	return &v.Float64
}

func GetBlogByID(id int64) (*Blog, error) {
	b := &Blog{}
	var lat, lng, accuracy sql.NullFloat64
	err := DB.QueryRow(
		"SELECT blog_id, blog_title, blog_identify, member_id, blog_content, COALESCE(blog_desc,''), password, modify_time, modify_at, create_time, version, COALESCE(blog_type,'article'), COALESCE(editor_type,'markdown'), COALESCE(visibility,0), COALESCE(is_pinned,0), COALESCE(pin_order,0), COALESCE(location_name,''), latitude, longitude, location_accuracy FROM md_blogs WHERE blog_id = ?",
		id,
	).Scan(&b.BlogID, &b.BlogTitle, &b.BlogIdentify, &b.MemberID, &b.BlogContent, &b.BlogDesc, &b.Password, &b.ModifyTime, &b.ModifyAt, &b.CreateTime, &b.Version, &b.BlogType, &b.EditorType, &b.Visibility, &b.IsPinned, &b.PinOrder, &b.LocationName, &lat, &lng, &accuracy)
	if err != nil {
		return nil, err
	}
	b.Latitude = float64Ptr(lat)
	b.Longitude = float64Ptr(lng)
	b.LocationAccuracy = float64Ptr(accuracy)
	return b, nil
}

func GetBlogByIdentify(identify string) (*Blog, error) {
	b := &Blog{}
	var lat, lng, accuracy sql.NullFloat64
	err := DB.QueryRow(
		"SELECT blog_id, blog_title, blog_identify, member_id, blog_content, COALESCE(blog_desc,''), password, modify_time, modify_at, create_time, version, COALESCE(blog_type,'article'), COALESCE(editor_type,'markdown'), COALESCE(visibility,0), COALESCE(is_pinned,0), COALESCE(pin_order,0), COALESCE(location_name,''), latitude, longitude, location_accuracy FROM md_blogs WHERE blog_identify = ?",
		identify,
	).Scan(&b.BlogID, &b.BlogTitle, &b.BlogIdentify, &b.MemberID, &b.BlogContent, &b.BlogDesc, &b.Password, &b.ModifyTime, &b.ModifyAt, &b.CreateTime, &b.Version, &b.BlogType, &b.EditorType, &b.Visibility, &b.IsPinned, &b.PinOrder, &b.LocationName, &lat, &lng, &accuracy)
	if err != nil {
		return nil, err
	}
	b.Latitude = float64Ptr(lat)
	b.Longitude = float64Ptr(lng)
	b.LocationAccuracy = float64Ptr(accuracy)
	return b, nil
}

// HashPassword hashes the blog password if not empty
func (b *Blog) HashPassword() error {
	if b.Password != "" {
		hashed, err := bcrypt.GenerateFromPassword([]byte(b.Password), bcrypt.DefaultCost)
		if err != nil {
			return err
		}
		b.Password = string(hashed)
	}
	return nil
}

// VerifyPassword checks if the plain password matches the stored hash
func (b *Blog) VerifyPassword(plain string) bool {
	if b.Password == "" {
		return plain == ""
	}
	err := bcrypt.CompareHashAndPassword([]byte(b.Password), []byte(plain))
	return err == nil
}

// HasPassword returns whether the blog has a password set
func (b *Blog) HasPassword() bool {
	return b.Password != ""
}

// BlogTitleExists 检查同一用户下是否已存在同名博客（excludeID 用于更新时排除自身）
// 仅对文章（blog_type='article'）生效，笔记允许标题重复
func BlogTitleExists(title string, memberID int64, excludeID int64) (bool, error) {
	var count int
	if excludeID > 0 {
		err := DB.QueryRow("SELECT COUNT(*) FROM md_blogs WHERE blog_title = ? AND member_id = ? AND blog_id != ? AND (blog_type = 'article' OR blog_type IS NULL)", title, memberID, excludeID).Scan(&count)
		return count > 0, err
	}
	err := DB.QueryRow("SELECT COUNT(*) FROM md_blogs WHERE blog_title = ? AND member_id = ? AND (blog_type = 'article' OR blog_type IS NULL)", title, memberID).Scan(&count)
	return count > 0, err
}

func (b *Blog) Insert() error {
	if b.BlogType == "" {
		b.BlogType = "article"
	}
	if b.EditorType == "" {
		b.EditorType = "markdown"
	}
	if b.EditorType == "spreadsheet" && b.BlogContent == "" {
		b.BlogContent = DefaultSpreadsheet
	}
	if b.EditorType == PresentationType && b.BlogContent == "" {
		b.BlogContent = DefaultPresentation(b.BlogTitle)
	}
	if b.EditorType == "drawing" && b.BlogContent == "" {
		b.BlogContent = `{"elements":[], "appState":{}}`
	}
	if b.EditorType == "mindmap" && b.BlogContent == "" {
		b.BlogContent = `{"nodeData":{"id":"root","topic":"新脑图","root":true,"children":[]},"linkData":{}}`
	}
	if b.EditorType == RichDocumentType && b.BlogContent == "" {
		b.BlogContent = DefaultRichDocument()
	}
	if (b.EditorType == "html" || b.EditorType == RichDocumentType) && !IsEncrypted(b.BlogContent) {
		encoded, err := EncodeContentForType(b.EditorType, b.BlogContent)
		if err != nil {
			return err
		}
		b.BlogContent = encoded
	}
	if b.Password != "" && !IsEncrypted(b.BlogContent) {
		encrypted, err := EncryptContent(b.Password, b.BlogContent)
		if err != nil {
			return err
		}
		b.BlogContent = encrypted
	}
	if err := b.HashPassword(); err != nil {
		return err
	}
	now := time.Now().Format("2006-01-02 15:04:05")
	result, err := DB.Exec(
		"INSERT INTO md_blogs (blog_title, blog_identify, member_id, blog_content, blog_desc, password, modify_time, create_time, version, blog_type, editor_type, visibility, is_pinned, pin_order, location_name, latitude, longitude, location_accuracy) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		b.BlogTitle, b.BlogIdentify, b.MemberID, b.BlogContent, b.BlogDesc, b.Password, now, now, b.BlogType, b.EditorType, b.Visibility, b.IsPinned, b.PinOrder, b.LocationName, b.Latitude, b.Longitude, b.LocationAccuracy,
	)
	if err != nil {
		return err
	}
	b.BlogID, _ = result.LastInsertId()
	if b.BlogID == 0 {
		log.Printf("Blog.Insert: LastInsertId returned 0")
	}
	return nil
}

// isBcryptHash checks if a string looks like a bcrypt hash (starts with $2a$, $2b$, or $2y$)
func isBcryptHash(s string) bool {
	return len(s) == 60 && (strings.HasPrefix(s, "$2a$") || strings.HasPrefix(s, "$2b$") || strings.HasPrefix(s, "$2y$"))
}

func (b *Blog) Update() error {
	if (b.EditorType == "html" || b.EditorType == RichDocumentType) && !IsEncrypted(b.BlogContent) {
		encoded, err := EncodeContentForType(b.EditorType, b.BlogContent)
		if err != nil {
			return err
		}
		b.BlogContent = encoded
	}
	now := time.Now().Format("2006-01-02 15:04:05")
	if b.Password != "" && !isBcryptHash(b.Password) {
		if err := b.HashPassword(); err != nil {
			return err
		}
	}
	_, err := DB.Exec(
		"UPDATE md_blogs SET blog_title = ?, blog_content = ?, blog_desc = ?, password = ?, modify_time = ?, modify_at = ?, version = version + 1, blog_type = ?, visibility = ?, is_pinned = ?, pin_order = ?, location_name = ?, latitude = ?, longitude = ?, location_accuracy = ? WHERE blog_id = ?",
		b.BlogTitle, b.BlogContent, b.BlogDesc, b.Password, now, b.ModifyAt, b.BlogType, b.Visibility, b.IsPinned, b.PinOrder, b.LocationName, b.Latitude, b.Longitude, b.LocationAccuracy, b.BlogID,
	)
	return err
}

func DeleteBlog(id int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Check if blog exists
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_blogs WHERE blog_id = ?", id).Scan(&count); err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("博客不存在")
	}

	// 快照到回收站
	snap, name, snapErr := SnapshotBlog(tx, id)
	if snapErr != nil {
		log.Printf("DeleteBlog: 快照失败: %v", snapErr)
	} else {
		var memberID int64
		if err := tx.QueryRow("SELECT member_id FROM md_blogs WHERE blog_id = ?", id).Scan(&memberID); err == nil {
			if err := CreateTrash(tx, "blog", name, snap, memberID); err != nil {
				log.Printf("DeleteBlog: 写入回收站失败: %v", err)
			}
		}
	}

	// Delete share records
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'blog' AND target_id = ?", id); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'blog'", id); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_blogs WHERE blog_id = ?", id); err != nil {
		return err
	}
	return tx.Commit()
}

func ListBlogsPagedWithLabels(memberID int64, page, pageSize int, keyword string, shared string, encrypted string, blogType string, visibility string, label string, date string, pinned string, editorType string, hasCode string) ([]BlogWithLabels, int64, error) {
	where := "WHERE 1=1"
	args := []interface{}{}
	if memberID > 0 {
		where += " AND b.member_id = ?"
		args = append(args, memberID)
	}
	if keyword != "" {
		where += " AND (b.blog_title LIKE ? OR b.blog_id IN (SELECT r.resource_id FROM md_label_relation r JOIN md_label l ON r.label_id = l.label_id WHERE l.label_name LIKE ? AND r.relation_type = 'blog'))"
		kw := "%" + keyword + "%"
		args = append(args, kw, kw)
	}
	if date != "" {
		where += " AND DATE(b.create_time) = ?"
		args = append(args, date)
	}
	if shared == "1" {
		where += " AND b.blog_id IN (SELECT target_id FROM md_shares WHERE share_type = 'blog')"
	} else if shared == "0" {
		where += " AND b.blog_id NOT IN (SELECT target_id FROM md_shares WHERE share_type = 'blog')"
	}
	if encrypted == "1" {
		where += " AND b.password != ''"
	} else if encrypted == "0" {
		where += " AND b.password = ''"
	}
	if blogType != "" {
		where += " AND b.blog_type = ?"
		args = append(args, blogType)
	}
	if visibility != "" {
		where += " AND b.visibility = ?"
		args = append(args, visibility)
	}
	if label != "" {
		where += " AND b.blog_id IN (SELECT lr.resource_id FROM md_label_relation lr JOIN md_label l ON lr.label_id = l.label_id WHERE l.label_name = ? AND lr.relation_type = 'blog')"
		args = append(args, label)
	}
	if pinned == "1" {
		where += " AND COALESCE(b.is_pinned,0) = 1"
	} else if pinned == "0" {
		where += " AND COALESCE(b.is_pinned,0) = 0"
	}
	if editorType != "" {
		where += " AND COALESCE(b.editor_type,'markdown') = ?"
		args = append(args, editorType)
	}
	if hasCode == "1" || hasCode == "true" {
		where += " AND COALESCE(b.editor_type,'markdown') != 'html' AND (COALESCE(b.blog_content,'') LIKE '%```%' OR COALESCE(b.blog_content,'') LIKE '%`_%`%')"
	}

	var total int64
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_blogs b "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	contentCol := "CASE WHEN b.password != '' THEN '' WHEN COALESCE(b.blog_desc,'') != '' THEN COALESCE(b.blog_desc,'') WHEN COALESCE(b.editor_type,'markdown') IN ('html','presentation') THEN '' WHEN COALESCE(b.editor_type,'markdown') IN ('spreadsheet','drawing','mindmap','richdoc') THEN COALESCE(b.blog_content,'') ELSE SUBSTR(COALESCE(b.blog_content,''), 1, 200) END"
	if blogType == "note" {
		contentCol = "CASE WHEN b.password != '' THEN '' WHEN COALESCE(b.blog_desc,'') != '' THEN COALESCE(b.blog_desc,'') WHEN COALESCE(b.editor_type,'markdown') = 'html' THEN '' ELSE COALESCE(b.blog_content,'') END"
	}
	query := "SELECT b.blog_id, b.blog_title, b.blog_identify, b.member_id, b.modify_time, b.create_time, b.version, CASE WHEN b.password != '' THEN 1 ELSE 0 END, COALESCE(b.blog_type,'article'), COALESCE(b.editor_type,'markdown'), COALESCE(b.visibility,0), COALESCE(b.is_pinned,0), COALESCE(b.pin_order,0), COALESCE(b.location_name,''), b.latitude, b.longitude, b.location_accuracy, COALESCE(b.blog_desc,''), " + contentCol + " FROM md_blogs b " + where + " ORDER BY COALESCE(b.is_pinned,0) DESC, COALESCE(b.pin_order,0) ASC, b.modify_time DESC LIMIT ? OFFSET ?"
	args = append(args, pageSize, offset)

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var blogs []BlogWithLabels
	var blogIDs []int64
	for rows.Next() {
		var b BlogWithLabels
		var hasPwd int
		var lat, lng, accuracy sql.NullFloat64
		if err := rows.Scan(&b.BlogID, &b.BlogTitle, &b.BlogIdentify, &b.MemberID, &b.ModifyTime, &b.CreateTime, &b.Version, &hasPwd, &b.BlogType, &b.EditorType, &b.Visibility, &b.IsPinned, &b.PinOrder, &b.LocationName, &lat, &lng, &accuracy, &b.BlogDesc, &b.ContentPreview); err != nil {
			return nil, 0, err
		}
		b.HasPassword = hasPwd == 1
		b.Latitude = float64Ptr(lat)
		b.Longitude = float64Ptr(lng)
		b.LocationAccuracy = float64Ptr(accuracy)
		if strings.TrimSpace(b.BlogDesc) == "" {
			b.ContentPreview = extractTextPreview(b.EditorType, b.ContentPreview)
		}
		blogs = append(blogs, b)
		blogIDs = append(blogIDs, b.BlogID)
	}

	// Batch load labels
	labelMap, err := BatchGetLabelsByResources(blogIDs, "blog")
	if err != nil {
		log.Printf("ListBlogsPagedWithLabels: BatchGetLabelsByResources failed: %v", err)
	}
	for i := range blogs {
		if labels, ok := labelMap[blogs[i].BlogID]; ok {
			blogs[i].Labels = labels
		} else {
			blogs[i].Labels = []string{}
		}
	}

	return blogs, total, nil
}

// BatchGetLabelsByResources 批量获取多个资源的标签
func BatchGetLabelsByResources(resourceIDs []int64, relationType string) (map[int64][]string, error) {
	if len(resourceIDs) == 0 {
		return map[int64][]string{}, nil
	}
	placeholders := ""
	args := []interface{}{relationType}
	for i, id := range resourceIDs {
		if i > 0 {
			placeholders += ","
		}
		placeholders += "?"
		args = append(args, id)
	}
	query := "SELECT r.resource_id, l.label_name FROM md_label_relation r JOIN md_label l ON r.label_id = l.label_id WHERE r.relation_type = ? AND r.resource_id IN (" + placeholders + ") ORDER BY l.label_name"

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[int64][]string)
	for rows.Next() {
		var resourceID int64
		var labelName string
		if err := rows.Scan(&resourceID, &labelName); err != nil {
			return nil, err
		}
		result[resourceID] = append(result[resourceID], labelName)
	}
	return result, nil
}

// ToggleBlogPin toggles the pinned state of a blog
func ToggleBlogPin(blogID, memberID int64) (bool, error) {
	var isPinned int
	err := DB.QueryRow("SELECT COALESCE(is_pinned,0) FROM md_blogs WHERE blog_id = ? AND member_id = ?", blogID, memberID).Scan(&isPinned)
	if err != nil {
		return false, fmt.Errorf("博客不存在或无权操作")
	}
	newVal := 0
	if isPinned == 0 {
		newVal = 1
	}
	_, err = DB.Exec("UPDATE md_blogs SET is_pinned = ? WHERE blog_id = ?", newVal, blogID)
	return newVal == 1, err
}

// ToggleBlogVisibility toggles visibility: 0↔1
func ToggleBlogVisibility(blogID, memberID int64) (int, error) {
	var vis int
	err := DB.QueryRow("SELECT COALESCE(visibility,0) FROM md_blogs WHERE blog_id = ? AND member_id = ?", blogID, memberID).Scan(&vis)
	if err != nil {
		return 0, fmt.Errorf("博客不存在或无权操作")
	}
	newVis := 0
	if vis == 0 {
		newVis = 1
	}
	_, err = DB.Exec("UPDATE md_blogs SET visibility = ? WHERE blog_id = ?", newVis, blogID)
	if err != nil {
		return newVis, err
	}
	if newVis == 0 {
		CleanupSharesForPrivateBlog(blogID)
	} else {
		blog, _ := GetBlogByID(blogID)
		if blog != nil {
			AutoCreateShareForPublicBlog(blog)
		}
	}
	return newVis, nil
}

// BatchPinBlogs sets is_pinned=1 for multiple blogs
func BatchPinBlogs(blogIDs []int64, memberID int64) (int, error) {
	if len(blogIDs) == 0 {
		return 0, nil
	}
	placeholders := ""
	args := []interface{}{memberID}
	for i, id := range blogIDs {
		if i > 0 {
			placeholders += ","
		}
		placeholders += "?"
		args = append(args, id)
	}
	result, err := DB.Exec("UPDATE md_blogs SET is_pinned = 1 WHERE member_id = ? AND blog_id IN ("+placeholders+")", args...)
	if err != nil {
		return 0, err
	}
	affected, _ := result.RowsAffected()
	return int(affected), nil
}

// BlogDailyCount represents daily content count for calendar heatmap
type BlogDailyCount struct {
	Date      string `json:"date"`
	Count     int    `json:"count"`
	NoteCount int    `json:"note_count"`
	ArtCount  int    `json:"article_count"`
}

// GetBlogDailyCounts returns daily blog/note counts for a given month
func GetBlogDailyCounts(memberID int64, year, month int) ([]BlogDailyCount, error) {
	startDate := fmt.Sprintf("%04d-%02d-01", year, month)
	endDate := fmt.Sprintf("%04d-%02d-31", year, month)
	rows, err := DB.Query(`
		SELECT DATE(create_time) as d,
		       COUNT(*) as cnt,
		       SUM(CASE WHEN COALESCE(blog_type,'article')='note' THEN 1 ELSE 0 END) as nc,
		       SUM(CASE WHEN COALESCE(blog_type,'article')='article' THEN 1 ELSE 0 END) as ac
		FROM md_blogs
		WHERE member_id = ? AND DATE(create_time) BETWEEN ? AND ?
		GROUP BY d
		ORDER BY d`, memberID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []BlogDailyCount
	for rows.Next() {
		var r BlogDailyCount
		if err := rows.Scan(&r.Date, &r.Count, &r.NoteCount, &r.ArtCount); err != nil {
			return nil, err
		}
		result = append(result, r)
	}
	return result, nil
}
