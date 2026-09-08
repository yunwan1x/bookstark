package models

import (
	"database/sql"
	"fmt"
	"log"
	"strconv"
	"strings"
)

type dbTx interface {
	Exec(query string, args ...interface{}) (sql.Result, error)
	QueryRow(query string, args ...interface{}) *sql.Row
}

type Label struct {
	LabelID   int64  `json:"label_id"`
	LabelName string `json:"label_name"`
}

type LabelWithCount struct {
	LabelID       int64  `json:"label_id"`
	LabelName     string `json:"label_name"`
	BookCount     int    `json:"book_count"`
	BlogCount     int    `json:"blog_count"`
	BookmarkCount int    `json:"bookmark_count"`
	RecentCount   int    `json:"recent_count,omitempty"`
}

type LabelRelation struct {
	ID           int64  `json:"id"`
	LabelID      int64  `json:"label_id"`
	ResourceID   int64  `json:"resource_id"`
	RelationType string `json:"relation_type"`
}

type TagRecommendationSettings struct {
	Strategy     string   `json:"strategy"`
	ManualLabels []string `json:"manual_labels"`
	PageSize     int      `json:"page_size"`
}

var tagRecommendationStrategies = map[string]bool{
	"recent":   true,
	"total":    true,
	"book":     true,
	"bookmark": true,
	"manual":   true,
}

func IsTagRecommendationStrategy(strategy string) bool {
	return tagRecommendationStrategies[strategy]
}

func GetTagRecommendationSettings() TagRecommendationSettings {
	strategy := strings.TrimSpace(GetSettingWithDefault("tag_recommend_strategy", "recent"))
	if !IsTagRecommendationStrategy(strategy) {
		strategy = "recent"
	}
	pageSize := 10
	if parsed, err := strconv.Atoi(GetSettingWithDefault("tag_recommend_page_size", "10")); err == nil && parsed >= 1 && parsed <= 50 {
		pageSize = parsed
	}
	manualLabels := splitLabelString(GetSetting("tag_recommend_manual_labels"))
	if manualLabels == nil {
		manualLabels = []string{}
	}
	return TagRecommendationSettings{
		Strategy:     strategy,
		ManualLabels: manualLabels,
		PageSize:     pageSize,
	}
}

func UpdateTagRecommendationSettings(settings TagRecommendationSettings) error {
	settings.Strategy = strings.TrimSpace(settings.Strategy)
	if !IsTagRecommendationStrategy(settings.Strategy) {
		return fmt.Errorf("不支持的推荐策略")
	}
	if settings.PageSize < 1 || settings.PageSize > 50 {
		return fmt.Errorf("推荐数量应在1-50之间")
	}

	manual := make([]string, 0, len(settings.ManualLabels))
	seen := map[string]bool{}
	for _, name := range settings.ManualLabels {
		name = strings.TrimSpace(name)
		if name == "" || seen[name] {
			continue
		}
		if len(name) > 100 {
			return fmt.Errorf("标签名称不能超过100个字符")
		}
		manual = append(manual, name)
		seen[name] = true
		if len(manual) >= 50 {
			break
		}
	}

	return BatchUpdateSettings(map[string]string{
		"tag_recommend_strategy":      settings.Strategy,
		"tag_recommend_manual_labels": strings.Join(manual, ","),
		"tag_recommend_page_size":     strconv.Itoa(settings.PageSize),
	})
}

// buildLabelSortClause builds the ORDER BY clause for label listing.
// sortBy: "name", "book", "blog", "bookmark", "total", "recent"
// sortOrder: "asc" or "desc"
func buildLabelSortClause(sortBy, sortOrder string) string {
	// Validate sortOrder
	if sortOrder != "asc" && sortOrder != "desc" {
		sortOrder = "asc"
	}

	var col string
	switch sortBy {
	case "book":
		col = "book_count"
	case "blog":
		col = "blog_count"
	case "bookmark":
		col = "bookmark_count"
	case "total":
		col = "(book_count + blog_count + bookmark_count)"
	case "recent":
		return "recent_count DESC, l.label_name ASC"
	case "name":
		col = "l.label_name"
	default:
		col = "l.label_id"
	}

	return col + " " + sortOrder
}

