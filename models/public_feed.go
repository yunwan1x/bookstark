package models

// Only labels attached to publicly listed resources are exposed to visitors.
func PublicFeedLabels(kind string) ([]string, error) {
	if kind == "bookmark" {
		items, err := ListPublicBookmarkLabelsWithCount()
		labels := []string{}
		for _, item := range items {
			labels = append(labels, item.Name)
		}
		return labels, err
	}
	rows, err := DB.Query(`SELECT DISTINCT l.label_name FROM md_label l JOIN md_label_relation r ON r.label_id=l.label_id WHERE
 (? IN ('article','note') AND r.relation_type='blog' AND EXISTS (SELECT 1 FROM md_blogs b WHERE b.blog_id=r.resource_id AND b.visibility=1 AND COALESCE(b.blog_type,'article')=? AND COALESCE(b.password,'')='')) OR
 (?='book' AND r.relation_type='book' AND EXISTS (SELECT 1 FROM md_shares s JOIN md_books b ON b.book_id=s.target_id WHERE s.share_type='book' AND s.target_id=r.resource_id)) ORDER BY l.label_name LIMIT 100`, kind, kind, kind)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	labels := []string{}
	for rows.Next() {
		var label string
		if err := rows.Scan(&label); err != nil {
			return nil, err
		}
		labels = append(labels, label)
	}
	return labels, rows.Err()
}
