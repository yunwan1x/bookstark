package models

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

const (
	DAVCompressionNone = "none"
	DAVCompressionGzip = "gzip"

	DAVChunkSize       = 1 << 20
	davCompressionMin  = 4 << 10
	davCompressionTry  = 64 << 10
	davCompressionGain = 0.10
	davAuthCacheTTL    = 2 * time.Minute
)

var (
	WebDAVDB *sql.DB

	ErrDAVNotFound      = errors.New("webdav resource not found")
	ErrDAVAlreadyExists = errors.New("webdav resource already exists")
	ErrDAVInvalidPath   = errors.New("invalid webdav path")
	ErrDAVIsDirectory   = errors.New("webdav resource is a directory")
	ErrDAVNotDirectory  = errors.New("webdav resource is not a directory")
	ErrDAVQuotaExceeded = errors.New("webdav quota exceeded")
	ErrDAVFileTooLarge  = errors.New("webdav file too large")
	ErrDAVCorruptBlob   = errors.New("webdav blob is corrupt")

	davAuthCache   sync.Map
	davAuthCacheMu sync.RWMutex
	davTransfers   = newDAVTransferGate()
)

type davTransferScopeContextKey struct{}

type davTransferGate struct {
	mu     sync.Mutex
	active int
	wait   chan struct{}
}

func newDAVTransferGate() *davTransferGate {
	return &davTransferGate{wait: make(chan struct{})}
}

func (g *davTransferGate) acquire(ctx context.Context) (func(), error) {
	return g.acquireWithLimitProvider(ctx, func() int {
		return GetWebDAVSettings().MaxConcurrentTransfers
	})
}

func BeginDAVTransfer(ctx context.Context) (context.Context, func(), error) {
	release, err := davTransfers.acquire(ctx)
	if err != nil {
		return ctx, nil, err
	}
	return context.WithValue(ctx, davTransferScopeContextKey{}, true), release, nil
}

func acquireDAVTransfer(ctx context.Context) (func(), error) {
	if scoped, _ := ctx.Value(davTransferScopeContextKey{}).(bool); scoped {
		return func() {}, nil
	}
	return davTransfers.acquire(ctx)
}

func (g *davTransferGate) acquireWithLimit(ctx context.Context, limit int) (func(), error) {
	return g.acquireWithLimitProvider(ctx, func() int { return limit })
}

func (g *davTransferGate) acquireWithLimitProvider(ctx context.Context, limitProvider func() int) (func(), error) {
	for {
		limit := limitProvider()
		if limit < 1 {
			limit = 1
		}
		g.mu.Lock()
		if g.active < limit {
			g.active++
			g.mu.Unlock()
			var once sync.Once
			return func() {
				once.Do(func() {
					g.mu.Lock()
					g.active--
					close(g.wait)
					g.wait = make(chan struct{})
					g.mu.Unlock()
				})
			}, nil
		}
		wait := g.wait
		g.mu.Unlock()
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-wait:
		case <-time.After(250 * time.Millisecond):
		}
	}
}

type davAuthCacheEntry struct {
	secretDigest [sha256.Size]byte
	expiresAt    time.Time
}

type DAVNode struct {
	NodeID     int64     `json:"id"`
	MemberID   int64     `json:"-"`
	ParentID   *int64    `json:"-"`
	Name       string    `json:"name"`
	IsDir      bool      `json:"-"`
	Type       string    `json:"type"`
	Path       string    `json:"path"`
	MIMEType   string    `json:"mime_type"`
	BlobID     *int64    `json:"-"`
	ETag       string    `json:"etag"`
	Size       int64     `json:"size"`
	StoredSize int64     `json:"stored_size,omitempty"`
	Mode       string    `json:"mode"`
	IsPublic   bool      `json:"is_public"`
	PublicPath string    `json:"public_path,omitempty"`
	CreateTime time.Time `json:"create_time"`
	ModifyTime time.Time `json:"mod_time"`
}

type DAVBlob struct {
	BlobID       int64
	ContentHash  string
	OriginalSize int64
	StoredSize   int64
	ChunkSize    int64
	ChunkCount   int
	RefCount     int64
	CreateTime   time.Time
}

type DAVUsage struct {
	FileCount             int64 `json:"file_count"`
	DirectoryCount        int64 `json:"directory_count"`
	LogicalBytes          int64 `json:"logical_bytes"`
	StoredBytes           int64 `json:"stored_bytes"`
	DeduplicatedBytes     int64 `json:"deduplicated_bytes"`
	CompressionSavedBytes int64 `json:"compression_saved_bytes"`
	QuotaBytes            int64 `json:"quota_bytes"`
}

type DAVPublicAsset struct {
	AssetID    int64     `json:"id"`
	MemberID   int64     `json:"-"`
	NodeID     int64     `json:"node_id"`
	PublicPath string    `json:"public_path"`
	Enabled    bool      `json:"enabled"`
	CreateTime time.Time `json:"create_time"`
	ModifyTime time.Time `json:"modify_time"`
}

type DAVAppCredential struct {
	MemberID    int64
	SecretHash  string
	CreateTime  time.Time
	ModifyTime  time.Time
	LastUseTime *time.Time
}

func InitWebDAVDB(dbPath string) error {
	if strings.TrimSpace(dbPath) == "" {
		return errors.New("webdav db path is empty")
	}
	if dbPath != ":memory:" && !strings.HasPrefix(dbPath, "file:") {
		if err := os.MkdirAll(filepath.Dir(dbPath), 0o755); err != nil {
			return fmt.Errorf("create webdav db directory: %w", err)
		}
	}
	if WebDAVDB != nil {
		_ = WebDAVDB.Close()
	}
	clearDAVAuthCache()
	db, err := sql.Open("sqlite", sqliteDSN(dbPath))
	if err != nil {
		return fmt.Errorf("open webdav db: %w", err)
	}
	if _, err = db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		_ = db.Close()
		return fmt.Errorf("set webdav WAL: %w", err)
	}
	for _, pragma := range []string{
		"PRAGMA synchronous=NORMAL",
		"PRAGMA busy_timeout=5000",
		"PRAGMA foreign_keys=ON",
	} {
		if _, err = db.Exec(pragma); err != nil {
			_ = db.Close()
			return fmt.Errorf("configure webdav db: %w", err)
		}
	}
	db.SetMaxOpenConns(40)
	db.SetMaxIdleConns(5)
	WebDAVDB = db
	if err := createWebDAVTables(); err != nil {
		_ = db.Close()
		WebDAVDB = nil
		return err
	}
	if err := RepairDAVBlobReferences(); err != nil {
		_ = db.Close()
		WebDAVDB = nil
		return fmt.Errorf("repair webdav blob references: %w", err)
	}
	return nil
}

