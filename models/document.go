package models

import (
	"database/sql"
	"fmt"
	"log"
	"time"
)

type Document struct {
	DocumentID   int64      `json:"document_id"`
	DocumentName string     `json:"document_name"`
	Identify     string     `json:"identify"`
	BookID       int64      `json:"book_id"`
	ParentID     int64      `json:"parent_id"`
	OrderSort    int        `json:"order_sort"`
	Markdown     string     `json:"markdown"`
	DocType      string     `json:"doc_type"`
	MemberID     int64      `json:"member_id"`
	CreateTime   time.Time  `json:"create_time"`
	ModifyTime   *time.Time `json:"modify_time"`
	ModifyAt     int64      `json:"modify_at"`
	IsOpen       int        `json:"is_open"`
	ViewCount    int        `json:"view_count"`
}

type DocTreeNode struct {
	DocumentID   int64          `json:"document_id"`
	DocumentName string         `json:"document_name"`
	Identify     string         `json:"identify"`
	ParentID     int64          `json:"parent_id"`
	OrderSort    int            `json:"order_sort"`
	DocType      string         `json:"doc_type"`
	Children     []*DocTreeNode `json:"children"`
}

func GetDocTree(bookID int64) ([]*DocTreeNode, error) {
	rows, err := DB.Query(
		"SELECT document_id, document_name, identify, parent_id, order_sort, COALESCE(doc_type,'markdown') FROM md_documents WHERE book_id = ? ORDER BY order_sort, document_id",
		bookID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	nodeMap := make(map[int64]*DocTreeNode)
	var allNodes []*DocTreeNode
	for rows.Next() {
		var n DocTreeNode
		if err := rows.Scan(&n.DocumentID, &n.DocumentName, &n.Identify, &n.ParentID, &n.OrderSort, &n.DocType); err != nil {
			return nil, err
		}
		nodeMap[n.DocumentID] = &n
		allNodes = append(allNodes, &n)
	}

	var roots []*DocTreeNode
	for _, n := range allNodes {
		if n.ParentID == 0 {
			roots = append(roots, n)
		} else if parent, ok := nodeMap[n.ParentID]; ok {
			parent.Children = append(parent.Children, n)
		}
	}
	return roots, nil
}

func GetDocumentByID(id int64) (*Document, error) {
	d := &Document{}
	err := DB.QueryRow(
		"SELECT document_id, document_name, identify, book_id, parent_id, order_sort, markdown, COALESCE(doc_type,'markdown'), member_id, create_time, modify_time, modify_at, is_open, view_count FROM md_documents WHERE document_id = ?",
		id,
	).Scan(&d.DocumentID, &d.DocumentName, &d.Identify, &d.BookID, &d.ParentID, &d.OrderSort, &d.Markdown, &d.DocType, &d.MemberID, &d.CreateTime, &d.ModifyTime, &d.ModifyAt, &d.IsOpen, &d.ViewCount)
	if err != nil {
		return nil, err
	}
	return d, nil
}

func GetDocumentByIdentify(identify string) (*Document, error) {
	d := &Document{}
	err := DB.QueryRow(
		"SELECT document_id, document_name, identify, book_id, parent_id, order_sort, markdown, COALESCE(doc_type,'markdown'), member_id, create_time, modify_time, modify_at, is_open, view_count FROM md_documents WHERE identify = ?",
		identify,
	).Scan(&d.DocumentID, &d.DocumentName, &d.Identify, &d.BookID, &d.ParentID, &d.OrderSort, &d.Markdown, &d.DocType, &d.MemberID, &d.CreateTime, &d.ModifyTime, &d.ModifyAt, &d.IsOpen, &d.ViewCount)
	if err != nil {
		return nil, err
	}
	return d, nil
}

func (d *Document) Insert() error {
	if d.Identify == "" {
		d.Identify = fmt.Sprintf("doc-%d", time.Now().UnixNano())
	}
	if d.DocType == "" {
		d.DocType = "markdown"
	}
	if d.DocType == "spreadsheet" && d.Markdown == "" {
		d.Markdown = DefaultSpreadsheet
	}
	if d.DocType == PresentationType && d.Markdown == "" {
		d.Markdown = DefaultPresentation(d.DocumentName)
	}
	if d.DocType == "drawing" && d.Markdown == "" {
		d.Markdown = `{"elements":[], "appState":{}}`
	}
	if d.DocType == "mindmap" && d.Markdown == "" {
		d.Markdown = `{"nodeData":{"id":"root","topic":"新脑图","root":true,"children":[]},"linkData":{}}`
	}
	if d.DocType == RichDocumentType && d.Markdown == "" {
		d.Markdown = DefaultRichDocument()
	}
	if d.DocType == "html" || d.DocType == RichDocumentType {
		encoded, err := EncodeContentForType(d.DocType, d.Markdown)
		if err != nil {
			return err
		}
		d.Markdown = encoded
	}
	now := time.Now()
	d.CreateTime = now
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	result, err := tx.Exec(
		"INSERT INTO md_documents (document_name, identify, book_id, parent_id, order_sort, markdown, doc_type, member_id, create_time, modify_time, modify_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		d.DocumentName, d.Identify, d.BookID, d.ParentID, d.OrderSort, d.Markdown, d.DocType, d.MemberID, now, now, d.ModifyAt,
	)
	if err != nil {
		return err
	}
	documentID, err := result.LastInsertId()
	if err != nil {
		return err
	}
	if documentID == 0 {
		return fmt.Errorf("Document.Insert: LastInsertId returned 0")
	}

	updateResult, err := tx.Exec("UPDATE md_books SET doc_count = doc_count + 1, modify_time = ? WHERE book_id = ?", now, d.BookID)
	if err != nil {
		return err
	}
	affected, err := updateResult.RowsAffected()
	if err != nil {
		return err
	}
	if affected != 1 {
		return fmt.Errorf("Document.Insert: book %d does not exist", d.BookID)
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	d.DocumentID = documentID
	return nil
}

func UpdateDocumentContent(id int64, markdown string, modifyAt int64) error {
	var docType string
	if err := DB.QueryRow("SELECT COALESCE(doc_type,'markdown') FROM md_documents WHERE document_id = ?", id).Scan(&docType); err != nil {
		return err
	}
	encoded, err := EncodeContentForType(docType, markdown)
	if err != nil {
		return err
	}
	now := time.Now()
	_, err = DB.Exec(
		"UPDATE md_documents SET markdown = ?, modify_time = ?, modify_at = ? WHERE document_id = ?",
		encoded, now, modifyAt, id,
	)
	return err
}

func UpdateDocumentName(id int64, name string) error {
	_, err := DB.Exec("UPDATE md_documents SET document_name = ?, modify_time = ? WHERE document_id = ?", name, time.Now(), id)
	return err
}

func DeleteDocument(id int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Check if document exists
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_documents WHERE document_id = ?", id).Scan(&count); err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("文档不存在")
	}

	// Check no children
	var childCount int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_documents WHERE parent_id = ?", id).Scan(&childCount); err != nil {
		return err
	}
	if childCount > 0 {
		return fmt.Errorf("cannot delete document with children")
	}

	// Get book_id for doc count update
	var bookID int64
	if err := tx.QueryRow("SELECT book_id FROM md_documents WHERE document_id = ?", id).Scan(&bookID); err != nil {
		return err
	}

	// 快照到回收站
	snap, name, snapErr := SnapshotDocument(tx, id)
	if snapErr != nil {
		log.Printf("DeleteDocument: 快照失败: %v", snapErr)
	} else {
		var memberID int64
		if err := tx.QueryRow("SELECT member_id FROM md_documents WHERE document_id = ?", id).Scan(&memberID); err == nil {
			if err := CreateTrash(tx, "document", name, snap, memberID); err != nil {
				log.Printf("DeleteDocument: 写入回收站失败: %v", err)
			}
		}
	}

	// Delete associated share records
	if _, err := tx.Exec("DELETE FROM md_shares WHERE share_type = 'document' AND target_id = ?", id); err != nil {
		return err
	}
	// Delete associated label relations
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = 'document'", id); err != nil {
		return err
	}

	if _, err := tx.Exec("DELETE FROM md_documents WHERE document_id = ?", id); err != nil {
		return err
	}

	// Update book doc count
	if _, err := tx.Exec("UPDATE md_books SET doc_count = doc_count - 1 WHERE book_id = ?", bookID); err != nil {
		return err
	}

	return tx.Commit()
}