func ListLabelsWithCount() ([]LabelWithCount, error) {
	rows, err := DB.Query(`
		SELECT l.label_id, l.label_name,
			COALESCE(SUM(CASE WHEN r.relation_type = 'book' THEN 1 ELSE 0 END), 0) as book_count,
			COALESCE(SUM(CASE WHEN r.relation_type = 'blog' THEN 1 ELSE 0 END), 0) as blog_count,
			COALESCE(SUM(CASE WHEN r.relation_type = 'bookmark' THEN 1 ELSE 0 END), 0) as bookmark_count
		FROM md_label l
		LEFT JOIN md_label_relation r ON l.label_id = r.label_id
		GROUP BY l.label_id, l.label_name
		ORDER BY l.label_id
			LIMIT ` + strconv.Itoa(GetLabelListLimit()))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var labels []LabelWithCount
	for rows.Next() {
		var l LabelWithCount
		if err := rows.Scan(&l.LabelID, &l.LabelName, &l.BookCount, &l.BlogCount, &l.BookmarkCount); err != nil {
			return nil, err
		}
		labels = append(labels, l)
	}
	return labels, nil
}

func ListLabelsWithCountPaged(keyword, sortBy, sortOrder string, page, pageSize int) ([]LabelWithCount, int64, int, int, error) {
	where := ""
	args := []interface{}{}
	if keyword != "" {
		where = " WHERE l.label_name LIKE ?"
		args = append(args, "%"+keyword+"%")
	}

	var total int64
	countSQL := "SELECT COUNT(*) FROM md_label l" + where
	if err := DB.QueryRow(countSQL, args...).Scan(&total); err != nil {
		return nil, 0, 0, 0, err
	}

	// Count used/unused labels globally
	var usedCount, unusedCount int
	statsSQL := `SELECT
		COALESCE(SUM(CASE WHEN cnt > 0 THEN 1 ELSE 0 END), 0),
		COALESCE(SUM(CASE WHEN cnt = 0 THEN 1 ELSE 0 END), 0)
	FROM (SELECT l.label_id, COUNT(r.id) as cnt FROM md_label l LEFT JOIN md_label_relation r ON l.label_id = r.label_id` +
		strings.Replace(where, "l.label_name", "l.label_name", 1) +
		` GROUP BY l.label_id) sub`
	if err := DB.QueryRow(statsSQL, args...).Scan(&usedCount, &unusedCount); err != nil {
		return nil, 0, 0, 0, err
	}

	// Build ORDER BY clause
	orderBy := buildLabelSortClause(sortBy, sortOrder)

	offset := (page - 1) * pageSize

	// When sorting by "recent", include recent_count column
	var recentCol string
	if sortBy == "recent" {
		recentCol = `,
		COALESCE(SUM(CASE WHEN r.created_at > datetime('now', '-90 days') THEN 1 ELSE 0 END), 0) as recent_count`
	}

	query := `SELECT l.label_id, l.label_name,
		COALESCE(SUM(CASE WHEN r.relation_type = 'book' THEN 1 ELSE 0 END), 0) as book_count,
		COALESCE(SUM(CASE WHEN r.relation_type = 'blog' THEN 1 ELSE 0 END), 0) as blog_count,
		COALESCE(SUM(CASE WHEN r.relation_type = 'bookmark' THEN 1 ELSE 0 END), 0) as bookmark_count` +
		recentCol + `
	FROM md_label l
	LEFT JOIN md_label_relation r ON l.label_id = r.label_id` + where + `
	GROUP BY l.label_id, l.label_name
	ORDER BY ` + orderBy + `
	LIMIT ? OFFSET ?`
	args = append(args, pageSize, offset)

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, 0, 0, 0, err
	}
	defer rows.Close()

	var labels []LabelWithCount
	for rows.Next() {
		var l LabelWithCount
		if sortBy == "recent" {
			if err := rows.Scan(&l.LabelID, &l.LabelName, &l.BookCount, &l.BlogCount, &l.BookmarkCount, &l.RecentCount); err != nil {
				return nil, 0, 0, 0, err
			}
		} else {
			if err := rows.Scan(&l.LabelID, &l.LabelName, &l.BookCount, &l.BlogCount, &l.BookmarkCount); err != nil {
				return nil, 0, 0, 0, err
			}
		}
		labels = append(labels, l)
	}
	return labels, total, usedCount, unusedCount, nil
}