func createWebDAVTables() error {
	if WebDAVDB == nil {
		return errors.New("webdav db is not initialized")
	}
	if err := resetEmptyLegacyDAVContentTables(); err != nil {
		return err
	}
	statements := []string{
		`CREATE TABLE IF NOT EXISTS dav_blobs (
			blob_id INTEGER PRIMARY KEY AUTOINCREMENT,
			content_hash TEXT NOT NULL,
			original_size INTEGER NOT NULL DEFAULT 0 CHECK(original_size >= 0),
			stored_size INTEGER NOT NULL DEFAULT 0 CHECK(stored_size >= 0),
			chunk_size INTEGER NOT NULL DEFAULT 1048576 CHECK(chunk_size = 1048576),
			chunk_count INTEGER NOT NULL DEFAULT 0 CHECK(chunk_count >= 0),
			ref_count INTEGER NOT NULL DEFAULT 0 CHECK(ref_count >= 0),
			create_time DATETIME NOT NULL,
			UNIQUE(content_hash, original_size)
		)`,
		`CREATE TABLE IF NOT EXISTS dav_blob_chunks (
			blob_id INTEGER NOT NULL,
			chunk_index INTEGER NOT NULL,
			original_size INTEGER NOT NULL CHECK(original_size >= 0 AND original_size <= 1048576),
			stored_size INTEGER NOT NULL CHECK(stored_size >= 0),
			compression TEXT NOT NULL DEFAULT 'none' CHECK(compression IN ('none', 'gzip')),
			chunk_hash TEXT NOT NULL,
			content_blob BLOB NOT NULL,
			PRIMARY KEY(blob_id, chunk_index),
			FOREIGN KEY(blob_id) REFERENCES dav_blobs(blob_id) ON DELETE CASCADE
		)`,
		`CREATE INDEX IF NOT EXISTS idx_dav_blob_chunks_blob
			ON dav_blob_chunks(blob_id)`,
		`CREATE TABLE IF NOT EXISTS dav_nodes (
			node_id INTEGER PRIMARY KEY AUTOINCREMENT,
			member_id INTEGER NOT NULL,
			parent_id INTEGER,
			name TEXT NOT NULL,
			is_dir INTEGER NOT NULL DEFAULT 0,
			mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
			blob_id INTEGER,
			etag TEXT NOT NULL DEFAULT '',
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL,
			UNIQUE(member_id, parent_id, name),
			FOREIGN KEY(parent_id) REFERENCES dav_nodes(node_id) ON DELETE CASCADE,
			FOREIGN KEY(blob_id) REFERENCES dav_blobs(blob_id) ON DELETE RESTRICT
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_dav_nodes_member_root
			ON dav_nodes(member_id) WHERE parent_id IS NULL`,
		`CREATE INDEX IF NOT EXISTS idx_dav_nodes_parent
			ON dav_nodes(member_id, parent_id, name)`,
		`CREATE INDEX IF NOT EXISTS idx_dav_nodes_blob ON dav_nodes(blob_id)`,
		`CREATE TABLE IF NOT EXISTS dav_public_assets (
			asset_id INTEGER PRIMARY KEY AUTOINCREMENT,
			member_id INTEGER NOT NULL,
			node_id INTEGER NOT NULL UNIQUE,
			public_path TEXT NOT NULL,
			enabled INTEGER NOT NULL DEFAULT 1,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL,
			UNIQUE(member_id, public_path),
			FOREIGN KEY(node_id) REFERENCES dav_nodes(node_id) ON DELETE CASCADE
		)`,
		`CREATE INDEX IF NOT EXISTS idx_dav_public_member_path
			ON dav_public_assets(member_id, public_path, enabled)`,
		`CREATE TABLE IF NOT EXISTS dav_app_credentials (
			member_id INTEGER PRIMARY KEY,
			secret_hash TEXT NOT NULL,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL,
			last_use_time DATETIME
		)`,
	}
	for _, statement := range statements {
		if _, err := WebDAVDB.Exec(statement); err != nil {
			return fmt.Errorf("create webdav tables: %w", err)
		}
	}
	return nil
}

func resetEmptyLegacyDAVContentTables() error {
	rows, err := WebDAVDB.Query("PRAGMA table_info(dav_blobs)")
	if err != nil {
		return fmt.Errorf("inspect webdav blob schema: %w", err)
	}
	defer rows.Close()
	hasTable := false
	hasInlineContent := false
	for rows.Next() {
		hasTable = true
		var cid, notNull, primaryKey int
		var name, columnType string
		var defaultValue any
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &primaryKey); err != nil {
			return fmt.Errorf("inspect webdav blob column: %w", err)
		}
		if name == "content_blob" {
			hasInlineContent = true
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if err := rows.Close(); err != nil {
		return fmt.Errorf("close WebDAV schema inspection: %w", err)
	}
	if !hasTable || !hasInlineContent {
		return nil
	}
	var blobCount int
	if err := WebDAVDB.QueryRow("SELECT COUNT(*) FROM dav_blobs").Scan(&blobCount); err != nil {
		return err
	}
	if blobCount != 0 {
		return errors.New("legacy WebDAV content exists; empty dav_blobs before enabling chunk storage")
	}
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, statement := range []string{
		"DROP TABLE IF EXISTS dav_public_assets",
		"DROP TABLE IF EXISTS dav_nodes",
		"DROP TABLE IF EXISTS dav_blob_chunks",
		"DROP TABLE IF EXISTS dav_blobs",
	} {
		if _, err := tx.Exec(statement); err != nil {
			return fmt.Errorf("replace empty WebDAV content schema: %w", err)
		}
	}
	return tx.Commit()
}

func NormalizeDAVPath(value string) (string, error) {
	if strings.Contains(value, "\\") || strings.IndexFunc(value, func(r rune) bool {
		return r < 0x20 || r == 0x7f
	}) >= 0 {
		return "", ErrDAVInvalidPath
	}
	for _, part := range strings.Split(strings.TrimPrefix(value, "/"), "/") {
		if part == ".." {
			return "", ErrDAVInvalidPath
		}
	}
	cleaned := path.Clean("/" + strings.TrimPrefix(value, "/"))
	if cleaned == "/" || cleaned == "." {
		return "", nil
	}
	return strings.TrimPrefix(cleaned, "/"), nil
}

func EnsureDAVRoot(memberID int64) (*DAVNode, error) {
	if memberID <= 0 || WebDAVDB == nil {
		return nil, ErrDAVNotFound
	}
	root, err := getDAVRoot(WebDAVDB, memberID)
	if err == nil {
		return root, nil
	}
	if !errors.Is(err, ErrDAVNotFound) {
		return nil, err
	}
	now := time.Now()
	_, err = WebDAVDB.Exec(`
		INSERT INTO dav_nodes(member_id, parent_id, name, is_dir, mime_type, create_time, modify_time)
		SELECT ?, NULL, '', 1, 'inode/directory', ?, ?
		WHERE NOT EXISTS (
			SELECT 1 FROM dav_nodes WHERE member_id=? AND parent_id IS NULL
		)`, memberID, now, now, memberID)
	if err != nil {
		if isDAVUniqueError(err) {
			return getDAVRoot(WebDAVDB, memberID)
		}
		return nil, fmt.Errorf("ensure webdav root: %w", err)
	}
	return getDAVRoot(WebDAVDB, memberID)
}

type davQuerier interface {
	QueryRow(query string, args ...any) *sql.Row
	Query(query string, args ...any) (*sql.Rows, error)
}

func getDAVRoot(q davQuerier, memberID int64) (*DAVNode, error) {
	row := q.QueryRow(`
		SELECT n.node_id, n.member_id, n.parent_id, n.name, n.is_dir, n.mime_type,
		       n.blob_id, n.etag, 0, 0, n.create_time, n.modify_time
		FROM dav_nodes n
		WHERE n.member_id=? AND n.parent_id IS NULL`, memberID)
	node, err := scanDAVNode(row)
	if err == sql.ErrNoRows {
		return nil, ErrDAVNotFound
	}
	return node, err
}

func resolveDAVNode(q davQuerier, memberID int64, value string) (*DAVNode, error) {
	normalized, err := NormalizeDAVPath(value)
	if err != nil {
		return nil, err
	}
	current, err := getDAVRoot(q, memberID)
	if err != nil {
		return nil, err
	}
	current.Path = ""
	if normalized == "" {
		return current, nil
	}
	currentPath := ""
	for _, part := range strings.Split(normalized, "/") {
		row := q.QueryRow(`
			SELECT n.node_id, n.member_id, n.parent_id, n.name, n.is_dir, n.mime_type,
			       n.blob_id, n.etag, COALESCE(b.original_size, 0), COALESCE(b.stored_size, 0),
			       n.create_time, n.modify_time
			FROM dav_nodes n
			LEFT JOIN dav_blobs b ON b.blob_id=n.blob_id
			WHERE n.member_id=? AND n.parent_id=? AND n.name=?`,
			memberID, current.NodeID, part)
		current, err = scanDAVNode(row)
		if err == sql.ErrNoRows {
			return nil, ErrDAVNotFound
		}
		if err != nil {
			return nil, err
		}
		currentPath = path.Join(currentPath, part)
		current.Path = currentPath
	}
	return current, nil
}

func GetDAVNode(memberID int64, value string) (*DAVNode, error) {
	if _, err := EnsureDAVRoot(memberID); err != nil {
		return nil, err
	}
	return resolveDAVNode(WebDAVDB, memberID, value)
}

func ListDAVNodes(memberID int64, value string) ([]DAVNode, error) {
	dir, err := GetDAVNode(memberID, value)
	if err != nil {
		return nil, err
	}
	if !dir.IsDir {
		return nil, ErrDAVNotDirectory
	}
	rows, err := WebDAVDB.Query(`
		SELECT n.node_id, n.member_id, n.parent_id, n.name, n.is_dir, n.mime_type,
		       n.blob_id, n.etag, COALESCE(b.original_size, 0), COALESCE(b.stored_size, 0),
		       n.create_time, n.modify_time,
		       CASE WHEN p.asset_id IS NULL THEN 0 ELSE 1 END,
		       COALESCE(p.public_path, '')
		FROM dav_nodes n
		LEFT JOIN dav_blobs b ON b.blob_id=n.blob_id
		LEFT JOIN dav_public_assets p ON p.node_id=n.node_id AND p.enabled=1
		WHERE n.member_id=? AND n.parent_id=?
		ORDER BY n.is_dir DESC, lower(n.name), n.name`, memberID, dir.NodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]DAVNode, 0)
	base, _ := NormalizeDAVPath(value)
	for rows.Next() {
		node, err := scanDAVNodeWithPublic(rows)
		if err != nil {
			return nil, err
		}
		node.Path = path.Join(base, node.Name)
		result = append(result, *node)
	}
	return result, rows.Err()
}

