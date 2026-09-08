package models

import (
	"testing"
	"time"
)

func insertDocumentTestBook(t *testing.T, identify string) int64 {
	t.Helper()
	now := time.Now()
	result, err := DB.Exec(
		"INSERT INTO md_books (book_name, identify, member_id, create_time, modify_time) VALUES (?, ?, ?, ?, ?)",
		"Document test book", identify, 1, now, now,
	)
	if err != nil {
		t.Fatalf("insert test book: %v", err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		t.Fatalf("test book LastInsertId: %v", err)
	}
	return id
}

func TestDocumentInsertUpdatesBookCountAtomically(t *testing.T) {
	initAssetTestDB(t)
	bookID := insertDocumentTestBook(t, "document-insert-success")

	document := &Document{
		DocumentName: "Atomic document",
		Identify:     "atomic-document",
		BookID:       bookID,
		MemberID:     1,
		DocType:      "markdown",
	}
	if err := document.Insert(); err != nil {
		t.Fatalf("Document.Insert() error = %v", err)
	}
	if document.DocumentID == 0 {
		t.Fatal("Document.Insert() did not assign DocumentID")
	}

	var documentCount, bookDocCount int
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_documents WHERE document_id = ?", document.DocumentID).Scan(&documentCount); err != nil {
		t.Fatalf("count inserted document: %v", err)
	}
	if err := DB.QueryRow("SELECT doc_count FROM md_books WHERE book_id = ?", bookID).Scan(&bookDocCount); err != nil {
		t.Fatalf("read book doc_count: %v", err)
	}
	if documentCount != 1 || bookDocCount != 1 {
		t.Fatalf("document count = %d, book doc_count = %d; want 1, 1", documentCount, bookDocCount)
	}
}

func TestDocumentInsertRollsBackWhenBookCountUpdateFails(t *testing.T) {
	initAssetTestDB(t)
	bookID := insertDocumentTestBook(t, "document-insert-rollback")
	if _, err := DB.Exec(`
		CREATE TRIGGER fail_document_book_count
		BEFORE UPDATE OF doc_count ON md_books
		BEGIN
			SELECT RAISE(ABORT, 'forced doc_count failure');
		END
	`); err != nil {
		t.Fatalf("create failure trigger: %v", err)
	}

	document := &Document{
		DocumentName: "Rolled back document",
		Identify:     "rolled-back-document",
		BookID:       bookID,
		MemberID:     1,
		DocType:      "markdown",
	}
	if err := document.Insert(); err == nil {
		t.Fatal("Document.Insert() error = nil, want forced update failure")
	}
	if document.DocumentID != 0 {
		t.Fatalf("DocumentID = %d after rollback, want 0", document.DocumentID)
	}

	var documentCount, bookDocCount int
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_documents WHERE identify = ?", document.Identify).Scan(&documentCount); err != nil {
		t.Fatalf("count rolled-back document: %v", err)
	}
	if err := DB.QueryRow("SELECT doc_count FROM md_books WHERE book_id = ?", bookID).Scan(&bookDocCount); err != nil {
		t.Fatalf("read book doc_count after rollback: %v", err)
	}
	if documentCount != 0 || bookDocCount != 0 {
		t.Fatalf("document count = %d, book doc_count = %d after rollback; want 0, 0", documentCount, bookDocCount)
	}
}