func ListRecommendedLabels(strategy string, manualLabels []string, limit int) ([]LabelWithCount, error) {
	if limit < 1 || limit > 50 {
		limit = 10
	}
	strategy = strings.TrimSpace(strategy)
	if strategy == "" {
		settings := GetTagRecommendationSettings()
		strategy = settings.Strategy
		manualLabels = settings.ManualLabels
		if limit == 10 && settings.PageSize > 0 {
			limit = settings.PageSize
		}
	}
	if !IsTagRecommendationStrategy(strategy) {
		strategy = "recent"
	}

	result := make([]LabelWithCount, 0, limit)
	seen := map[int64]bool{}
	appendUnique := func(items []LabelWithCount) {
		for _, item := range items {
			if seen[item.LabelID] {
				continue
			}
			result = append(result, item)
			seen[item.LabelID] = true
			if len(result) >= limit {
				return
			}
		}
	}

	if strategy == "manual" {
		items, err := labelsByNames(manualLabels)
		if err != nil {
			return nil, err
		}
		appendUnique(items)
		if len(result) >= limit {
			return result, nil
		}
	}

	sortBy := strategy
	fallbackLimit := limit
	if strategy == "manual" {
		sortBy = "recent"
		fallbackLimit = limit + len(result)
		if fallbackLimit > 50 {
			fallbackLimit = 50
		}
	}
	items, _, _, _, err := ListLabelsWithCountPaged("", sortBy, "desc", 1, fallbackLimit)
	if err != nil {
		return nil, err
	}
	appendUnique(items)
	return result, nil
}

func labelsByNames(names []string) ([]LabelWithCount, error) {
	var result []LabelWithCount
	seen := map[string]bool{}
	for _, name := range names {
		name = strings.TrimSpace(name)
		if name == "" || seen[name] {
			continue
		}
		seen[name] = true
		var l LabelWithCount
		err := DB.QueryRow(`
			SELECT l.label_id, l.label_name,
				COALESCE(SUM(CASE WHEN r.relation_type = 'book' THEN 1 ELSE 0 END), 0) as book_count,
				COALESCE(SUM(CASE WHEN r.relation_type = 'blog' THEN 1 ELSE 0 END), 0) as blog_count,
				COALESCE(SUM(CASE WHEN r.relation_type = 'bookmark' THEN 1 ELSE 0 END), 0) as bookmark_count
			FROM md_label l
			LEFT JOIN md_label_relation r ON l.label_id = r.label_id
			WHERE l.label_name = ?
			GROUP BY l.label_id, l.label_name
		`, name).Scan(&l.LabelID, &l.LabelName, &l.BookCount, &l.BlogCount, &l.BookmarkCount)
		if err != nil {
			continue
		}
		result = append(result, l)
	}
	return result, nil
}

func ListLabelsByMemberForType(memberID int64, relationType string, blogType string) ([]LabelWithCount, error) {
	query := `SELECT l.label_id, l.label_name,
		COALESCE(SUM(CASE WHEN r.relation_type = 'book' THEN 1 ELSE 0 END), 0) as book_count,
		COALESCE(SUM(CASE WHEN r.relation_type = 'blog' THEN 1 ELSE 0 END), 0) as blog_count,
		COALESCE(SUM(CASE WHEN r.relation_type = 'bookmark' THEN 1 ELSE 0 END), 0) as bookmark_count
	FROM md_label l
	INNER JOIN md_label_relation r ON l.label_id = r.label_id
	INNER JOIN md_blogs b ON r.resource_id = b.blog_id
	WHERE b.member_id = ? AND r.relation_type = ?`
	args := []interface{}{memberID, relationType}
	if blogType != "" {
		query += ` AND b.blog_type = ?`
		args = append(args, blogType)
	}
	query += ` GROUP BY l.label_id, l.label_name ORDER BY blog_count DESC, l.label_name ASC`

	rows, err := DB.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var labels []LabelWithCount
	for rows.Next() {
		var l LabelWithCount
		if err := rows.Scan(&l.LabelID, &l.LabelName, &l.BookCount, &l.BlogCount, &l.BookmarkCount); err != nil {
			return nil, err
		}
		labels = append(labels, l)
	}
	return labels, nil
}

func GetLabelByID(id int64) (*Label, error) {
	l := &Label{}
	err := DB.QueryRow("SELECT label_id, label_name FROM md_label WHERE label_id = ?", id).Scan(&l.LabelID, &l.LabelName)
	if err != nil {
		return nil, err
	}
	return l, nil
}