type rowScan interface {
	Scan(dest ...any) error
}

func scanDAVNode(row rowScan) (*DAVNode, error) {
	var node DAVNode
	var parentID, blobID sql.NullInt64
	var isDir int
	if err := row.Scan(
		&node.NodeID, &node.MemberID, &parentID, &node.Name, &isDir,
		&node.MIMEType, &blobID, &node.ETag, &node.Size, &node.StoredSize,
		&node.CreateTime, &node.ModifyTime,
	); err != nil {
		return nil, err
	}
	node.IsDir = isDir == 1
	node.Type = "file"
	node.Mode = "0644"
	if node.IsDir {
		node.Type = "dir"
		node.Mode = "0755"
	}
	if parentID.Valid {
		value := parentID.Int64
		node.ParentID = &value
	}
	if blobID.Valid {
		value := blobID.Int64
		node.BlobID = &value
	}
	return &node, nil
}

func scanDAVNodeWithPublic(row rowScan) (*DAVNode, error) {
	var node DAVNode
	var parentID, blobID sql.NullInt64
	var isDir, isPublic int
	if err := row.Scan(
		&node.NodeID, &node.MemberID, &parentID, &node.Name, &isDir,
		&node.MIMEType, &blobID, &node.ETag, &node.Size, &node.StoredSize,
		&node.CreateTime, &node.ModifyTime, &isPublic, &node.PublicPath,
	); err != nil {
		return nil, err
	}
	node.IsDir = isDir == 1
	node.IsPublic = isPublic == 1
	node.Type = "file"
	node.Mode = "0644"
	if node.IsDir {
		node.Type = "dir"
		node.Mode = "0755"
	}
	if parentID.Valid {
		value := parentID.Int64
		node.ParentID = &value
	}
	if blobID.Valid {
		value := blobID.Int64
		node.BlobID = &value
	}
	return &node, nil
}

func CreateDAVDirectory(memberID int64, value string) (*DAVNode, error) {
	normalized, err := NormalizeDAVPath(value)
	if err != nil || normalized == "" {
		return nil, ErrDAVInvalidPath
	}
	if _, err := EnsureDAVRoot(memberID); err != nil {
		return nil, err
	}
	parentPath, name := path.Split(normalized)
	if name == "" || name == "." || name == ".." {
		return nil, ErrDAVInvalidPath
	}
	parent, err := resolveDAVNode(WebDAVDB, memberID, strings.TrimSuffix(parentPath, "/"))
	if err != nil {
		return nil, err
	}
	if !parent.IsDir {
		return nil, ErrDAVNotDirectory
	}
	now := time.Now()
	result, err := WebDAVDB.Exec(`
		INSERT INTO dav_nodes(member_id, parent_id, name, is_dir, mime_type, create_time, modify_time)
		VALUES (?, ?, ?, 1, 'inode/directory', ?, ?)`,
		memberID, parent.NodeID, name, now, now)
	if isDAVUniqueError(err) {
		return nil, ErrDAVAlreadyExists
	}
	if err != nil {
		return nil, err
	}
	id, _ := result.LastInsertId()
	return GetDAVNodeByID(memberID, id)
}

func GetDAVNodeByID(memberID, nodeID int64) (*DAVNode, error) {
	row := WebDAVDB.QueryRow(`
		SELECT n.node_id, n.member_id, n.parent_id, n.name, n.is_dir, n.mime_type,
		       n.blob_id, n.etag, COALESCE(b.original_size, 0), COALESCE(b.stored_size, 0),
		       n.create_time, n.modify_time
		FROM dav_nodes n
		LEFT JOIN dav_blobs b ON b.blob_id=n.blob_id
		WHERE n.member_id=? AND n.node_id=?`, memberID, nodeID)
	node, err := scanDAVNode(row)
	if err == sql.ErrNoRows {
		return nil, ErrDAVNotFound
	}
	return node, err
}

func PutDAVFile(memberID int64, value, contentType string, source io.Reader, maxBytes, quotaBytes int64) (*DAVNode, bool, error) {
	return PutDAVFileContext(context.Background(), memberID, value, contentType, source, maxBytes, quotaBytes)
}

func PutDAVFileContext(ctx context.Context, memberID int64, value, contentType string, source io.Reader, maxBytes, quotaBytes int64) (*DAVNode, bool, error) {
	normalized, err := NormalizeDAVPath(value)
	if err != nil || normalized == "" {
		return nil, false, ErrDAVInvalidPath
	}
	release, err := acquireDAVTransfer(ctx)
	if err != nil {
		return nil, false, err
	}
	defer release()
	temp, err := os.CreateTemp("", "bookstark-dav-upload-*")
	if err != nil {
		return nil, false, err
	}
	tempName := temp.Name()
	defer func() {
		_ = temp.Close()
		_ = os.Remove(tempName)
	}()

	hash := sha256.New()
	var total int64
	buf := make([]byte, DAVChunkSize)
	for {
		if err := ctx.Err(); err != nil {
			return nil, false, err
		}
		n, readErr := io.ReadFull(source, buf)
		if n > 0 {
			total += int64(n)
			if maxBytes > 0 && total > maxBytes {
				return nil, false, ErrDAVFileTooLarge
			}
			part := buf[:n]
			if _, err := hash.Write(part); err != nil {
				return nil, false, err
			}
			if _, err := temp.Write(part); err != nil {
				return nil, false, err
			}
		}
		if readErr == io.EOF || readErr == io.ErrUnexpectedEOF {
			break
		}
		if readErr != nil {
			return nil, false, readErr
		}
	}
	if err := temp.Sync(); err != nil {
		return nil, false, err
	}
	contentHash := hex.EncodeToString(hash.Sum(nil))

	var node *DAVNode
	var deduplicated bool
	for attempt := 0; attempt < 7; attempt++ {
		node, deduplicated, err = commitDAVFile(
			ctx, memberID, normalized, contentType, tempName, contentHash, total, quotaBytes,
		)
		if err == nil || !isDAVBusyError(err) {
			return node, deduplicated, err
		}
		select {
		case <-ctx.Done():
			return nil, false, ctx.Err()
		case <-time.After(time.Duration(1<<attempt) * 10 * time.Millisecond):
		}
	}
	return node, deduplicated, err
}

