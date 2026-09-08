package models

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const UploadBaseDir = "data/uploads"

func init() {
	if err := os.MkdirAll(UploadBaseDir, 0755); err != nil {
		log.Printf("create upload base dir: %v", err)
	}
}

var allowedCategories = map[string]bool{
	"editor":  true,
	"note":    true,
	"drawing": true,
}

// Upload represents an uploaded file record
type Upload struct {
	UploadID    int64     `json:"id"`
	FileName    string    `json:"file_name"`
	StoragePath string    `json:"storage_path"`
	FileHash    string    `json:"file_hash"`
	ThumbPath   string    `json:"thumb_path"`
	Category    string    `json:"category"`
	MimeType    string    `json:"mime_type"`
	FileSize    int64     `json:"file_size"`
	ThumbSize   int64     `json:"thumb_size"`
	Width       int       `json:"width"`
	Height      int       `json:"height"`
	MemberID    int64     `json:"member_id"`
	CreateTime  time.Time `json:"create_time"`
}

// IsAllowedCategory checks if a category is in the allowed list
func IsAllowedCategory(cat string) bool {
	return allowedCategories[cat]
}

// --- Cached setting getters (60s TTL, RWMutex double-check) ---

var (
	uploadMaxSizeCache   int64
	uploadMaxSizeCacheAt time.Time
	uploadMaxSizeMu      sync.RWMutex
)

// GetUploadMaxSize returns the max upload file size in bytes (default 10485760)
func GetUploadMaxSize() int64 {
	uploadMaxSizeMu.RLock()
	if time.Since(uploadMaxSizeCacheAt) < 60*time.Second {
		v := uploadMaxSizeCache
		uploadMaxSizeMu.RUnlock()
		return v
	}
	uploadMaxSizeMu.RUnlock()

	uploadMaxSizeMu.Lock()
	defer uploadMaxSizeMu.Unlock()

	if time.Since(uploadMaxSizeCacheAt) < 60*time.Second {
		return uploadMaxSizeCache
	}

	val := GetSetting("upload_max_size")
	n := int64(10485760)
	if val != "" {
		if parsed, err := strconv.ParseInt(val, 10, 64); err == nil && parsed > 0 {
			n = parsed
		}
	}
	uploadMaxSizeCache = n
	uploadMaxSizeCacheAt = time.Now()
	return n
}

var (
	uploadAllowedTypesCache   string
	uploadAllowedTypesCacheAt time.Time
	uploadAllowedTypesMu      sync.RWMutex
)

// GetUploadAllowedTypes returns the comma-separated list of allowed MIME types
func GetUploadAllowedTypes() string {
	uploadAllowedTypesMu.RLock()
	if time.Since(uploadAllowedTypesCacheAt) < 60*time.Second {
		v := uploadAllowedTypesCache
		uploadAllowedTypesMu.RUnlock()
		return v
	}
	uploadAllowedTypesMu.RUnlock()

	uploadAllowedTypesMu.Lock()
	defer uploadAllowedTypesMu.Unlock()

	if time.Since(uploadAllowedTypesCacheAt) < 60*time.Second {
		return uploadAllowedTypesCache
	}

	val := GetSetting("upload_allowed_types")
	s := "image/jpeg,image/png,image/gif,image/webp,image/svg+xml"
	if val != "" {
		s = val
	}
	uploadAllowedTypesCache = s
	uploadAllowedTypesCacheAt = time.Now()
	return s
}

var (
	uploadMaxWidthCache   int
	uploadMaxWidthCacheAt time.Time
	uploadMaxWidthMu      sync.RWMutex
)

// GetUploadMaxWidth returns the max original image width in pixels (default 2048)
func GetUploadMaxWidth() int {
	uploadMaxWidthMu.RLock()
	if time.Since(uploadMaxWidthCacheAt) < 60*time.Second {
		v := uploadMaxWidthCache
		uploadMaxWidthMu.RUnlock()
		return v
	}
	uploadMaxWidthMu.RUnlock()

	uploadMaxWidthMu.Lock()
	defer uploadMaxWidthMu.Unlock()

	if time.Since(uploadMaxWidthCacheAt) < 60*time.Second {
		return uploadMaxWidthCache
	}

	val := GetSetting("upload_max_width")
	n := 2048
	if val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 {
			n = parsed
		}
	}
	uploadMaxWidthCache = n
	uploadMaxWidthCacheAt = time.Now()
	return n
}

var (
	uploadThumbWidthCache   int
	uploadThumbWidthCacheAt time.Time
	uploadThumbWidthMu      sync.RWMutex
)

// GetUploadThumbWidth returns the thumbnail width in pixels (default 300)
func GetUploadThumbWidth() int {
	uploadThumbWidthMu.RLock()
	if time.Since(uploadThumbWidthCacheAt) < 60*time.Second {
		v := uploadThumbWidthCache
		uploadThumbWidthMu.RUnlock()
		return v
	}
	uploadThumbWidthMu.RUnlock()

	uploadThumbWidthMu.Lock()
	defer uploadThumbWidthMu.Unlock()

	if time.Since(uploadThumbWidthCacheAt) < 60*time.Second {
		return uploadThumbWidthCache
	}

	val := GetSetting("upload_thumb_width")
	n := 300
	if val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 {
			n = parsed
		}
	}
	uploadThumbWidthCache = n
	uploadThumbWidthCacheAt = time.Now()
	return n
}

