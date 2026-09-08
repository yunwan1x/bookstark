package models

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func initFaviconCacheTestDB(t *testing.T) string {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "favicon.db")
	if err := SetFaviconCacheDBPath(dbPath); err != nil {
		t.Fatalf("SetFaviconCacheDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = CloseFaviconCacheDB()
		_ = SetFaviconCacheDBPath(defaultFaviconCacheDBPath)
	})
	return dbPath
}

func TestFaviconCacheUsesSeparateDeleteJournalDB(t *testing.T) {
	initFaviconCacheTestDB(t)
	if err := InitFaviconCacheDB(); err != nil {
		t.Fatalf("InitFaviconCacheDB() error = %v", err)
	}

	var journalMode string
	if err := faviconCacheDB.QueryRow(`PRAGMA journal_mode`).Scan(&journalMode); err != nil {
		t.Fatalf("PRAGMA journal_mode error = %v", err)
	}
	if journalMode != "delete" {
		t.Fatalf("journal_mode = %q, want delete", journalMode)
	}
}

func TestFaviconCacheDeduplicatesBlobData(t *testing.T) {
	initFaviconCacheTestDB(t)

	data := []byte(`<svg xmlns="http://www.w3.org/2000/svg"></svg>`)
	if _, err := StoreFaviconCache("https://a.example/favicon.svg", "image/svg+xml", ".svg", data); err != nil {
		t.Fatalf("StoreFaviconCache(first) error = %v", err)
	}
	if _, err := StoreFaviconCache("https://b.example/favicon.svg", "image/svg+xml", ".svg", data); err != nil {
		t.Fatalf("StoreFaviconCache(second) error = %v", err)
	}

	var blobCount int
	if err := faviconCacheDB.QueryRow(`SELECT COUNT(1) FROM md_favicon_blob`).Scan(&blobCount); err != nil {
		t.Fatalf("count blobs error = %v", err)
	}
	if blobCount != 1 {
		t.Fatalf("blob count = %d, want 1", blobCount)
	}

	entry, err := LoadFaviconCache("https://b.example/favicon.svg")
	if err != nil {
		t.Fatalf("LoadFaviconCache() error = %v", err)
	}
	if entry == nil || string(entry.Data) != string(data) || entry.MimeType != "image/svg+xml" {
		t.Fatalf("loaded entry mismatch: %#v", entry)
	}
}

func TestMigrateFaviconFileCacheMatchesBookmarkURLs(t *testing.T) {
	assetTestDBMu.Lock()
	defer assetTestDBMu.Unlock()

	if DB != nil {
		_ = DB.Close()
		DB = nil
	}
	t.Cleanup(func() {
		if DB != nil {
			_ = DB.Close()
			DB = nil
		}
	})

	dir := t.TempDir()
	if err := InitDB(filepath.Join(dir, "main.db")); err != nil {
		t.Fatalf("InitDB() error = %v", err)
	}
	initFaviconCacheTestDB(t)

	faviconURL := "https://example.com/favicon.svg"
	if _, err := DB.Exec(`
		INSERT INTO md_bookmark (title, url, favicon, member_id, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?)
	`, "Example", "https://example.com", faviconURL, 1, time.Now(), time.Now()); err != nil {
		t.Fatalf("insert bookmark error = %v", err)
	}

	cacheDir := filepath.Join(dir, "favicon")
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		t.Fatalf("mkdir cache dir error = %v", err)
	}
	data := []byte(`<svg xmlns="http://www.w3.org/2000/svg"><path /></svg>`)
	filePath := filepath.Join(cacheDir, FaviconURLHash(faviconURL)+".svg")
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		t.Fatalf("write favicon file error = %v", err)
	}

	migrated, err := MigrateFaviconFileCache(cacheDir)
	if err != nil {
		t.Fatalf("MigrateFaviconFileCache() error = %v", err)
	}
	if migrated != 1 {
		t.Fatalf("migrated = %d, want 1", migrated)
	}
	entry, err := LoadFaviconCache(faviconURL)
	if err != nil {
		t.Fatalf("LoadFaviconCache() error = %v", err)
	}
	if entry == nil || string(entry.Data) != string(data) || entry.Extension != ".svg" {
		t.Fatalf("migrated entry mismatch: %#v", entry)
	}
}