func commitDAVFile(ctx context.Context, memberID int64, normalized, contentType, tempName, contentHash string, originalSize, quotaBytes int64) (*DAVNode, bool, error) {
	if _, err := EnsureDAVRoot(memberID); err != nil {
		return nil, false, err
	}
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback()

	parentPath, name := path.Split(normalized)
	parent, err := resolveDAVNode(tx, memberID, strings.TrimSuffix(parentPath, "/"))
	if err != nil {
		return nil, false, err
	}
	if !parent.IsDir {
		return nil, false, ErrDAVNotDirectory
	}

	var existing *DAVNode
	existing, err = resolveDAVNode(tx, memberID, normalized)
	if err != nil && !errors.Is(err, ErrDAVNotFound) {
		return nil, false, err
	}
	if existing != nil && existing.IsDir {
		return nil, false, ErrDAVIsDirectory
	}

	if existing != nil && originalSize > GetWebDAVSettings().PublicFileMaxBytes {
		var published int
		if err := tx.QueryRow(`
			SELECT COUNT(*) FROM dav_public_assets
			WHERE member_id=? AND node_id=? AND enabled=1`,
			memberID, existing.NodeID).Scan(&published); err != nil {
			return nil, false, err
		}
		if published > 0 {
			return nil, false, ErrDAVFileTooLarge
		}
	}

	blob, err := findDAVBlobTx(tx, contentHash, originalSize)
	deduplicated := err == nil
	if err != nil && !errors.Is(err, ErrDAVNotFound) {
		return nil, false, err
	}
	if blob == nil {
		chunkCount := int((originalSize + DAVChunkSize - 1) / DAVChunkSize)
		now := time.Now()
		result, insertErr := tx.ExecContext(ctx, `
			INSERT INTO dav_blobs(
				content_hash, original_size, stored_size, chunk_size, chunk_count, ref_count, create_time
			) VALUES (?, ?, 0, ?, ?, 0, ?)`,
			contentHash, originalSize, DAVChunkSize, chunkCount, now)
		if isDAVUniqueError(insertErr) {
			blob, err = findDAVBlobTx(tx, contentHash, originalSize)
			if err != nil {
				return nil, false, err
			}
			deduplicated = true
		} else if insertErr != nil {
			return nil, false, insertErr
		} else {
			blobID, _ := result.LastInsertId()
			storedSize, writeErr := writeDAVBlobChunksTx(ctx, tx, blobID, name, tempName, chunkCount)
			if writeErr != nil {
				return nil, false, writeErr
			}
			if _, updateErr := tx.ExecContext(ctx, "UPDATE dav_blobs SET stored_size=? WHERE blob_id=?", storedSize, blobID); updateErr != nil {
				return nil, false, updateErr
			}
			blob = &DAVBlob{
				BlobID:       blobID,
				ContentHash:  contentHash,
				OriginalSize: originalSize,
				StoredSize:   storedSize,
				ChunkSize:    DAVChunkSize,
				ChunkCount:   chunkCount,
			}
		}
	}
	var existingNodeID, oldBlobID int64
	if existing != nil {
		existingNodeID = existing.NodeID
		if existing.BlobID != nil {
			oldBlobID = *existing.BlobID
		}
	}
	if err := ensureDAVStoredQuotaTx(tx, memberID, existingNodeID, oldBlobID, blob, quotaBytes); err != nil {
		return nil, false, err
	}

	mimeType := strings.TrimSpace(contentType)
	if mimeType == "" || mimeType == "application/octet-stream" {
		mimeType = detectDAVMIME(name, tempName)
	}
	now := time.Now()
	var nodeID int64
	if existing != nil {
		nodeID = existing.NodeID
		_, err = tx.ExecContext(ctx, `
			UPDATE dav_nodes
			SET mime_type=?, blob_id=?, etag=?, modify_time=?
			WHERE member_id=? AND node_id=?`,
			mimeType, blob.BlobID, contentHash, now, memberID, nodeID)
	} else {
		result, insertErr := tx.ExecContext(ctx, `
			INSERT INTO dav_nodes(
				member_id, parent_id, name, is_dir, mime_type, blob_id, etag, create_time, modify_time
			) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?)`,
			memberID, parent.NodeID, name, mimeType, blob.BlobID, contentHash, now, now)
		if isDAVUniqueError(insertErr) {
			return nil, false, ErrDAVAlreadyExists
		}
		if insertErr != nil {
			return nil, false, insertErr
		}
		nodeID, _ = result.LastInsertId()
		err = nil
	}
	if err != nil {
		return nil, false, err
	}
	if oldBlobID != blob.BlobID {
		if _, err := tx.ExecContext(ctx, "UPDATE dav_blobs SET ref_count=ref_count+1 WHERE blob_id=?", blob.BlobID); err != nil {
			return nil, false, err
		}
		if oldBlobID > 0 {
			if err := releaseDAVBlobTx(tx, oldBlobID, 1); err != nil {
				return nil, false, err
			}
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, false, err
	}
	node, err := GetDAVNodeByID(memberID, nodeID)
	if node != nil {
		node.Path = normalized
	}
	return node, deduplicated, err
}

func writeDAVBlobChunksTx(ctx context.Context, tx *sql.Tx, blobID int64, name, tempName string, expectedCount int) (int64, error) {
	file, err := os.Open(tempName)
	if err != nil {
		return 0, err
	}
	defer file.Close()
	buffer := make([]byte, DAVChunkSize)
	var storedTotal int64
	chunkIndex := 0
	for {
		if err := ctx.Err(); err != nil {
			return 0, err
		}
		n, readErr := io.ReadFull(file, buffer)
		if n > 0 {
			original := buffer[:n]
			stored, compression, err := encodeDAVContent(name, original)
			if err != nil {
				return 0, err
			}
			chunkHash := sha256.Sum256(original)
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO dav_blob_chunks(
					blob_id, chunk_index, original_size, stored_size, compression, chunk_hash, content_blob
				) VALUES (?, ?, ?, ?, ?, ?, ?)`,
				blobID, chunkIndex, n, len(stored), compression,
				hex.EncodeToString(chunkHash[:]), stored); err != nil {
				return 0, err
			}
			storedTotal += int64(len(stored))
			chunkIndex++
		}
		if readErr == io.EOF || readErr == io.ErrUnexpectedEOF {
			break
		}
		if readErr != nil {
			return 0, readErr
		}
	}
	if chunkIndex != expectedCount {
		return 0, fmt.Errorf("webdav chunk count mismatch: wrote %d, expected %d", chunkIndex, expectedCount)
	}
	return storedTotal, nil
}

func LinkDAVBlob(memberID int64, value string, blobID int64, contentType string, quotaBytes int64) (*DAVNode, error) {
	normalized, err := NormalizeDAVPath(value)
	if err != nil || normalized == "" {
		return nil, ErrDAVInvalidPath
	}
	if _, err := EnsureDAVRoot(memberID); err != nil {
		return nil, err
	}
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	blob, err := getDAVBlobByIDTx(tx, blobID)
	if err != nil {
		return nil, err
	}
	parentPath, name := path.Split(normalized)
	parent, err := resolveDAVNode(tx, memberID, strings.TrimSuffix(parentPath, "/"))
	if err != nil {
		return nil, err
	}
	existing, err := resolveDAVNode(tx, memberID, normalized)
	if err != nil && !errors.Is(err, ErrDAVNotFound) {
		return nil, err
	}
	if errors.Is(err, ErrDAVNotFound) {
		existing = nil
		err = nil
	}
	if existing != nil && existing.IsDir {
		return nil, ErrDAVIsDirectory
	}
	var existingNodeID, oldBlobID int64
	if existing != nil {
		existingNodeID = existing.NodeID
		if existing.BlobID != nil {
			oldBlobID = *existing.BlobID
		}
	}
	if err := ensureDAVStoredQuotaTx(tx, memberID, existingNodeID, oldBlobID, blob, quotaBytes); err != nil {
		return nil, err
	}
	if contentType == "" {
		contentType = mime.TypeByExtension(strings.ToLower(path.Ext(name)))
	}
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	now := time.Now()
	var nodeID int64
	if existing != nil {
		nodeID = existing.NodeID
		_, err = tx.Exec(`
			UPDATE dav_nodes SET mime_type=?, blob_id=?, etag=?, modify_time=?
			WHERE member_id=? AND node_id=?`,
			contentType, blobID, blob.ContentHash, now, memberID, nodeID)
	} else {
		result, insertErr := tx.Exec(`
			INSERT INTO dav_nodes(member_id, parent_id, name, is_dir, mime_type, blob_id, etag, create_time, modify_time)
			VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?)`,
			memberID, parent.NodeID, name, contentType, blobID, blob.ContentHash, now, now)
		if insertErr != nil {
			return nil, insertErr
		}
		nodeID, _ = result.LastInsertId()
	}
	if err != nil {
		return nil, err
	}
	if oldBlobID != blobID {
		if _, err := tx.Exec("UPDATE dav_blobs SET ref_count=ref_count+1 WHERE blob_id=?", blobID); err != nil {
			return nil, err
		}
		if oldBlobID > 0 {
			if err := releaseDAVBlobTx(tx, oldBlobID, 1); err != nil {
				return nil, err
			}
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	node, err := GetDAVNodeByID(memberID, nodeID)
	if node != nil {
		node.Path = normalized
	}
	return node, err
}

func FindDAVBlob(contentHash string, originalSize int64) (*DAVBlob, error) {
	return findDAVBlobTx(WebDAVDB, strings.ToLower(strings.TrimSpace(contentHash)), originalSize)
}

func FindDAVBlobByID(blobID int64) (*DAVBlob, error) {
	return getDAVBlobByIDTx(WebDAVDB, blobID)
}

type DAVReadSeekCloser interface {
	io.Reader
	io.Seeker
	io.Closer
}

func OpenDAVBlob(blob *DAVBlob) (DAVReadSeekCloser, error) {
	return OpenDAVBlobContext(context.Background(), blob)
}

func OpenDAVBlobContext(ctx context.Context, blob *DAVBlob) (DAVReadSeekCloser, error) {
	if blob == nil || blob.BlobID <= 0 {
		return nil, ErrDAVNotFound
	}
	if err := validateDAVBlobMetadata(blob); err != nil {
		return nil, err
	}
	release, err := acquireDAVTransfer(ctx)
	if err != nil {
		return nil, err
	}
	tx, err := WebDAVDB.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		release()
		return nil, err
	}
	var blobID int64
	if err := tx.QueryRowContext(ctx, "SELECT blob_id FROM dav_blobs WHERE blob_id=?", blob.BlobID).Scan(&blobID); err != nil {
		_ = tx.Rollback()
		release()
		if err == sql.ErrNoRows {
			return nil, ErrDAVNotFound
		}
		return nil, err
	}
	return &davBlobReader{
		ctx:         ctx,
		blob:        *blob,
		tx:          tx,
		loadedIndex: -1,
		release:     release,
	}, nil
}

func findDAVBlobTx(q interface {
	QueryRow(query string, args ...any) *sql.Row
}, contentHash string, originalSize int64) (*DAVBlob, error) {
	fields := `blob_id, content_hash, original_size, stored_size, chunk_size,
		chunk_count, ref_count, create_time`
	row := q.QueryRow("SELECT "+fields+" FROM dav_blobs WHERE content_hash=? AND original_size=?",
		contentHash, originalSize)
	return scanDAVBlob(row)
}

func getDAVBlobByIDTx(q interface {
	QueryRow(query string, args ...any) *sql.Row
}, blobID int64) (*DAVBlob, error) {
	fields := `blob_id, content_hash, original_size, stored_size, chunk_size,
		chunk_count, ref_count, create_time`
	row := q.QueryRow("SELECT "+fields+" FROM dav_blobs WHERE blob_id=?", blobID)
	return scanDAVBlob(row)
}

func scanDAVBlob(row rowScan) (*DAVBlob, error) {
	var blob DAVBlob
	if err := row.Scan(
		&blob.BlobID, &blob.ContentHash, &blob.OriginalSize, &blob.StoredSize,
		&blob.ChunkSize, &blob.ChunkCount, &blob.RefCount, &blob.CreateTime,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrDAVNotFound
		}
		return nil, err
	}
	if err := validateDAVBlobMetadata(&blob); err != nil {
		return nil, ErrDAVCorruptBlob
	}
	return &blob, nil
}

func validateDAVBlobMetadata(blob *DAVBlob) error {
	if blob == nil || blob.BlobID <= 0 || blob.OriginalSize < 0 || blob.StoredSize < 0 ||
		blob.ChunkSize != DAVChunkSize || blob.ChunkCount < 0 {
		return ErrDAVCorruptBlob
	}
	expectedChunks := int((blob.OriginalSize + blob.ChunkSize - 1) / blob.ChunkSize)
	if blob.ChunkCount != expectedChunks {
		return ErrDAVCorruptBlob
	}
	return nil
}

func MemberReferencesDAVBlob(memberID, blobID int64) (bool, error) {
	var count int
	err := WebDAVDB.QueryRow(`
		SELECT COUNT(*) FROM dav_nodes
		WHERE member_id=? AND blob_id=?`, memberID, blobID).Scan(&count)
	return count > 0, err
}

func ReadDAVFile(memberID int64, value string) (*DAVNode, *DAVBlob, DAVReadSeekCloser, error) {
	return ReadDAVFileContext(context.Background(), memberID, value)
}

func ReadDAVFileContext(ctx context.Context, memberID int64, value string) (*DAVNode, *DAVBlob, DAVReadSeekCloser, error) {
	node, err := GetDAVNode(memberID, value)
	if err != nil {
		return nil, nil, nil, err
	}
	if node.IsDir || node.BlobID == nil {
		return nil, nil, nil, ErrDAVIsDirectory
	}
	blob, err := getDAVBlobByIDTx(WebDAVDB, *node.BlobID)
	if err != nil {
		return nil, nil, nil, err
	}
	reader, err := OpenDAVBlobContext(ctx, blob)
	if err != nil {
		return nil, nil, nil, err
	}
	return node, blob, reader, nil
}

type davBlobReader struct {
	ctx         context.Context
	blob        DAVBlob
	tx          *sql.Tx
	position    int64
	loadedIndex int64
	loaded      []byte
	release     func()
	closed      bool
}

func (r *davBlobReader) Read(destination []byte) (int, error) {
	if r.closed {
		return 0, os.ErrClosed
	}
	if len(destination) == 0 {
		return 0, nil
	}
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	if r.position >= r.blob.OriginalSize {
		return 0, io.EOF
	}
	written := 0
	for len(destination) > 0 && r.position < r.blob.OriginalSize {
		index := r.position / r.blob.ChunkSize
		if r.loadedIndex != index {
			chunk, err := loadDAVBlobChunkFrom(r.ctx, r.tx, r.blob, int(index))
			if err != nil {
				return written, err
			}
			r.loaded = chunk
			r.loadedIndex = index
		}
		offset := int(r.position % r.blob.ChunkSize)
		if offset >= len(r.loaded) {
			return written, ErrDAVCorruptBlob
		}
		n := copy(destination, r.loaded[offset:])
		if n == 0 {
			return written, ErrDAVCorruptBlob
		}
		destination = destination[n:]
		written += n
		r.position += int64(n)
	}
	if written == 0 {
		return 0, io.EOF
	}
	return written, nil
}

func (r *davBlobReader) Seek(offset int64, whence int) (int64, error) {
	if r.closed {
		return 0, os.ErrClosed
	}
	var next int64
	switch whence {
	case io.SeekStart:
		next = offset
	case io.SeekCurrent:
		next = r.position + offset
	case io.SeekEnd:
		next = r.blob.OriginalSize + offset
	default:
		return 0, errors.New("invalid seek whence")
	}
	if next < 0 {
		return 0, errors.New("negative seek offset")
	}
	r.position = next
	return next, nil
}

func (r *davBlobReader) Close() error {
	if r.closed {
		return nil
	}
	r.closed = true
	r.loaded = nil
	if r.tx != nil {
		_ = r.tx.Rollback()
		r.tx = nil
	}
	if r.release != nil {
		r.release()
		r.release = nil
	}
	return nil
}

func ReadDAVBlobChunkContext(ctx context.Context, blob *DAVBlob, chunkIndex int) ([]byte, error) {
	if blob == nil || blob.BlobID <= 0 {
		return nil, ErrDAVNotFound
	}
	release, err := acquireDAVTransfer(ctx)
	if err != nil {
		return nil, err
	}
	defer release()
	return loadDAVBlobChunk(ctx, *blob, chunkIndex)
}

func loadDAVBlobChunk(ctx context.Context, blob DAVBlob, chunkIndex int) ([]byte, error) {
	return loadDAVBlobChunkFrom(ctx, WebDAVDB, blob, chunkIndex)
}

func loadDAVBlobChunkFrom(ctx context.Context, queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}, blob DAVBlob, chunkIndex int) ([]byte, error) {
	if chunkIndex < 0 || chunkIndex >= blob.ChunkCount {
		return nil, ErrDAVNotFound
	}
	var originalSize, storedSize int
	var compression, expectedHash string
	var stored []byte
	err := queryer.QueryRowContext(ctx, `
		SELECT original_size, stored_size, compression, chunk_hash, content_blob
		FROM dav_blob_chunks WHERE blob_id=? AND chunk_index=?`,
		blob.BlobID, chunkIndex).Scan(&originalSize, &storedSize, &compression, &expectedHash, &stored)
	if err == sql.ErrNoRows {
		return nil, ErrDAVCorruptBlob
	}
	if err != nil {
		return nil, err
	}
	expectedOriginalSize := int(blob.ChunkSize)
	if chunkIndex == blob.ChunkCount-1 {
		expectedOriginalSize = int(blob.OriginalSize - int64(chunkIndex)*blob.ChunkSize)
	}
	if originalSize != expectedOriginalSize || storedSize != len(stored) {
		return nil, ErrDAVCorruptBlob
	}
	var original []byte
	switch compression {
	case DAVCompressionNone:
		original = stored
	case DAVCompressionGzip:
		reader, err := gzip.NewReader(bytes.NewReader(stored))
		if err != nil {
			return nil, ErrDAVCorruptBlob
		}
		original, err = io.ReadAll(io.LimitReader(reader, int64(originalSize)+1))
		closeErr := reader.Close()
		if err != nil || closeErr != nil {
			return nil, ErrDAVCorruptBlob
		}
	default:
		return nil, ErrDAVCorruptBlob
	}
	if len(original) != originalSize {
		return nil, ErrDAVCorruptBlob
	}
	digest := sha256.Sum256(original)
	if !strings.EqualFold(expectedHash, hex.EncodeToString(digest[:])) {
		return nil, ErrDAVCorruptBlob
	}
	return original, nil
}

func encodeDAVContent(name string, content []byte) ([]byte, string, error) {
	if !ShouldTryDAVCompression(name, content) {
		return content, DAVCompressionNone, nil
	}
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	if _, err := writer.Write(content); err != nil {
		return nil, "", err
	}
	if err := writer.Close(); err != nil {
		return nil, "", err
	}
	if len(compressed.Bytes()) >= len(content) || float64(len(content)-compressed.Len())/float64(len(content)) < davCompressionGain {
		return content, DAVCompressionNone, nil
	}
	return compressed.Bytes(), DAVCompressionGzip, nil
}

func ShouldTryDAVCompression(name string, content []byte) bool {
	if len(content) < davCompressionMin {
		return false
	}
	ext := strings.TrimPrefix(strings.ToLower(path.Ext(name)), ".")
	if davAlreadyCompressedExt[ext] {
		return false
	}
	sample := content
	if len(sample) > davCompressionTry {
		sample = sample[:davCompressionTry]
	}
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	_, _ = writer.Write(sample)
	_ = writer.Close()
	if compressed.Len() >= len(sample) {
		return false
	}
	return float64(len(sample)-compressed.Len())/float64(len(sample)) >= davCompressionGain
}

var davAlreadyCompressedExt = map[string]bool{
	"jpg": true, "jpeg": true, "png": true, "gif": true, "webp": true, "avif": true, "heic": true,
	"mp3": true, "aac": true, "m4a": true, "ogg": true, "flac": true, "wav": true,
	"mp4": true, "webm": true, "mov": true, "m4v": true, "mkv": true, "avi": true,
	"zip": true, "gz": true, "bz2": true, "xz": true, "7z": true, "rar": true, "tar": true,
	"pdf": true, "woff": true, "woff2": true, "docx": true, "xlsx": true, "pptx": true,
}

func detectDAVMIME(name, tempName string) string {
	if byExt := mime.TypeByExtension(strings.ToLower(path.Ext(name))); byExt != "" {
		return byExt
	}
	file, err := os.Open(tempName)
	if err != nil {
		return "application/octet-stream"
	}
	defer file.Close()
	sample := make([]byte, 512)
	n, _ := file.Read(sample)
	return http.DetectContentType(sample[:n])
}

func RenameDAVNode(memberID int64, oldValue, newValue string) error {
	oldPath, err := NormalizeDAVPath(oldValue)
	if err != nil || oldPath == "" {
		return ErrDAVInvalidPath
	}
	newPath, err := NormalizeDAVPath(newValue)
	if err != nil || newPath == "" {
		return ErrDAVInvalidPath
	}
	if newPath == oldPath || strings.HasPrefix(newPath+"/", oldPath+"/") {
		return ErrDAVInvalidPath
	}
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	node, err := resolveDAVNode(tx, memberID, oldPath)
	if err != nil {
		return err
	}
	parentPath, name := path.Split(newPath)
	parent, err := resolveDAVNode(tx, memberID, strings.TrimSuffix(parentPath, "/"))
	if err != nil {
		return err
	}
	if !parent.IsDir {
		return ErrDAVNotDirectory
	}
	if _, err := resolveDAVNode(tx, memberID, newPath); err == nil {
		return ErrDAVAlreadyExists
	} else if !errors.Is(err, ErrDAVNotFound) {
		return err
	}
	result, err := tx.Exec(`
		UPDATE dav_nodes SET parent_id=?, name=?, modify_time=?
		WHERE member_id=? AND node_id=?`, parent.NodeID, name, time.Now(), memberID, node.NodeID)
	if isDAVUniqueError(err) {
		return ErrDAVAlreadyExists
	}
	if err != nil {
		return err
	}
	affected, _ := result.RowsAffected()
	if affected != 1 {
		return ErrDAVNotFound
	}
	return tx.Commit()
}

func CopyDAVNode(memberID int64, sourceValue, targetValue string, quotaBytes int64) error {
	sourcePath, err := NormalizeDAVPath(sourceValue)
	if err != nil || sourcePath == "" {
		return ErrDAVInvalidPath
	}
	targetPath, err := NormalizeDAVPath(targetValue)
	if err != nil || targetPath == "" || strings.HasPrefix(targetPath+"/", sourcePath+"/") {
		return ErrDAVInvalidPath
	}
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	source, err := resolveDAVNode(tx, memberID, sourcePath)
	if err != nil {
		return err
	}
	if _, err := resolveDAVNode(tx, memberID, targetPath); err == nil {
		return ErrDAVAlreadyExists
	} else if !errors.Is(err, ErrDAVNotFound) {
		return err
	}
	parentPath, name := path.Split(targetPath)
	parent, err := resolveDAVNode(tx, memberID, strings.TrimSuffix(parentPath, "/"))
	if err != nil {
		return err
	}
	if !parent.IsDir {
		return ErrDAVNotDirectory
	}
	if err := copyDAVSubtreeTx(tx, memberID, source.NodeID, parent.NodeID, name); err != nil {
		return err
	}
	return tx.Commit()
}

func copyDAVSubtreeTx(tx *sql.Tx, memberID, sourceID, targetParentID int64, targetName string) error {
	source, err := getDAVNodeByIDTx(tx, memberID, sourceID)
	if err != nil {
		return err
	}
	now := time.Now()
	result, err := tx.Exec(`
		INSERT INTO dav_nodes(member_id, parent_id, name, is_dir, mime_type, blob_id, etag, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		memberID, targetParentID, targetName, boolInt(source.IsDir), source.MIMEType,
		source.BlobID, source.ETag, now, now)
	if err != nil {
		return err
	}
	newID, _ := result.LastInsertId()
	if source.BlobID != nil {
		if _, err := tx.Exec("UPDATE dav_blobs SET ref_count=ref_count+1 WHERE blob_id=?", *source.BlobID); err != nil {
			return err
		}
	}
	if !source.IsDir {
		return nil
	}
	rows, err := tx.Query("SELECT node_id, name FROM dav_nodes WHERE member_id=? AND parent_id=? ORDER BY node_id", memberID, sourceID)
	if err != nil {
		return err
	}
	type child struct {
		id   int64
		name string
	}
	children := make([]child, 0)
	for rows.Next() {
		var item child
		if err := rows.Scan(&item.id, &item.name); err != nil {
			rows.Close()
			return err
		}
		children = append(children, item)
	}
	if err := rows.Close(); err != nil {
		return err
	}
	for _, item := range children {
		if err := copyDAVSubtreeTx(tx, memberID, item.id, newID, item.name); err != nil {
			return err
		}
	}
	return nil
}

func DeleteDAVNode(memberID int64, value string, recursive bool) error {
	normalized, err := NormalizeDAVPath(value)
	if err != nil || normalized == "" {
		return ErrDAVInvalidPath
	}
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	node, err := resolveDAVNode(tx, memberID, normalized)
	if err != nil {
		return err
	}
	if node.IsDir && !recursive {
		var childCount int
		if err := tx.QueryRow("SELECT COUNT(*) FROM dav_nodes WHERE member_id=? AND parent_id=?", memberID, node.NodeID).Scan(&childCount); err != nil {
			return err
		}
		if childCount > 0 {
			return errors.New("directory is not empty")
		}
	}
	blobCounts, err := davSubtreeBlobCountsTx(tx, memberID, node.NodeID)
	if err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM dav_nodes WHERE member_id=? AND node_id=?", memberID, node.NodeID); err != nil {
		return err
	}
	for blobID, count := range blobCounts {
		if err := releaseDAVBlobTx(tx, blobID, count); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func davSubtreeBlobCountsTx(tx *sql.Tx, memberID, nodeID int64) (map[int64]int64, error) {
	rows, err := tx.Query(`
		WITH RECURSIVE subtree(node_id) AS (
			SELECT node_id FROM dav_nodes WHERE member_id=? AND node_id=?
			UNION ALL
			SELECT n.node_id FROM dav_nodes n JOIN subtree s ON n.parent_id=s.node_id
			WHERE n.member_id=?
		)
		SELECT blob_id, COUNT(*) FROM dav_nodes
		WHERE node_id IN (SELECT node_id FROM subtree) AND blob_id IS NOT NULL
		GROUP BY blob_id`, memberID, nodeID, memberID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[int64]int64)
	for rows.Next() {
		var id, count int64
		if err := rows.Scan(&id, &count); err != nil {
			return nil, err
		}
		result[id] = count
	}
	return result, rows.Err()
}

func releaseDAVBlobTx(tx *sql.Tx, blobID, count int64) error {
	if count < 1 {
		return nil
	}
	if _, err := tx.Exec(`
		UPDATE dav_blobs SET ref_count=MAX(ref_count-?, 0) WHERE blob_id=?`,
		count, blobID); err != nil {
		return err
	}
	_, err := tx.Exec(`
		DELETE FROM dav_blobs
		WHERE blob_id=? AND ref_count=0
		  AND NOT EXISTS (SELECT 1 FROM dav_nodes WHERE blob_id=?)`,
		blobID, blobID)
	return err
}

func davLogicalUsageTx(q interface {
	QueryRow(query string, args ...any) *sql.Row
}, memberID int64) (int64, error) {
	var total int64
	err := q.QueryRow(`
		SELECT COALESCE(SUM(b.original_size), 0)
		FROM dav_nodes n JOIN dav_blobs b ON b.blob_id=n.blob_id
		WHERE n.member_id=?`, memberID).Scan(&total)
	return total, err
}

func davStoredUsageTx(q interface {
	QueryRow(query string, args ...any) *sql.Row
}, memberID int64) (int64, error) {
	var total int64
	err := q.QueryRow(`
		SELECT COALESCE(SUM(stored_size), 0)
		FROM dav_blobs
		WHERE blob_id IN (
			SELECT DISTINCT blob_id
			FROM dav_nodes
			WHERE member_id=? AND blob_id IS NOT NULL
		)`, memberID).Scan(&total)
	return total, err
}

func ensureDAVStoredQuotaTx(tx *sql.Tx, memberID, existingNodeID, oldBlobID int64, newBlob *DAVBlob, quotaBytes int64) error {
	if quotaBytes <= 0 || newBlob == nil {
		return nil
	}
	used, err := davStoredUsageTx(tx, memberID)
	if err != nil {
		return err
	}
	projected := used
	if oldBlobID > 0 && oldBlobID != newBlob.BlobID {
		var remainingReferences int64
		if err := tx.QueryRow(`
			SELECT COUNT(*)
			FROM dav_nodes
			WHERE member_id=? AND blob_id=? AND node_id<>?`,
			memberID, oldBlobID, existingNodeID).Scan(&remainingReferences); err != nil {
			return err
		}
		if remainingReferences == 0 {
			var oldStoredSize int64
			if err := tx.QueryRow("SELECT stored_size FROM dav_blobs WHERE blob_id=?", oldBlobID).Scan(&oldStoredSize); err != nil {
				return err
			}
			projected -= oldStoredSize
		}
	}
	if oldBlobID != newBlob.BlobID {
		var existingReferences int64
		if err := tx.QueryRow(`
			SELECT COUNT(*)
			FROM dav_nodes
			WHERE member_id=? AND blob_id=?`,
			memberID, newBlob.BlobID).Scan(&existingReferences); err != nil {
			return err
		}
		if existingReferences == 0 {
			projected += newBlob.StoredSize
		}
	}
	if projected > quotaBytes {
		return ErrDAVQuotaExceeded
	}
	return nil
}

func davSubtreeLogicalSizeTx(tx *sql.Tx, nodeID int64) (int64, error) {
	var total int64
	err := tx.QueryRow(`
		WITH RECURSIVE subtree(node_id) AS (
			SELECT node_id FROM dav_nodes WHERE node_id=?
			UNION ALL
			SELECT n.node_id FROM dav_nodes n JOIN subtree s ON n.parent_id=s.node_id
		)
		SELECT COALESCE(SUM(b.original_size), 0)
		FROM dav_nodes n JOIN dav_blobs b ON b.blob_id=n.blob_id
		WHERE n.node_id IN (SELECT node_id FROM subtree)`, nodeID).Scan(&total)
	return total, err
}

func getDAVNodeByIDTx(q interface {
	QueryRow(query string, args ...any) *sql.Row
}, memberID, nodeID int64) (*DAVNode, error) {
	row := q.QueryRow(`
		SELECT n.node_id, n.member_id, n.parent_id, n.name, n.is_dir, n.mime_type,
		       n.blob_id, n.etag, COALESCE(b.original_size, 0), COALESCE(b.stored_size, 0),
		       n.create_time, n.modify_time
		FROM dav_nodes n LEFT JOIN dav_blobs b ON b.blob_id=n.blob_id
		WHERE n.member_id=? AND n.node_id=?`, memberID, nodeID)
	node, err := scanDAVNode(row)
	if err == sql.ErrNoRows {
		return nil, ErrDAVNotFound
	}
	return node, err
}

func GetDAVUsage(memberID, quotaBytes int64) (DAVUsage, error) {
	var usage DAVUsage
	usage.QuotaBytes = quotaBytes
	err := WebDAVDB.QueryRow(`
		WITH member_nodes AS (
			SELECT n.is_dir, n.parent_id, n.blob_id,
			       COALESCE(b.original_size, 0) AS original_size
			FROM dav_nodes n
			LEFT JOIN dav_blobs b ON b.blob_id=n.blob_id
			WHERE n.member_id=?
		),
		member_blobs AS (
			SELECT DISTINCT b.blob_id, b.original_size, b.stored_size
			FROM dav_nodes n
			JOIN dav_blobs b ON b.blob_id=n.blob_id
			WHERE n.member_id=?
		)
		SELECT
			COALESCE((SELECT SUM(CASE WHEN is_dir=0 THEN 1 ELSE 0 END) FROM member_nodes), 0),
			COALESCE((SELECT SUM(CASE WHEN is_dir=1 AND parent_id IS NOT NULL THEN 1 ELSE 0 END) FROM member_nodes), 0),
			COALESCE((SELECT SUM(CASE WHEN is_dir=0 THEN original_size ELSE 0 END) FROM member_nodes), 0),
			COALESCE((SELECT SUM(stored_size) FROM member_blobs), 0),
			COALESCE((SELECT SUM(CASE WHEN is_dir=0 THEN original_size ELSE 0 END) FROM member_nodes), 0)
				- COALESCE((SELECT SUM(original_size) FROM member_blobs), 0),
			COALESCE((SELECT SUM(original_size-stored_size) FROM member_blobs), 0)`,
		memberID, memberID).Scan(
		&usage.FileCount, &usage.DirectoryCount, &usage.LogicalBytes, &usage.StoredBytes,
		&usage.DeduplicatedBytes, &usage.CompressionSavedBytes)
	return usage, err
}

func CreateOrUpdateDAVPublicAsset(memberID, nodeID int64, publicPath string) (*DAVPublicAsset, error) {
	publicPath, err := NormalizeDAVPublicPath(publicPath)
	if err != nil {
		return nil, err
	}
	node, err := GetDAVNodeByID(memberID, nodeID)
	if err != nil {
		return nil, err
	}
	if node.IsDir {
		return nil, ErrDAVIsDirectory
	}
	now := time.Now()
	_, err = WebDAVDB.Exec(`
		INSERT INTO dav_public_assets(member_id, node_id, public_path, enabled, create_time, modify_time)
		VALUES (?, ?, ?, 1, ?, ?)
		ON CONFLICT(node_id) DO UPDATE SET
			public_path=excluded.public_path,
			enabled=1,
			modify_time=excluded.modify_time`,
		memberID, nodeID, publicPath, now, now)
	if isDAVUniqueError(err) {
		return nil, ErrDAVAlreadyExists
	}
	if err != nil {
		return nil, err
	}
	return GetDAVPublicAssetByNode(memberID, nodeID)
}

func NormalizeDAVPublicPath(value string) (string, error) {
	normalized, err := NormalizeDAVPath(value)
	if err != nil || normalized == "" || strings.HasPrefix(normalized, ".") {
		return "", ErrDAVInvalidPath
	}
	for _, part := range strings.Split(normalized, "/") {
		if strings.HasPrefix(part, ".") || part == "dav" || part == "dav-public" {
			return "", ErrDAVInvalidPath
		}
	}
	return normalized, nil
}

func GetDAVPublicAssetByNode(memberID, nodeID int64) (*DAVPublicAsset, error) {
	var asset DAVPublicAsset
	var enabled int
	err := WebDAVDB.QueryRow(`
		SELECT asset_id, member_id, node_id, public_path, enabled, create_time, modify_time
		FROM dav_public_assets WHERE member_id=? AND node_id=?`,
		memberID, nodeID).Scan(
		&asset.AssetID, &asset.MemberID, &asset.NodeID, &asset.PublicPath,
		&enabled, &asset.CreateTime, &asset.ModifyTime)
	if err == sql.ErrNoRows {
		return nil, ErrDAVNotFound
	}
	asset.Enabled = enabled == 1
	return &asset, err
}

func DeleteDAVPublicAsset(memberID, nodeID int64) error {
	result, err := WebDAVDB.Exec("DELETE FROM dav_public_assets WHERE member_id=? AND node_id=?", memberID, nodeID)
	if err != nil {
		return err
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		return ErrDAVNotFound
	}
	return nil
}

func ResolveDAVPublicAsset(memberID int64, publicPath string) (*DAVNode, *DAVBlob, error) {
	normalized, err := NormalizeDAVPublicPath(publicPath)
	if err != nil {
		return nil, nil, err
	}
	row := WebDAVDB.QueryRow(`
		SELECT n.node_id, n.member_id, n.parent_id, n.name, n.is_dir, n.mime_type,
		       n.blob_id, n.etag, b.original_size, b.stored_size,
		       n.create_time, n.modify_time,
		       b.blob_id, b.content_hash, b.original_size, b.stored_size,
		       b.chunk_size, b.chunk_count, b.ref_count, b.create_time
		FROM dav_public_assets p
		JOIN dav_nodes n ON n.node_id=p.node_id AND n.member_id=p.member_id
		JOIN dav_blobs b ON b.blob_id=n.blob_id
		WHERE p.member_id=? AND p.public_path=? AND p.enabled=1`,
		memberID, normalized)
	var node DAVNode
	var parentID, nodeBlobID sql.NullInt64
	var isDir int
	var blob DAVBlob
	if err := row.Scan(
		&node.NodeID, &node.MemberID, &parentID, &node.Name, &isDir, &node.MIMEType,
		&nodeBlobID, &node.ETag, &node.Size, &node.StoredSize, &node.CreateTime, &node.ModifyTime,
		&blob.BlobID, &blob.ContentHash, &blob.OriginalSize, &blob.StoredSize,
		&blob.ChunkSize, &blob.ChunkCount, &blob.RefCount, &blob.CreateTime,
	); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil, ErrDAVNotFound
		}
		return nil, nil, err
	}
	node.IsDir = isDir == 1
	if parentID.Valid {
		value := parentID.Int64
		node.ParentID = &value
	}
	if nodeBlobID.Valid {
		value := nodeBlobID.Int64
		node.BlobID = &value
	}
	if err := validateDAVBlobMetadata(&blob); err != nil {
		return nil, nil, err
	}
	return &node, &blob, nil
}

func ResetDAVAppPassword(memberID int64) (string, error) {
	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	secret := base64.RawURLEncoding.EncodeToString(raw)
	if err := SetDAVAppPassword(memberID, secret); err != nil {
		return "", err
	}
	return secret, nil
}

func SetDAVAppPassword(memberID int64, secret string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(secret), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	davAuthCacheMu.Lock()
	defer davAuthCacheMu.Unlock()
	now := time.Now()
	_, err = WebDAVDB.Exec(`
		INSERT INTO dav_app_credentials(member_id, secret_hash, create_time, modify_time)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(member_id) DO UPDATE SET
			secret_hash=excluded.secret_hash,
			modify_time=excluded.modify_time,
			last_use_time=NULL`,
		memberID, string(hash), now, now)
	if err != nil {
		return err
	}
	davAuthCache.Delete(memberID)
	return nil
}

func HasDAVAppPassword(memberID int64) (bool, error) {
	var count int
	err := WebDAVDB.QueryRow("SELECT COUNT(*) FROM dav_app_credentials WHERE member_id=?", memberID).Scan(&count)
	return count > 0, err
}

func VerifyDAVAppPassword(memberID int64, secret string) bool {
	davAuthCacheMu.RLock()
	defer davAuthCacheMu.RUnlock()
	digest := sha256.Sum256([]byte(secret))
	if cached, ok := davAuthCache.Load(memberID); ok {
		entry := cached.(davAuthCacheEntry)
		if time.Now().Before(entry.expiresAt) &&
			subtle.ConstantTimeCompare(entry.secretDigest[:], digest[:]) == 1 {
			return true
		}
		davAuthCache.Delete(memberID)
	}
	var hash string
	err := WebDAVDB.QueryRow("SELECT secret_hash FROM dav_app_credentials WHERE member_id=?", memberID).Scan(&hash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(secret)) != nil {
		return false
	}
	davAuthCache.Store(memberID, davAuthCacheEntry{
		secretDigest: digest,
		expiresAt:    time.Now().Add(davAuthCacheTTL),
	})
	_, _ = WebDAVDB.Exec("UPDATE dav_app_credentials SET last_use_time=? WHERE member_id=?", time.Now(), memberID)
	return true
}

func RevokeDAVAppPassword(memberID int64) error {
	davAuthCacheMu.Lock()
	defer davAuthCacheMu.Unlock()
	davAuthCache.Delete(memberID)
	_, err := WebDAVDB.Exec("DELETE FROM dav_app_credentials WHERE member_id=?", memberID)
	return err
}

func clearDAVAuthCache() {
	davAuthCacheMu.Lock()
	defer davAuthCacheMu.Unlock()
	davAuthCache.Range(func(key, _ any) bool {
		davAuthCache.Delete(key)
		return true
	})
}

func BackupWebDAVDatabase(destination string) error {
	if WebDAVDB == nil || strings.TrimSpace(destination) == "" {
		return errors.New("webdav db is not initialized")
	}
	_ = os.Remove(destination)
	_, err := WebDAVDB.Exec("VACUUM INTO ?", destination)
	return err
}

func RepairDAVBlobReferences() error {
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`
		UPDATE dav_blobs
		SET ref_count=(SELECT COUNT(*) FROM dav_nodes WHERE dav_nodes.blob_id=dav_blobs.blob_id)`); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		DELETE FROM dav_blobs
		WHERE ref_count=0
		  AND NOT EXISTS (SELECT 1 FROM dav_nodes WHERE dav_nodes.blob_id=dav_blobs.blob_id)`); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	return ValidateDAVBlobStorage()
}

func ValidateDAVBlobStorage() error {
	var blobID int64
	err := WebDAVDB.QueryRow(`
		SELECT b.blob_id
		FROM dav_blobs b
		LEFT JOIN dav_blob_chunks c ON c.blob_id=b.blob_id
		GROUP BY b.blob_id
			HAVING b.chunk_size != ?
			    OR b.chunk_count != ((b.original_size + b.chunk_size - 1) / b.chunk_size)
			    OR b.chunk_count != COUNT(c.chunk_index)
			    OR (b.chunk_count > 0 AND (
			        MIN(c.chunk_index) != 0 OR MAX(c.chunk_index) != b.chunk_count - 1
			    ))
			    OR b.original_size != COALESCE(SUM(c.original_size), 0)
			    OR b.stored_size != COALESCE(SUM(c.stored_size), 0)
		LIMIT 1`, DAVChunkSize).Scan(&blobID)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return err
	}
	return fmt.Errorf("%w: inconsistent metadata for blob %d", ErrDAVCorruptBlob, blobID)
}

func RemoveDAVMemberData(memberID int64) error {
	if memberID <= 0 {
		return nil
	}
	davAuthCacheMu.Lock()
	defer davAuthCacheMu.Unlock()
	tx, err := WebDAVDB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	root, err := getDAVRoot(tx, memberID)
	if err != nil && !errors.Is(err, ErrDAVNotFound) {
		return err
	}
	if root != nil {
		counts, err := davSubtreeBlobCountsTx(tx, memberID, root.NodeID)
		if err != nil {
			return err
		}
		if _, err := tx.Exec("DELETE FROM dav_nodes WHERE member_id=? AND node_id=?", memberID, root.NodeID); err != nil {
			return err
		}
		for blobID, count := range counts {
			if err := releaseDAVBlobTx(tx, blobID, count); err != nil {
				return err
			}
		}
	}
	if _, err := tx.Exec("DELETE FROM dav_app_credentials WHERE member_id=?", memberID); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	davAuthCache.Delete(memberID)
	return nil
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func isDAVUniqueError(err error) bool {
	if err == nil {
		return false
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "unique constraint")
}

func isDAVBusyError(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "database is locked") ||
		strings.Contains(message, "sqlite_busy")
}
