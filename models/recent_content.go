package models

import (
	"net/url"
	"strconv"
	"time"
)

// RecentContent stores references, never content, passwords, edit tokens or
// caller-supplied URLs. Titles and authorization are resolved on every read.
type RecentContent struct {
	Type      string `json:"type"`
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Context   string `json:"context"`
	URL       string `json:"url"`
	VisitedAt int64  `json:"visited_at"`
}

// RecordRecentContent is called only after the corresponding read handler has
// authorized the resource. One record per account/content, bounded to 100.
func RecordRecentContent(memberID int64, kind string, targetID int64, shareIdentify string) error {
	if memberID <= 0 || targetID <= 0 || (kind != "blog" && kind != "book" && kind != "document") {
		return nil
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.Exec(`INSERT INTO md_recent_content(member_id,resource_type,target_id,share_identify,visited_at)
	 VALUES(?,?,?,?,?) ON CONFLICT(member_id,resource_type,target_id) DO UPDATE SET
	 share_identify=excluded.share_identify, visited_at=excluded.visited_at`, memberID, kind, targetID, shareIdentify, time.Now().UnixMilli())
	if err != nil {
		return err
	}
	_, err = tx.Exec(`DELETE FROM md_recent_content WHERE member_id=? AND rowid NOT IN
	 (SELECT rowid FROM md_recent_content WHERE member_id=? ORDER BY visited_at DESC,rowid DESC LIMIT 100)`, memberID, memberID)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func ClearRecentContent(memberID int64) error {
	_, err := DB.Exec("DELETE FROM md_recent_content WHERE member_id=?", memberID)
	return err
}

func ListRecentContent(memberID int64, admin bool) ([]RecentContent, error) {
	// Private reads follow the editor's owner/admin policy. Public reads must
	// still have a live public route; unpublishing/deleting immediately hides them.
	rows, err := DB.Query(`SELECT kind,id,title,context,target,share_identify,visited_at FROM (
	 SELECT CASE WHEN b.blog_type='note' THEN 'note' ELSE 'article' END kind,b.blog_id id,b.blog_title title,
	 '' context,b.blog_identify target,h.share_identify,h.visited_at
	 FROM md_recent_content h JOIN md_blogs b ON h.resource_type='blog' AND h.target_id=b.blog_id
	 WHERE h.member_id=? AND ((h.share_identify='' AND (b.member_id=? OR ?)) OR
	 (h.share_identify!='' AND b.visibility=1 AND (b.blog_identify=h.share_identify OR EXISTS
	 (SELECT 1 FROM md_shares s WHERE s.share_identify=h.share_identify AND s.share_type='blog' AND s.target_id=b.blog_id))))
	 UNION ALL
	 SELECT 'book',b.book_id,b.book_name,'',b.identify,h.share_identify,h.visited_at
	 FROM md_recent_content h JOIN md_books b ON h.resource_type='book' AND h.target_id=b.book_id
	 WHERE h.member_id=? AND ((h.share_identify='' AND (b.member_id=? OR ?)) OR
	 (h.share_identify!='' AND EXISTS(SELECT 1 FROM md_shares s WHERE s.share_identify=h.share_identify AND s.share_type='book' AND s.target_id=b.book_id)))
	 UNION ALL
	 SELECT 'document',d.document_id,d.document_name,b.book_name,b.identify,h.share_identify,h.visited_at
	 FROM md_recent_content h JOIN md_documents d ON h.resource_type='document' AND h.target_id=d.document_id
	 JOIN md_books b ON b.book_id=d.book_id
	 WHERE h.member_id=? AND ((h.share_identify='' AND (d.member_id=? OR ?) AND (b.member_id=? OR ?)) OR
	 (h.share_identify!='' AND EXISTS(SELECT 1 FROM md_shares s WHERE s.share_identify=h.share_identify AND s.share_type='document' AND s.target_id=d.document_id)))
	 ) ORDER BY visited_at DESC,kind,id DESC LIMIT 3`, memberID, memberID, admin, memberID, memberID, admin, memberID, memberID, admin, memberID, admin)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []RecentContent{}
	for rows.Next() {
		var item RecentContent
		var target, share string
		if err := rows.Scan(&item.Type, &item.ID, &item.Title, &item.Context, &target, &share, &item.VisitedAt); err != nil {
			return nil, err
		}
		if share != "" {
			item.URL = "/shares/" + url.PathEscape(share)
		} else {
			switch item.Type {
			case "note", "article":
				item.URL = "/blogs/" + url.PathEscape(target) + "/edit"
			case "book":
				item.URL = "/books/" + url.PathEscape(target) + "/edit"
			case "document":
				item.URL = "/books/" + url.PathEscape(target) + "/edit?doc=" + strconv.FormatInt(item.ID, 10)
			}
		}
		items = append(items, item)
	}
	return items, rows.Err()
}