func (l *Label) Insert() error {
	result, err := DB.Exec("INSERT INTO md_label (label_name) VALUES (?)", l.LabelName)
	if err != nil {
		return err
	}
	l.LabelID, _ = result.LastInsertId()
	if l.LabelID == 0 {
		log.Printf("Label.Insert: LastInsertId returned 0")
	}
	return nil
}

func (l *Label) Update() error {
	_, err := DB.Exec("UPDATE md_label SET label_name = ? WHERE label_id = ?", l.LabelName, l.LabelID)
	return err
}

func DeleteLabel(id int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// 事务内检查标签是否存在
	var count int
	if err := tx.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_id = ?", id).Scan(&count); err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("标签不存在")
	}

	// 获取受影响的资源列表（用于后续同步 label 字段）
	type affectedResource struct {
		resourceID   int64
		relationType string
	}
	var affected []affectedResource
	rows, err := tx.Query("SELECT resource_id, relation_type FROM md_label_relation WHERE label_id = ?", id)
	if err != nil {
		return err
	}
	for rows.Next() {
		var r affectedResource
		if err := rows.Scan(&r.resourceID, &r.relationType); err != nil {
			rows.Close()
			return err
		}
		affected = append(affected, r)
	}
	rows.Close()

	// 先删关联，再删标签
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE label_id = ?", id); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM md_label WHERE label_id = ?", id); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}

	// 事务提交后同步受影响资源的 label 字段
	for _, r := range affected {
		if err := SyncResourceLabelField(r.resourceID, r.relationType); err != nil {
			log.Printf("DeleteLabel: SyncResourceLabelField failed for resource %d (%s): %v", r.resourceID, r.relationType, err)
		}
	}
	return nil
}

func DeleteUnusedLabels() (int64, error) {
	result, err := DB.Exec(`
		DELETE FROM md_label
		WHERE NOT EXISTS (
			SELECT 1 FROM md_label_relation r
			WHERE r.label_id = md_label.label_id
		)
	`)
	if err != nil {
		return 0, err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return 0, err
	}
	return count, nil
}

func BindLabels(labelID int64, resourceIDs []int64, relationType string) error {
	for _, rid := range resourceIDs {
		_, err := DB.Exec(
			"INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, ?, datetime('now'))",
			labelID, rid, relationType,
		)
		if err != nil {
			return err
		}
	}
	return nil
}

func UnbindLabels(labelID int64, resourceIDs []int64, relationType string) error {
	for _, rid := range resourceIDs {
		_, err := DB.Exec(
			"DELETE FROM md_label_relation WHERE label_id = ? AND resource_id = ? AND relation_type = ?",
			labelID, rid, relationType,
		)
		if err != nil {
			return err
		}
	}
	return nil
}

// LabelDetailItem holds a single associated content item for a label
type LabelDetailItem struct {
	ResourceID   int64  `json:"resource_id"`
	Title        string `json:"title"`
	RelationType string `json:"relation_type"`
	Identify     string `json:"identify"`
}

// LabelDetail holds full label detail with associated content
type LabelDetail struct {
	LabelID       int64             `json:"label_id"`
	LabelName     string            `json:"label_name"`
	BookCount     int               `json:"book_count"`
	BlogCount     int               `json:"blog_count"`
	BookmarkCount int               `json:"bookmark_count"`
	Items         []LabelDetailItem `json:"items"`
}

