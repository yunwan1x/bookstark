package models

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"errors"
	"io"
	"regexp"
	"time"
	"unicode/utf8"
)

var (
	ErrSharedEditToken    = errors.New("shared edit token invalid")
	ErrSharedEditTarget   = errors.New("shared edit target missing or owner changed")
	ErrSharedEditPassword = errors.New("shared edit password invalid")
	ErrSharedEditConflict = errors.New("shared edit source changed")
	ErrSharedEditInput    = errors.New("shared edit input invalid")
)
var sharedSourceHashPattern = regexp.MustCompile("^[0-9a-f]{64}$")

type SharedContentReceipt struct {
	ModifyTime   time.Time
	SourceSHA256 string
}

// One transaction reads current authority and source, then updates content only.
// SQLite snapshot/write conflicts fail closed; never retry using stale values.
func SaveSharedContent(identify, token, source, password string, expectedSourceSHA256 *string) (*SharedContentReceipt, error) {
	return saveSharedContentIdentity(context.Background(), identify, token, source, password, expectedSourceSHA256, nil)
}
func saveSharedContentIdentity(ctx context.Context, identify, token, source, password string, expectedSourceSHA256 *string, expected *SharedEditIdentity) (*SharedContentReceipt, error) {
	if token == "" {
		return nil, ErrSharedEditToken
	}
	if expectedSourceSHA256 != nil && !sharedSourceHashPattern.MatchString(*expectedSourceSHA256) {
		return nil, ErrSharedEditInput
	}
	tx, err := DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	var shareID, targetID, owner int64
	var kind, currentToken string
	err = tx.QueryRowContext(ctx, "SELECT share_id, share_type, target_id, member_id, edit_token FROM md_shares WHERE share_identify = ?", identify).Scan(&shareID, &kind, &targetID, &owner, &currentToken)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrSharedEditTarget
	}
	if err != nil {
		return nil, err
	}
	if currentToken == "" || subtle.ConstantTimeCompare([]byte(currentToken), []byte(token)) != 1 {
		return nil, ErrSharedEditToken
	}
	if expected != nil {
		if err := checkSharedStoredBudget(ctx, tx, kind, targetID); err != nil {
			return nil, err
		}
	}
	var targetOwner int64
	var format, stored, passwordHash string
	switch kind {
	case "blog":
		body := "blog_content"
		if expected != nil {
			body = "COALESCE(blog_content,'')"
		}
		err = tx.QueryRowContext(ctx, "SELECT member_id, COALESCE(editor_type,'markdown'), "+body+", password FROM md_blogs WHERE blog_id = ?", targetID).Scan(&targetOwner, &format, &stored, &passwordHash)
	case "document":
		body := "markdown"
		if expected != nil {
			body = "COALESCE(markdown,'')"
		}
		err = tx.QueryRowContext(ctx, "SELECT member_id, COALESCE(doc_type,'markdown'), "+body+" FROM md_documents WHERE document_id = ?", targetID).Scan(&targetOwner, &format, &stored)
	default:
		return nil, ErrSharedEditInput
	}
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrSharedEditTarget
	}
	if err != nil {
		return nil, err
	}
	if owner <= 0 || targetOwner != owner {
		return nil, ErrSharedEditTarget
	}
	if expected != nil && (expected.ShareID != shareID || expected.TargetID != targetID ||
		expected.OwnerID != owner || expected.ShareType != kind || expected.Format != format ||
		expected.Protected != (passwordHash != "")) {
		return nil, ErrSharedEditConflict
	}
	if expected != nil && kind == "document" {
		var bookID, bookOwner int64
		if err := tx.QueryRowContext(ctx, "SELECT d.book_id,b.member_id FROM md_documents d JOIN md_books b ON b.book_id=d.book_id WHERE d.document_id=?", targetID).Scan(&bookID, &bookOwner); err != nil {
			return nil, ErrSharedEditTarget
		}
		if bookID != expected.BookID || bookOwner != owner {
			return nil, ErrSharedEditConflict
		}
	}
	if expected != nil && kind == "blog" {
		var collection string
		if err := tx.QueryRowContext(ctx, "SELECT blog_type FROM md_blogs WHERE blog_id=?", targetID).Scan(&collection); err != nil {
			return nil, ErrSharedEditTarget
		}
		if collection != expected.Collection {
			return nil, ErrSharedEditConflict
		}
	}
	maxBytes, valid := sharedEditLimit(format)
	if !valid || !utf8.ValidString(source) || len(source) > maxBytes {
		return nil, ErrSharedEditInput
	}
	if expected != nil {
		if err := validateSharedIdentitySource(format, source); err != nil {
			return nil, err
		}
		if reservedSharedEnvelope(stored) && (passwordHash == "" || !IsEncrypted(stored)) {
			return nil, ErrSharedEditPassword
		}
	}
	if passwordHash != "" && !(&Blog{Password: passwordHash}).VerifyPassword(password) {
		return nil, ErrSharedEditPassword
	}
	if expectedSourceSHA256 != nil {
		actual, err := sharedEditFullSource(format, stored, passwordHash != "", password, maxBytes)
		if err != nil {
			return nil, err
		}
		if expected != nil {
			if err := validateSharedIdentitySource(format, actual); err != nil {
				return nil, err
			}
		}
		if sharedEditSourceHash(actual) != *expectedSourceSHA256 {
			return nil, ErrSharedEditConflict
		}
	}
	if expected != nil && expectedSourceSHA256 != nil && sharedEditSourceHash(source) == *expectedSourceSHA256 {
		modified, err := sharedIdentityModified(ctx, tx, kind, targetID)
		if err != nil {
			return nil, err
		}
		if err = tx.Commit(); err != nil {
			return nil, err
		}
		return &SharedContentReceipt{ModifyTime: modified, SourceSHA256: *expectedSourceSHA256}, nil
	}
	if format == RichDocumentType {
		if err := ValidateRichDocument(source); err != nil {
			return nil, ErrSharedEditInput
		}
	}
	if format == PresentationType {
		if err := ValidatePresentation(source); err != nil {
			return nil, ErrSharedEditInput
		}
	}
	encoded, err := EncodeContentForType(format, source)
	if err != nil {
		return nil, err
	}
	// Receipt binds the actual decoded source. The existing codec also supports
	// already-compressed legacy input; never guess its plaintext digest.
	actualSource, err := sharedEditFullSource(format, encoded, false, "", maxBytes)
	if err != nil {
		return nil, err
	}
	if passwordHash != "" {
		encoded, err = EncryptContent(password, encoded)
		if err != nil {
			return nil, err
		}
	}
	now := time.Now()
	authority := " AND EXISTS (SELECT 1 FROM md_shares WHERE share_id = ? AND share_identify = ? AND share_type = ? AND target_id = ? AND member_id = ? AND edit_token = ?)"
	var result sql.Result
	switch kind {
	case "blog":
		result, err = tx.ExecContext(ctx, "UPDATE md_blogs SET blog_content = ?, modify_time = ?, modify_at = ?, version = version + 1 WHERE blog_id = ? AND member_id = ? AND COALESCE(editor_type,'markdown') = ? AND password = ?"+authority,
			encoded, now.Format("2006-01-02 15:04:05"), now.Unix(), targetID, owner, format, passwordHash, shareID, identify, kind, targetID, owner, token)
	case "document":
		result, err = tx.ExecContext(ctx, "UPDATE md_documents SET markdown = ?, modify_time = ?, modify_at = ? WHERE document_id = ? AND member_id = ? AND COALESCE(doc_type,'markdown') = ?"+authority,
			encoded, now, now.Unix(), targetID, owner, format, shareID, identify, kind, targetID, owner, token)
	}
	if err != nil {
		return nil, err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return nil, err
	}
	if count != 1 {
		return nil, ErrSharedEditTarget
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &SharedContentReceipt{ModifyTime: now, SourceSHA256: sharedEditSourceHash(actualSource)}, nil
}
func sharedEditLimit(format string) (int, bool) {
	switch format {
	case "", "markdown":
		return 500 * 1024, true
	case "html", "spreadsheet", "drawing", "mindmap", RichDocumentType:
		return 5 * 1024 * 1024, true
	case PresentationType:
		return 20 * 1024 * 1024, true
	default:
		return 0, false
	}
}
func sharedEditSourceHash(source string) string {
	sum := sha256.Sum256([]byte(source))
	return hex.EncodeToString(sum[:])
}

// Bound decompression when checking current source, even for damaged legacy DB.
func sharedEditFullSource(format, stored string, protected bool, password string, maxBytes int) (string, error) {
	content := stored
	var err error
	if protected && IsEncrypted(content) {
		content, err = DecryptContent(password, content)
		if err != nil {
			return "", err
		}
	}
	if (format == "html" || format == RichDocumentType) && IsCompressedContent(content) {
		data, err := CompressedContentGzipBytes(content)
		if err != nil {
			return "", err
		}
		reader, err := gzip.NewReader(bytes.NewReader(data))
		if err != nil {
			return "", err
		}
		defer reader.Close()
		plain, err := io.ReadAll(io.LimitReader(reader, int64(maxBytes)+1))
		if err != nil {
			return "", err
		}
		content = string(plain)
	}
	if len(content) > maxBytes || !utf8.ValidString(content) {
		return "", ErrSharedEditInput
	}
	return content, nil
}
