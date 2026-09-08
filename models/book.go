package models

import (
	"fmt"
	"log"
	"time"
)

type Book struct {
	BookID              int64      `json:"book_id"`
	BookName            string     `json:"book_name"`
	ItemID              int        `json:"item_id"`
	Identify            string     `json:"identify"`
	OrderIndex          int        `json:"order_index"`
	Description         string     `json:"description"`
	Label               string     `json:"label"`
	DocCount            int        `json:"doc_count"`
	MemberID            int64      `json:"member_id"`
	CreateTime          time.Time  `json:"create_time"`
	ModifyTime          *time.Time `json:"modify_time"`
	IsUseFirstDocument  int        `json:"is_use_first_document"`
}

func ListBooksPaged(memberID int64, page, pageSize int, keyword string) ([]Book, int64, error) {
	where := "WHERE member_id = ?"
	args := []interface{}{memberID}
	if keyword != "" {
		where += " AND (book_name LIKE ? OR label LIKE ?)"
		kw := "%" + keyword + "%"
		args = append(args, kw, kw)
	}

	var total int64
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_books "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	query := "SELECT book_id, book_name, identify, order_index, description, label, doc_count, member_id, create_time, modify_time FROM md_books " + where + " ORDER BY modify_time DESC LIMIT ? OFFSET ?"
	args = append(args, pageSize, offset)

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var books []Book
	for rows.Next() {
		var b Book
		if err := rows.Scan(&b.BookID, &b.BookName, &b.Identify, &b.OrderIndex, &b.Description, &b.Label, &b.DocCount, &b.MemberID, &b.CreateTime, &b.ModifyTime); err != nil {
			return nil, 0, err
		}
		books = append(books, b)
	}
	return books, total, nil
}

func GetBookByID(id int64) (*Book, error) {
	b := &Book{}
	err := DB.QueryRow(
		"SELECT book_id, book_name, item_id, identify, order_index, description, label, doc_count, member_id, create_time, modify_time, is_use_first_document FROM md_books WHERE book_id = ?",
		id,
	).Scan(&b.BookID, &b.BookName, &b.ItemID, &b.Identify, &b.OrderIndex, &b.Description, &b.Label, &b.DocCount, &b.MemberID, &b.CreateTime, &b.ModifyTime, &b.IsUseFirstDocument)
	if err != nil {
		return nil, err
	}
	return b, nil
}

func GetBookByIdentify(identify string) (*Book, error) {
	b := &Book{}
	err := DB.QueryRow(
		"SELECT book_id, book_name, item_id, identify, order_index, description, label, doc_count, member_id, create_time, modify_time, is_use_first_document FROM md_books WHERE identify = ?",
		identify,
	).Scan(&b.BookID, &b.BookName, &b.ItemID, &b.Identify, &b.OrderIndex, &b.Description, &b.Label, &b.DocCount, &b.MemberID, &b.CreateTime, &b.ModifyTime, &b.IsUseFirstDocument)
	if err != nil {
		return nil, err
	}
	return b, nil
}

// BookNameExists 检查同一用户下是否已存在同名书籍（excludeID 用于更新时排除自身）
func BookNameExists(name string, memberID int64, excludeID int64) (bool, error) {
	var count int
	if excludeID > 0 {
		err := DB.QueryRow("SELECT COUNT(*) FROM md_books WHERE book_name = ? AND member_id = ? AND book_id != ?", name, memberID, excludeID).Scan(&count)
		return count > 0, err
	}
	err := DB.QueryRow("SELECT COUNT(*) FROM md_books WHERE book_name = ? AND member_id = ?", name, memberID).Scan(&count)
	return count > 0, err
}

func (b *Book) Insert() error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	result, err := tx.Exec(
		"INSERT INTO md_books (book_name, identify, description, label, member_id, create_time, modify_time) VALUES (?, ?, ?, ?, ?, ?, ?)",
		b.BookName, b.Identify, b.Description, b.Label, b.MemberID, b.CreateTime, time.Now(),
	)
	if err != nil {
		return err
	}
	b.BookID, _ = result.LastInsertId()
	if b.BookID == 0 {
		log.Printf("Book.Insert: LastInsertId returned 0")
	}

	// Create first document
	docIdentify := fmt.Sprintf("doc-%d", b.BookID)
	now := time.Now()
	if _, err := tx.Exec(
		"INSERT INTO md_documents (document_name, identify, book_id, parent_id, order_sort, markdown, doc_type, member_id, create_time, modify_time, modify_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		b.BookName, docIdentify, b.BookID, 0, 0, "", "markdown", b.MemberID, now, now, 0,
	); err != nil {
		return err
	}

	// Update doc count
	if _, err := tx.Exec("UPDATE md_books SET doc_count = 1 WHERE book_id = ?", b.BookID); err != nil {
		return err
	}

	return tx.Commit()
}

func (b *Book) Update() error {
	_, err := DB.Exec(
		"UPDATE md_books SET book_name = ?, description = ?, label = ?, modify_time = ? WHERE book_id = ?",
		b.BookName, b.Description, b.Label, time.Now(), b.BookID,
	)
	return err
}

func DeleteBook(id int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Check if book exists
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_books WHERE book_id = ?", id).Scan(&count); err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("书籍不存在")
	}

	// 快照到回收站
	snap, name, snapErr := SnapshotBook(tx, id)
	if snapErr != nil {
		log.Printf("DeleteBook: 快照失败: %v", snapErr)
	} else {
		// 获取书籍的 member_id
		var memberID int64
		if err := tx.QueryRow("SELECT member_id FROM md_books WHERE book_id = ?", id).Scan(&memberID); err == nil {
			if err := CreateTrash(tx, "book", name, snap, memberID); err != nil {
				log.Printf("DeleteBook: 写入回收站失败: %v", err)
			}
		}
	}

	// Delete share records for documents under this book
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'document' AND target_id IN (SELECT document_id FROM md_documents WHERE book_id = ?)", id); err != nil {
		return err
	}
	// Delete all documents
	if _, err := tx.Exec("DELETE FROM md_documents WHERE book_id = ?", id); err != nil {
		return err
	}
	// Delete share records for this book
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'book' AND target_id = ?", id); err != nil {
		return err
	}
	// Delete label relations
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'book'", id); err != nil {
		return err
	}
	// Delete book
	if _, err := tx.Exec("DELETE FROM md_books WHERE book_id = ?", id); err != nil {
		return err
	}

	return tx.Commit()
}