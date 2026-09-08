package models

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const defaultFaviconCacheDBPath = "data/favicon.db"

var (
	faviconCacheDB     *sql.DB
	faviconCacheDBPath = defaultFaviconCacheDBPath
	faviconCacheMu     sync.Mutex
)

type FaviconCacheEntry struct {
	FaviconURL  string
	ContentHash string
	MimeType    string
	Extension   string
	Data        []byte
	Size        int64
	UpdatedAt   time.Time
	LastUsedAt  time.Time
}

func FaviconURLHash(faviconURL string) string {
	sum := sha256.Sum256([]byte(faviconURL))
	return hex.EncodeToString(sum[:16])
}

func FaviconContentHash(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func SetFaviconCacheDBPath(path string) error {
	faviconCacheMu.Lock()
	defer faviconCacheMu.Unlock()
	if faviconCacheDB != nil {
		if err := faviconCacheDB.Close(); err != nil {
			return err
		}
		faviconCacheDB = nil
	}
	if strings.TrimSpace(path) == "" {
		faviconCacheDBPath = defaultFaviconCacheDBPath
	} else {
		faviconCacheDBPath = path
	}
	return nil
}

func CloseFaviconCacheDB() error {
	faviconCacheMu.Lock()
	defer faviconCacheMu.Unlock()
	if faviconCacheDB == nil {
		return nil
	}
	err := faviconCacheDB.Close()
	faviconCacheDB = nil
	return err
}

func InitFaviconCacheDB() error {
	faviconCacheMu.Lock()
	defer faviconCacheMu.Unlock()
	return initFaviconCacheDBLocked()
}

func initFaviconCacheDBLocked() error {
	if faviconCacheDB != nil {
		return nil
	}
	dir := filepath.Dir(faviconCacheDBPath)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("create favicon db dir: %w", err)
		}
	}
	db, err := sql.Open("sqlite", sqliteDSN(faviconCacheDBPath))
	if err != nil {
		return fmt.Errorf("open favicon db: %w", err)
	}
	if _, err := db.Exec("PRAGMA journal_mode=DELETE"); err != nil {
		db.Close()
		return fmt.Errorf("set favicon journal mode: %w", err)
	}
	if _, err := db.Exec("PRAGMA synchronous=NORMAL"); err != nil {
		db.Close()
		return fmt.Errorf("set favicon synchronous: %w", err)
	}
	if _, err := db.Exec("PRAGMA busy_timeout=3000"); err != nil {
		db.Close()
		return fmt.Errorf("set favicon busy_timeout: %w", err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	if err := createFaviconCacheTables(db); err != nil {
		db.Close()
		return err
	}
	faviconCacheDB = db
	return nil
}

func createFaviconCacheTables(db *sql.DB) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS md_favicon_blob (
			content_hash TEXT PRIMARY KEY,
			mime_type TEXT NOT NULL DEFAULT '',
			extension TEXT NOT NULL DEFAULT '',
			data BLOB NOT NULL,
			size INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_favicon_cache (
			url_hash TEXT PRIMARY KEY,
			favicon_url TEXT NOT NULL UNIQUE,
			content_hash TEXT NOT NULL,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL,
			last_used_time DATETIME NOT NULL,
			FOREIGN KEY(content_hash) REFERENCES md_favicon_blob(content_hash)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_favicon_cache_modify_time ON md_favicon_cache(modify_time)`,
		`CREATE INDEX IF NOT EXISTS idx_favicon_cache_last_used_time ON md_favicon_cache(last_used_time)`,
	}
	for _, stmt := range statements {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("create favicon cache table: %w", err)
		}
	}
	return nil
}

func LoadFaviconCache(faviconURL string) (*FaviconCacheEntry, error) {
	if err := InitFaviconCacheDB(); err != nil {
		return nil, err
	}
	row := faviconCacheDB.QueryRow(`
		SELECT c.favicon_url, c.content_hash, b.mime_type, b.extension, b.data, b.size, c.modify_time, c.last_used_time
		FROM md_favicon_cache c
		INNER JOIN md_favicon_blob b ON b.content_hash = c.content_hash
		WHERE c.url_hash = ?
	`, FaviconURLHash(faviconURL))
	var entry FaviconCacheEntry
	err := row.Scan(&entry.FaviconURL, &entry.ContentHash, &entry.MimeType, &entry.Extension, &entry.Data, &entry.Size, &entry.UpdatedAt, &entry.LastUsedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	go TouchFaviconCache(faviconURL)
	return &entry, nil
}

func TouchFaviconCache(faviconURL string) {
	if err := InitFaviconCacheDB(); err != nil {
		return
	}
	_, _ = faviconCacheDB.Exec(
		`UPDATE md_favicon_cache SET last_used_time = ? WHERE url_hash = ?`,
		time.Now(), FaviconURLHash(faviconURL),
	)
}

func StoreFaviconCache(faviconURL, mimeType, extension string, data []byte) (*FaviconCacheEntry, error) {
	if len(data) == 0 {
		return nil, fmt.Errorf("empty favicon data")
	}
	if err := InitFaviconCacheDB(); err != nil {
		return nil, err
	}
	if extension == "" {
		extension = ".ico"
	}
	if !strings.HasPrefix(extension, ".") {
		extension = "." + extension
	}
	now := time.Now()
	contentHash := FaviconContentHash(data)
	urlHash := FaviconURLHash(faviconURL)

	tx, err := faviconCacheDB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`
		INSERT INTO md_favicon_blob (content_hash, mime_type, extension, data, size, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(content_hash) DO UPDATE SET
			mime_type = excluded.mime_type,
			extension = excluded.extension,
			modify_time = excluded.modify_time
	`, contentHash, mimeType, extension, data, len(data), now, now); err != nil {
		return nil, err
	}
	if _, err := tx.Exec(`
		INSERT INTO md_favicon_cache (url_hash, favicon_url, content_hash, create_time, modify_time, last_used_time)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(url_hash) DO UPDATE SET
			favicon_url = excluded.favicon_url,
			content_hash = excluded.content_hash,
			modify_time = excluded.modify_time,
			last_used_time = excluded.last_used_time
	`, urlHash, faviconURL, contentHash, now, now, now); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &FaviconCacheEntry{
		FaviconURL:  faviconURL,
		ContentHash: contentHash,
		MimeType:    mimeType,
		Extension:   extension,
		Data:        data,
		Size:        int64(len(data)),
		UpdatedAt:   now,
		LastUsedAt:  now,
	}, nil
}

func MigrateFaviconFileCache(cacheDir string) (int, error) {
	if DB == nil {
		return 0, nil
	}
	files, err := os.ReadDir(cacheDir)
	if os.IsNotExist(err) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}

	rows, err := DB.Query(`SELECT DISTINCT favicon FROM md_bookmark WHERE favicon <> ''`)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	urlsByHash := make(map[string]string)
	for rows.Next() {
		var faviconURL string
		if err := rows.Scan(&faviconURL); err != nil {
			return 0, err
		}
		urlsByHash[FaviconURLHash(faviconURL)] = faviconURL
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}

	migrated := 0
	for _, file := range files {
		if file.IsDir() {
			continue
		}
		name := file.Name()
		ext := strings.ToLower(filepath.Ext(name))
		urlHash := strings.TrimSuffix(name, ext)
		faviconURL := urlsByHash[urlHash]
		if faviconURL == "" {
			continue
		}
		path := filepath.Join(cacheDir, name)
		data, err := os.ReadFile(path)
		if err != nil {
			log.Printf("favicon: skip migration for %s: %v", path, err)
			continue
		}
		if len(data) == 0 {
			continue
		}
		mimeType := FaviconMimeTypeFromExtension(ext)
		if _, err := StoreFaviconCache(faviconURL, mimeType, ext, data); err != nil {
			log.Printf("favicon: skip migration for %s: %v", path, err)
			continue
		}
		migrated++
	}
	return migrated, nil
}

func FaviconMimeTypeFromExtension(extension string) string {
	switch strings.ToLower(extension) {
	case ".png":
		return "image/png"
	case ".svg":
		return "image/svg+xml"
	case ".gif":
		return "image/gif"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".webp":
		return "image/webp"
	case ".ico":
		return "image/x-icon"
	default:
		return "image/x-icon"
	}
}
