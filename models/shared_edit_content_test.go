// Draft only. Not compiled or run during the shared Native freeze.
package models

import (
	"errors"
	"reflect"
	"strings"
	"testing"
)

func sharedEditFixture(t *testing.T, format, password string) (*Blog, *Share, string) {
	t.Helper()
	content := "\ufeffbefore\r\n"
	if format == "html" {
		content = "\ufeff<p>before</p>\r\n"
	}
	blog := &Blog{BlogTitle: "Owner title", BlogIdentify: "shared-integrity-" + format,
		BlogType: "article", EditorType: format, MemberID: 1, Visibility: 1,
		BlogContent: content, Password: password, BlogDesc: "Owner description",
		IsPinned: 1, PinOrder: 8, LocationName: "Owner place"}
	if err := blog.Insert(); err != nil {
		t.Fatal("fixture blog insert failed")
	}
	token := strings.Repeat("fixture", 8)
	share, err := CreateShare("blog", blog.BlogID, 1, token)
	if err != nil {
		t.Fatal("fixture share insert failed")
	}
	share, err = GetShareByTypeAndTarget("blog", blog.BlogID)
	if err != nil || share.ShareID <= 0 {
		t.Fatal("fixture share readback failed")
	}
	actual, err := GetBlogByID(blog.BlogID)
	if err != nil {
		t.Fatal(err)
	}
	return actual, share, token
}
func sharedSetupUpdate(t *testing.T, query string, args ...any) {
	t.Helper()
	result, err := DB.Exec(query, args...)
	if err != nil {
		t.Fatal(err)
	}
	count, err := result.RowsAffected()
	if err != nil || count != 1 {
		t.Fatal("setup UPDATE did not affect exactly one row")
	}
}
func sharedEditMetadata(t *testing.T, id int64) []any {
	t.Helper()
	rows, err := DB.Query("SELECT blog_title,blog_desc,password,blog_type,visibility,is_pinned,pin_order,location_name,latitude,longitude,location_accuracy,member_id,editor_type FROM md_blogs WHERE blog_id = ?", id)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	if !rows.Next() {
		t.Fatal("metadata missing")
	}
	columns, err := rows.Columns()
	if err != nil {
		t.Fatal(err)
	}
	values := make([]any, len(columns))
	ptrs := make([]any, len(columns))
	for i := range ptrs {
		ptrs[i] = &values[i]
	}
	if err := rows.Scan(ptrs...); err != nil {
		t.Fatal(err)
	}
	return values
}
func TestSharedContentPreservesAllOwnerMetadataAndLegacyProtocol(t *testing.T) {
	initAssetTestDB(t)
	blog, share, token := sharedEditFixture(t, "markdown", "")
	// Simulate owner metadata changed since an editor loaded an old snapshot.
	sharedSetupUpdate(t, "UPDATE md_blogs SET blog_title=?,blog_desc=?,visibility=0,is_pinned=0,pin_order=17,location_name=? WHERE blog_id=?",
		"New owner title", "New owner description", "New owner place", blog.BlogID)
	before := sharedEditMetadata(t, blog.BlogID)
	receipt, err := SaveSharedContent(share.ShareIdentify, token, "\ufeffsaved\r\n", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(before, sharedEditMetadata(t, blog.BlogID)) {
		t.Fatal("owner metadata overwritten")
	}
	actual, err := GetBlogByID(blog.BlogID)
	if err != nil {
		t.Fatal(err)
	}
	if actual.BlogContent != "\ufeffsaved\r\n" || actual.Version != blog.Version+1 {
		t.Fatal("content/version mismatch")
	}
	if receipt.SourceSHA256 != sharedEditSourceHash("\ufeffsaved\r\n") || receipt.ModifyTime.IsZero() {
		t.Fatal("receipt mismatch")
	}
}
func TestSharedContentExpectedPlainSourceHashConflictsWithoutMutation(t *testing.T) {
	initAssetTestDB(t)
	blog, share, token := sharedEditFixture(t, "markdown", "")
	expected := sharedEditSourceHash("wrong baseline")
	_, err := SaveSharedContent(share.ShareIdentify, token, "new", "", &expected)
	if !errors.Is(err, ErrSharedEditConflict) {
		t.Fatal("expected source conflict")
	}
	actual, _ := GetBlogByID(blog.BlogID)
	if actual.BlogContent != blog.BlogContent || actual.Version != blog.Version {
		t.Fatal("conflict mutated content")
	}
}
func TestSharedContentProtectedCompressedHTMLHashAndPasswordPreservation(t *testing.T) {
	initAssetTestDB(t)
	blog, share, token := sharedEditFixture(t, "html", "fixture-passphrase")
	before := sharedEditMetadata(t, blog.BlogID)
	expected := sharedEditSourceHash("\ufeff<p>before</p>\r\n")
	if _, err := SaveSharedContent(share.ShareIdentify, token, "<p>new</p>", "wrong", &expected); !errors.Is(err, ErrSharedEditPassword) {
		t.Fatal("wrong password not rejected")
	}
	receipt, err := SaveSharedContent(share.ShareIdentify, token, "\ufeff<p>new</p>\r\n", "fixture-passphrase", &expected)
	if err != nil {
		t.Fatal(err)
	}
	actual, _ := GetBlogByID(blog.BlogID)
	decoded, err := sharedEditFullSource("html", actual.BlogContent, true, "fixture-passphrase", 5*1024*1024)
	if err != nil || decoded != "\ufeff<p>new</p>\r\n" {
		t.Fatal("protected exact source mismatch")
	}
	if !reflect.DeepEqual(before, sharedEditMetadata(t, blog.BlogID)) {
		t.Fatal("password or metadata overwritten")
	}
	if receipt.SourceSHA256 != sharedEditSourceHash(decoded) {
		t.Fatal("receipt not plaintext digest")
	}
}
func TestSharedContentRevokedTokenAndChangedOwnerCannotWrite(t *testing.T) {
	initAssetTestDB(t)
	blog, share, token := sharedEditFixture(t, "markdown", "")
	if err := SetEditToken("blog", blog.BlogID, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := SaveSharedContent(share.ShareIdentify, token, "new", "", nil); !errors.Is(err, ErrSharedEditToken) {
		t.Fatal("revoked token accepted")
	}
	if err := SetEditToken("blog", blog.BlogID, token); err != nil {
		t.Fatal(err)
	}
	sharedSetupUpdate(t, "UPDATE md_shares SET member_id=999 WHERE share_id=?", share.ShareID)
	if _, err := SaveSharedContent(share.ShareIdentify, token, "new", "", nil); !errors.Is(err, ErrSharedEditTarget) {
		t.Fatal("changed owner accepted")
	}
	actual, _ := GetBlogByID(blog.BlogID)
	if actual.BlogContent != blog.BlogContent || actual.Version != blog.Version {
		t.Fatal("denied write mutated content")
	}
}
func TestSharedContentFailedUpdateRollsBackContentVersionAndOtherTriggerWrites(t *testing.T) {
	initAssetTestDB(t)
	blog, share, token := sharedEditFixture(t, "markdown", "")
	if _, err := DB.Exec("CREATE TRIGGER fail_shared_write AFTER UPDATE OF blog_content ON md_blogs BEGIN UPDATE md_shares SET edit_token='bad-fixture'; SELECT RAISE(ABORT,'fixture rollback'); END"); err != nil {
		t.Fatal(err)
	}
	if _, err := SaveSharedContent(share.ShareIdentify, token, "new", "", nil); err == nil {
		t.Fatal("expected transactional failure")
	}
	actual, _ := GetBlogByID(blog.BlogID)
	if actual.BlogContent != blog.BlogContent || actual.Version != blog.Version {
		t.Fatal("failed transaction changed blog")
	}
	actualToken, err := GetEditToken("blog", blog.BlogID)
	if err != nil || actualToken != token {
		t.Fatal("failed transaction changed token")
	}
}
func TestSharedContentDocumentDoesNotTouchNameParentOrderOrOwner(t *testing.T) {
	initAssetTestDB(t)
	book := &Book{BookName: "Shared doc book", Identify: "shared-doc-book", MemberID: 1}
	if err := book.Insert(); err != nil {
		t.Fatal(err)
	}
	var id int64
	if err := DB.QueryRow("SELECT document_id FROM md_documents WHERE book_id=?", book.BookID).Scan(&id); err != nil {
		t.Fatal(err)
	}
	token := strings.Repeat("document-fixture", 4)
	share, err := CreateShare("document", id, 1, token)
	if err != nil {
		t.Fatal(err)
	}
	old, err := GetDocumentByID(id)
	if err != nil {
		t.Fatal(err)
	}
	expected := sharedEditSourceHash(old.Markdown)
	if _, err := SaveSharedContent(share.ShareIdentify, token, "new doc", "", &expected); err != nil {
		t.Fatal(err)
	}
	actual, err := GetDocumentByID(id)
	if err != nil {
		t.Fatal(err)
	}
	if actual.Markdown != "new doc" || actual.DocumentName != old.DocumentName ||
		actual.ParentID != old.ParentID || actual.MemberID != old.MemberID || actual.BookID != old.BookID ||
		actual.OrderSort != old.OrderSort || actual.DocType != old.DocType {
		t.Fatal("document content-only update violated metadata")
	}
}
func TestSharedContentBadHashAndUnknownFormatAreRejected(t *testing.T) {
	initAssetTestDB(t)
	blog, share, token := sharedEditFixture(t, "markdown", "")
	invalid := "ABC"
	if _, err := SaveSharedContent(share.ShareIdentify, token, "new", "", &invalid); !errors.Is(err, ErrSharedEditInput) {
		t.Fatal("invalid hash accepted")
	}
	sharedSetupUpdate(t, "UPDATE md_blogs SET editor_type='unsupported' WHERE blog_id=?", blog.BlogID)
	if _, err := SaveSharedContent(share.ShareIdentify, token, "new", "", nil); !errors.Is(err, ErrSharedEditInput) {
		t.Fatal("unknown format accepted")
	}
}