// GetLabelDetail returns a label with its associated content items
func GetLabelDetail(id int64) (*LabelDetail, error) {
	detail := &LabelDetail{LabelID: id}

	err := DB.QueryRow("SELECT label_name FROM md_label WHERE label_id = ?", id).Scan(&detail.LabelName)
	if err != nil {
		return nil, err
	}

	err = DB.QueryRow(`
		SELECT
			COALESCE(SUM(CASE WHEN relation_type = 'book' THEN 1 ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN relation_type = 'blog' THEN 1 ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN relation_type = 'bookmark' THEN 1 ELSE 0 END), 0)
		FROM md_label_relation WHERE label_id = ?
	`, id).Scan(&detail.BookCount, &detail.BlogCount, &detail.BookmarkCount)
	if err != nil {
		return nil, err
	}

	rows, err := DB.Query(`
		SELECT r.resource_id, r.relation_type,
			CASE r.relation_type
				WHEN 'book' THEN (SELECT b.book_name FROM md_books b WHERE b.book_id = r.resource_id)
				WHEN 'blog' THEN (SELECT bl.blog_title FROM md_blogs bl WHERE bl.blog_id = r.resource_id)
				WHEN 'bookmark' THEN (SELECT bm.title FROM md_bookmark bm WHERE bm.bookmark_id = r.resource_id)
				ELSE ''
			END as title,
			CASE r.relation_type
				WHEN 'book' THEN COALESCE((SELECT b.identify FROM md_books b WHERE b.book_id = r.resource_id), '')
				WHEN 'blog' THEN COALESCE((SELECT bl.blog_identify FROM md_blogs bl WHERE bl.blog_id = r.resource_id), '')
				ELSE ''
			END as identify
		FROM md_label_relation r
		WHERE r.label_id = ?
		ORDER BY r.relation_type, r.resource_id DESC
			LIMIT 500
	`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var item LabelDetailItem
		if err := rows.Scan(&item.ResourceID, &item.RelationType, &item.Title, &item.Identify); err != nil {
			return nil, err
		}
		detail.Items = append(detail.Items, item)
	}

	return detail, nil
}

// MergeLabels merges source labels into the target label
func MergeLabels(targetLabelID int64, sourceLabelIDs []int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// 收集所有受影响的资源（用于后续同步 label 字段）
	type affectedResource struct {
		resourceID   int64
		relationType string
	}
	var allAffected []affectedResource

	for _, sourceID := range sourceLabelIDs {
		if sourceID == targetLabelID {
			continue
		}

		rows, err := tx.Query("SELECT resource_id, relation_type FROM md_label_relation WHERE label_id = ?", sourceID)
		if err != nil {
			return err
		}

		type relation struct {
			resourceID   int64
			relationType string
		}
		var relations []relation
		for rows.Next() {
			var r relation
			if err := rows.Scan(&r.resourceID, &r.relationType); err != nil {
				rows.Close()
				return err
			}
			relations = append(relations, r)
			allAffected = append(allAffected, affectedResource{resourceID: r.resourceID, relationType: r.relationType})
		}
		rows.Close()

		for _, r := range relations {
			var existing int
			err := tx.QueryRow(
				"SELECT COUNT(*) FROM md_label_relation WHERE label_id = ? AND resource_id = ? AND relation_type = ?",
				targetLabelID, r.resourceID, r.relationType,
			).Scan(&existing)
			if err != nil {
				return err
			}

			if existing > 0 {
				_, err = tx.Exec(
					"DELETE FROM md_label_relation WHERE label_id = ? AND resource_id = ? AND relation_type = ?",
					sourceID, r.resourceID, r.relationType,
				)
			} else {
				_, err = tx.Exec(
					"UPDATE md_label_relation SET label_id = ? WHERE label_id = ? AND resource_id = ? AND relation_type = ?",
					targetLabelID, sourceID, r.resourceID, r.relationType,
				)
			}
			if err != nil {
				return err
			}
		}

		_, err = tx.Exec("DELETE FROM md_label WHERE label_id = ?", sourceID)
		if err != nil {
			return err
		}

		_, err = tx.Exec("DELETE FROM md_label_relation WHERE label_id = ?", sourceID)
		if err != nil {
			return err
		}
	}

	if err := tx.Commit(); err != nil {
		return err
	}

	// 事务提交后同步受影响资源的 label 字段
	for _, r := range allAffected {
		if err := SyncResourceLabelField(r.resourceID, r.relationType); err != nil {
			log.Printf("MergeLabels: SyncResourceLabelField failed for resource %d (%s): %v", r.resourceID, r.relationType, err)
		}
	}
	return nil
}

// GetLabelsByResource returns label names for a book or blog
func GetLabelsByResource(resourceID int64, relationType string) ([]string, error) {
	rows, err := DB.Query(`
		SELECT l.label_name FROM md_label l
		JOIN md_label_relation r ON l.label_id = r.label_id
		WHERE r.resource_id = ? AND r.relation_type = ?
		LIMIT 100
	`, resourceID, relationType)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	return names, nil
}