func SortDocument(id int64, orderSort int) error {
	_, err := DB.Exec("UPDATE md_documents SET order_sort = ? WHERE document_id = ?", orderSort, id)
	return err
}

func MoveDocument(id int64, parentID int64, orderSort int) error {
	doc, err := GetDocumentByID(id)
	if err != nil {
		return err
	}
	oldParentID := doc.ParentID
	bookID := doc.BookID

	// Prevent moving a node into its own descendant (circular reference)
	if parentID > 0 && isDescendant(parentID, id, bookID) {
		return fmt.Errorf("不能将文档移动到自身子文档下")
	}

	now := time.Now()
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec("UPDATE md_documents SET parent_id = ?, order_sort = ?, modify_time = ? WHERE document_id = ?", parentID, orderSort, now, id)
	if err != nil {
		return err
	}

	reorderSiblingsTx(tx, oldParentID, bookID)
	if oldParentID != parentID {
		reorderSiblingsTx(tx, parentID, bookID)
	}
	return tx.Commit()
}

// isDescendant checks if targetID is a descendant of ancestorID
func isDescendant(targetID int64, ancestorID int64, bookID int64) bool {
	rows, err := DB.Query(
		"SELECT document_id FROM md_documents WHERE book_id = ? AND parent_id = ?",
		bookID, ancestorID,
	)
	if err != nil {
		return false
	}
	defer rows.Close()
	for rows.Next() {
		var childID int64
		if err := rows.Scan(&childID); err != nil {
			continue
		}
		if childID == targetID {
			return true
		}
		if isDescendant(targetID, childID, bookID) {
			return true
		}
	}
	return false
}