// IsAllowedMIMEType checks if the given MIME type is in the allowed list
func IsAllowedMIMEType(mime string) bool {
	allowed := GetUploadAllowedTypes()
	for _, t := range strings.Split(allowed, ",") {
		if strings.TrimSpace(t) == mime {
			return true
		}
	}
	return false
}

// --- CRUD operations ---

// InsertUpload inserts an upload record and returns the new ID
func InsertUpload(u *Upload) (int64, error) {
	result, err := DB.Exec(`
		INSERT INTO md_uploads (file_name, storage_path, file_hash, file_size, mime_type, width, height, thumb_path, thumb_size, category, member_id, create_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		u.FileName, u.StoragePath, u.FileHash, u.FileSize, u.MimeType, u.Width, u.Height,
		u.ThumbPath, u.ThumbSize, u.Category, u.MemberID, u.CreateTime,
	)
	if err != nil {
		return 0, fmt.Errorf("insert upload: %w", err)
	}
	return result.LastInsertId()
}

// GetUploadByID returns a single upload by its ID
func GetUploadByID(id int64) (*Upload, error) {
	row := DB.QueryRow(`
		SELECT upload_id, file_name, storage_path, file_hash, file_size, mime_type, width, height, thumb_path, thumb_size, category, member_id, create_time
		FROM md_uploads WHERE upload_id = ?`, id)

	var u Upload
	var createTime sql.NullTime
	if err := row.Scan(&u.UploadID, &u.FileName, &u.StoragePath, &u.FileHash, &u.FileSize, &u.MimeType,
		&u.Width, &u.Height, &u.ThumbPath, &u.ThumbSize, &u.Category, &u.MemberID, &createTime); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("get upload by id: %w", err)
	}
	if createTime.Valid {
		u.CreateTime = createTime.Time
	}
	return &u, nil
}

// ListUploadsPaged returns a paginated list of uploads with optional keyword and category filters.
// It returns the uploads, total count, and error.
func ListUploadsPaged(page, pageSize int, keyword, category string) ([]Upload, int64, error) {
	var where []string
	var args []any

	if keyword != "" {
		where = append(where, "file_name LIKE ?")
		args = append(args, "%"+keyword+"%")
	}
	if category != "" {
		where = append(where, "category = ?")
		args = append(args, category)
	}

	whereClause := ""
	if len(where) > 0 {
		whereClause = "WHERE " + strings.Join(where, " AND ")
	}

	// Count total
	var total int64
	countSQL := "SELECT COUNT(*) FROM md_uploads " + whereClause
	if err := DB.QueryRow(countSQL, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count uploads: %w", err)
	}

	// Query page
	offset := (page - 1) * pageSize
	querySQL := fmt.Sprintf(`
		SELECT upload_id, file_name, storage_path, file_hash, file_size, mime_type, width, height, thumb_path, thumb_size, category, member_id, create_time
		FROM md_uploads %s
		ORDER BY create_time DESC
		LIMIT ? OFFSET ?`, whereClause)
	queryArgs := append(args, pageSize, offset)

	rows, err := DB.Query(querySQL, queryArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("list uploads: %w", err)
	}
	defer rows.Close()

	var uploads []Upload
	for rows.Next() {
		var u Upload
		var createTime sql.NullTime
		if err := rows.Scan(&u.UploadID, &u.FileName, &u.StoragePath, &u.FileHash, &u.FileSize, &u.MimeType,
			&u.Width, &u.Height, &u.ThumbPath, &u.ThumbSize, &u.Category, &u.MemberID, &createTime); err != nil {
			return nil, 0, fmt.Errorf("scan upload: %w", err)
		}
		if createTime.Valid {
			u.CreateTime = createTime.Time
		}
		uploads = append(uploads, u)
	}
	return uploads, total, nil
}

// DeleteUpload deletes an upload record by ID
// GetUploadByHash returns an upload with the same file hash (for dedup)
func GetUploadByHash(hash string) (*Upload, error) {
	row := DB.QueryRow(`
		SELECT upload_id, file_name, storage_path, file_hash, file_size, mime_type, width, height, thumb_path, thumb_size, category, member_id, create_time
		FROM md_uploads WHERE file_hash = ? LIMIT 1`, hash)

	var u Upload
	var createTime sql.NullTime
	if err := row.Scan(&u.UploadID, &u.FileName, &u.StoragePath, &u.FileHash, &u.FileSize, &u.MimeType,
		&u.Width, &u.Height, &u.ThumbPath, &u.ThumbSize, &u.Category, &u.MemberID, &createTime); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("get upload by hash: %w", err)
	}
	if createTime.Valid {
		u.CreateTime = createTime.Time
	}
	return &u, nil
}

// DeleteUpload deletes an upload record by ID
func DeleteUpload(id int64) error {
	_, err := DB.Exec("DELETE FROM md_uploads WHERE upload_id = ?", id)
	if err != nil {
		return fmt.Errorf("delete upload: %w", err)
	}
	return nil
}

// GetUploadStats returns the total count and total file size of all uploads
func GetUploadStats() (count int64, totalSize int64, err error) {
	err = DB.QueryRow("SELECT COUNT(*), COALESCE(SUM(file_size), 0) FROM md_uploads").Scan(&count, &totalSize)
	if err != nil {
		return 0, 0, fmt.Errorf("get upload stats: %w", err)
	}
	return count, totalSize, nil
}