// BindLabelsFromNames 根据标签名字符串创建标签并绑定到资源
func BindLabelsFromNames(resourceID int64, relationType, labelsStr string) error {
	if labelsStr == "" {
		return nil
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, name := range splitLabelString(labelsStr) {
		if name == "" {
			continue
		}
		var labelID int64
		err := tx.QueryRow("SELECT label_id FROM md_label WHERE label_name = ?", name).Scan(&labelID)
		if err != nil {
			res, err2 := tx.Exec("INSERT INTO md_label (label_name) VALUES (?)", name)
			if err2 != nil {
				return err2
			}
			labelID, _ = res.LastInsertId()
		}
		if _, err := tx.Exec("INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, ?, datetime('now'))", labelID, resourceID, relationType); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// RebindLabels 删除旧的标签关联并重新绑定
func RebindLabels(resourceID int64, relationType, labelsStr string) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := rebindLabelsTx(tx, resourceID, relationType, labelsStr); err != nil {
		return err
	}
	return tx.Commit()
}

func rebindLabelsTx(tx dbTx, resourceID int64, relationType, labelsStr string) error {
	if _, err := tx.Exec("DELETE FROM md_label_relation WHERE resource_id = ? AND relation_type = ?", resourceID, relationType); err != nil {
		return err
	}

	if labelsStr != "" {
		for _, name := range splitLabelString(labelsStr) {
			if name == "" {
				continue
			}
			var labelID int64
			err := tx.QueryRow("SELECT label_id FROM md_label WHERE label_name = ?", name).Scan(&labelID)
			if err != nil {
				res, err2 := tx.Exec("INSERT INTO md_label (label_name) VALUES (?)", name)
				if err2 != nil {
					return err2
				}
				labelID, _ = res.LastInsertId()
			}
			if _, err := tx.Exec("INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, ?, datetime('now'))", labelID, resourceID, relationType); err != nil {
				return err
			}
		}
	}
	return nil
}

// splitLabelString 按逗号分割标签字符串
func splitLabelString(s string) []string {
	var result []string
	current := ""
	for _, ch := range s {
		if ch == ',' || ch == '，' {
			if current != "" {
				result = append(result, current)
				current = ""
			}
		} else {
			current += string(ch)
		}
	}
	if current != "" {
		result = append(result, current)
	}
	return result
}

// CheckResourcesOwnership 检查指定资源ID列表是否全部属于某个用户
// relationType: "book", "blog" 或 "bookmark"
// 返回不属于该用户的资源数量（0 表示全部属于该用户）
func CheckResourcesOwnership(resourceIDs []int64, relationType string, memberID int64) (int, error) {
	if len(resourceIDs) == 0 {
		return 0, nil
	}

	var table string
	var idCol string
	switch relationType {
	case "book":
		table = "md_books"
		idCol = "book_id"
	case "blog":
		table = "md_blogs"
		idCol = "blog_id"
	case "bookmark":
		table = "md_bookmark"
		idCol = "bookmark_id"
	case "document":
		table = "md_documents"
		idCol = "document_id"
	default:
		return len(resourceIDs), fmt.Errorf("不支持的资源类型: %s", relationType)
	}

	placeholders := ""
	args := []interface{}{memberID}
	for i, id := range resourceIDs {
		if i > 0 {
			placeholders += ","
		}
		placeholders += "?"
		args = append(args, id)
	}

	var count int
	err := DB.QueryRow(
		"SELECT COUNT(*) FROM "+table+" WHERE member_id = ? AND "+idCol+" IN ("+placeholders+")",
		args...,
	).Scan(&count)
	if err != nil {
		return len(resourceIDs), err
	}

	return len(resourceIDs) - count, nil
}

// GetLabelsByResourceAsStr 返回资源的标签逗号分隔字符串
func GetLabelsByResourceAsStr(resourceID int64, relationType string) string {
	labels, err := GetLabelsByResource(resourceID, relationType)
	if err != nil {
		return ""
	}
	return strings.Join(labels, ",")
}

// SyncResourceLabelField 将 md_label_relation 中的标签同步到资源的 label 字段
func SyncResourceLabelField(resourceID int64, relationType string) error {
	var table string
	var idCol string
	switch relationType {
	case "book":
		table = "md_books"
		idCol = "book_id"
	case "bookmark":
		table = "md_bookmark"
		idCol = "bookmark_id"
	default:
		// md_blogs、md_documents 和行动待办没有 label 字段，无需同步
		return nil
	}
	labelStr := GetLabelsByResourceAsStr(resourceID, relationType)
	_, err := DB.Exec("UPDATE "+table+" SET label = ? WHERE "+idCol+" = ?", labelStr, resourceID)
	return err
}