// ReorderDocument moves a document up, down, indent (make child of previous sibling), or outdent (make sibling of parent).
func ReorderDocument(id int64, direction string) error {
	doc, err := GetDocumentByID(id)
	if err != nil {
		return err
	}

	switch direction {
	case "up":
		return reorderUp(id, doc.ParentID, doc.BookID)
	case "down":
		return reorderDown(id, doc.ParentID, doc.BookID)
	case "indent":
		return indentDoc(id, doc.ParentID, doc.BookID)
	case "outdent":
		return outdentDoc(id, doc.ParentID, doc.BookID)
	default:
		return fmt.Errorf("无效的排序方向: %s", direction)
	}
}

func getSiblingIDs(parentID int64, bookID int64) ([]int64, error) {
	rows, err := DB.Query(
		"SELECT document_id FROM md_documents WHERE parent_id = ? AND book_id = ? ORDER BY order_sort, document_id",
		parentID, bookID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int64
	for rows.Next() {
		var dID int64
		if err := rows.Scan(&dID); err != nil {
			return nil, err
		}
		ids = append(ids, dID)
	}
	return ids, nil
}

func reorderSiblingsTx(tx *sql.Tx, parentID int64, bookID int64) {
	ids, err := getSiblingIDs(parentID, bookID)
	if err != nil || len(ids) == 0 {
		return
	}
	for i, dID := range ids {
		if tx != nil {
			tx.Exec("UPDATE md_documents SET order_sort = ? WHERE document_id = ?", i*10, dID)
		} else {
			DB.Exec("UPDATE md_documents SET order_sort = ? WHERE document_id = ?", i*10, dID)
		}
	}
}

func reorderUp(id int64, parentID int64, bookID int64) error {
	ids, err := getSiblingIDs(parentID, bookID)
	if err != nil {
		return err
	}

	pos := -1
	for i, dID := range ids {
		if dID == id {
			pos = i
			break
		}
	}
	if pos < 0 {
		return fmt.Errorf("文档不在同级列表中")
	}
	if pos == 0 {
		return fmt.Errorf("已经是第一个")
	}

	ids[pos], ids[pos-1] = ids[pos-1], ids[pos]

	now := time.Now()
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for i, dID := range ids {
		if dID == id {
			tx.Exec("UPDATE md_documents SET order_sort = ?, modify_time = ? WHERE document_id = ?", i*10, now, dID)
		} else {
			tx.Exec("UPDATE md_documents SET order_sort = ? WHERE document_id = ?", i*10, dID)
		}
	}
	return tx.Commit()
}

func reorderDown(id int64, parentID int64, bookID int64) error {
	ids, err := getSiblingIDs(parentID, bookID)
	if err != nil {
		return err
	}

	pos := -1
	for i, dID := range ids {
		if dID == id {
			pos = i
			break
		}
	}
	if pos < 0 {
		return fmt.Errorf("文档不在同级列表中")
	}
	if pos == len(ids)-1 {
		return fmt.Errorf("已经是最后一个")
	}

	ids[pos], ids[pos+1] = ids[pos+1], ids[pos]

	now := time.Now()
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for i, dID := range ids {
		if dID == id {
			tx.Exec("UPDATE md_documents SET order_sort = ?, modify_time = ? WHERE document_id = ?", i*10, now, dID)
		} else {
			tx.Exec("UPDATE md_documents SET order_sort = ? WHERE document_id = ?", i*10, dID)
		}
	}
	return tx.Commit()
}

func indentDoc(id int64, parentID int64, bookID int64) error {
	ids, err := getSiblingIDs(parentID, bookID)
	if err != nil {
		return err
	}

	pos := -1
	for i, dID := range ids {
		if dID == id {
			pos = i
			break
		}
	}
	if pos < 0 || pos == 0 {
		return fmt.Errorf("无法降级，没有上一个同级文档")
	}

	newParentID := ids[pos-1]
	now := time.Now()

	var maxSort sql.NullInt64
	DB.QueryRow("SELECT MAX(order_sort) FROM md_documents WHERE parent_id = ?", newParentID).Scan(&maxSort)
	newSort := 0
	if maxSort.Valid {
		newSort = int(maxSort.Int64) + 10
	}

	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec("UPDATE md_documents SET parent_id = ?, order_sort = ?, modify_time = ? WHERE document_id = ?", newParentID, newSort, now, id)
	if err != nil {
		return err
	}

	reorderSiblingsTx(tx, parentID, bookID)
	return tx.Commit()
}

func outdentDoc(id int64, parentID int64, bookID int64) error {
	if parentID == 0 {
		return fmt.Errorf("已经是顶级文档")
	}

	parent, err := GetDocumentByID(parentID)
	if err != nil {
		return fmt.Errorf("父文档不存在")
	}

	newParentID := parent.ParentID
	now := time.Now()

	parentSiblings, err := getSiblingIDs(newParentID, bookID)
	if err != nil {
		return err
	}

	parentPos := -1
	for i, dID := range parentSiblings {
		if dID == parentID {
			parentPos = i
			break
		}
	}
	if parentPos < 0 {
		return fmt.Errorf("无法找到父文档的排序位置")
	}

	newSort := (parentPos + 1) * 10

	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec("UPDATE md_documents SET parent_id = ?, order_sort = ?, modify_time = ? WHERE document_id = ?", newParentID, newSort, now, id)
	if err != nil {
		return err
	}

	reorderSiblingsTx(tx, parentID, bookID)
	reorderSiblingsTx(tx, newParentID, bookID)
	return tx.Commit()
}

// GetDocumentSiblings returns prev/next document IDs for navigation
func GetDocumentNavigation(docID int64, bookID int64) (prevID, nextID int64) {
	// Get all documents in flat order
	rows, err := DB.Query(
		"SELECT document_id FROM md_documents WHERE book_id = ? ORDER BY order_sort, document_id",
		bookID,
	)
	if err != nil {
		return 0, 0
	}
	defer rows.Close()

	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return 0, 0
		}
		ids = append(ids, id)
	}

	for i, id := range ids {
		if id == docID {
			if i > 0 {
				prevID = ids[i-1]
			}
			if i < len(ids)-1 {
				nextID = ids[i+1]
			}
			break
		}
	}
	return
}
