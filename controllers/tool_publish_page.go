package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"database/sql"
	"encoding/json"
	"errors"
	"html/template"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func ToolPublishSelectionPage(c *gin.Context) {
	if !canPublishTools(c) {
		forbidden(c)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.HTML(http.StatusOK, "tool_publish_select.html", commonData(c, "shares"))
}

func ToolPublishPage(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.Status(404)
		return
	}
	b, err := models.GetBlogByID(id)
	if err != nil {
		c.Status(404)
		return
	}
	if !checkOwnership(c, b.MemberID) {
		forbidden(c)
		return
	}
	publication, err := toolPublicationData(c, b)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	renderToolPublishPage(c, publication, b.BlogTitle)
}
func PackageToolPublishPage(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.Status(404)
		return
	}
	source, err := models.GetToolSource(id)
	if err != nil || source.Kind != "package" {
		c.Status(404)
		return
	}
	if !checkOwnership(c, source.MemberID) {
		forbidden(c)
		return
	}
	publication, err := publicationForSource(c, source)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	renderToolPublishPage(c, publication, "")
}
func renderToolPublishPage(c *gin.Context, publication gin.H, source string) {
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "shares")
	data["ToolID"] = publication["id"]
	initial, err := json.Marshal(publication)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	data["PublicationJSON"] = template.JS(initial)
	data["Package"] = publication["package"]
	data["IsPackage"] = publication["package"] != nil
	data["PackageEntry"] = publication["metadata"].(models.ToolMetadata).Entry
	data["PermissionsChanged"] = publication["permissions_changed"]
	m := publication["metadata"].(models.ToolMetadata)
	title, description := m.Title, m.Description
	if title == "" {
		title = publication["title"].(string)
	}
	if description == "" {
		description = publication["description"].(string)
	}
	category, access := m.Category, m.Access
	if category == "" {
		category = "document"
	}
	if access == "" {
		access = "inherit"
	}
	version := "1.0.0"
	if m.Version != "" && m.SourceKind == "package" {
		version = m.Version
	}
	if versions := publication["versions"].([]gin.H); len(versions) > 0 {
		parts := strings.SplitN(versions[0]["version"].(string), ".", 3)
		if len(parts) == 3 {
			patch, _ := strconv.Atoi(strings.SplitN(parts[2], "-", 2)[0])
			version = parts[0] + "." + parts[1] + "." + strconv.Itoa(patch+1)
		}
	}
	if v, ok := publication["manifest_version"].(string); ok && v != "" {
		version = v
	}
	data["PublishForm"] = gin.H{"Source": source, "Title": title, "Description": description, "Version": version, "Category": category, "Access": access, "Market": publication["market"].(marketSettings).Name, "Members": strings.Join(publication["member_accounts"].([]string), ", "), "Notes": m.Notes}

	flags := m.Permissions.Flags()
	if m.Version == "" {
		flags = map[string]bool{"read_files": true, "save_files": true}
	}
	items := []gin.H{}
	for _, spec := range models.ToolPermissionCatalog {
		if !spec.Managed {
			continue
		}
		label, description := spec.Zh, spec.DescriptionZh
		if middleware.GetLang(c) == "en" {
			label, description = spec.En, spec.DescriptionEn
		}
		name, id := spec.Key, "publishPermission_"+spec.Key
		if spec.Key == "read_files" {
			name, id = "read", "publishRead"
		}
		if spec.Key == "save_files" {
			name, id = "save", "publishSave"
		}
		items = append(items, gin.H{"Key": spec.Key, "Name": name, "ID": id, "Label": label, "Description": description, "Checked": flags[spec.Key]})
	}
	data["ManagedPermissions"] = items

	data["IconSlots"] = make([]struct{}, 24)
	c.HTML(200, "tool_publish.html", data)
}

type toolPublishArticle struct {
	ID          int64     `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Updated     time.Time `json:"updated"`
	Published   bool      `json:"published"`
	Version     string    `json:"version"`
}

func scanToolPublishArticle(row interface{ Scan(...any) error }) (*toolPublishArticle, error) {
	var article toolPublishArticle
	err := row.Scan(&article.ID, &article.Title, &article.Description, &article.Updated, &article.Published, &article.Version)
	return &article, err
}

func ToolPublishArticles(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	if !canPublishTools(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "publication_forbidden"})
		return
	}
	// Read source metadata only. Never fetch or execute HTML to populate this list.
	base := ` FROM md_blogs b LEFT JOIN md_tools ts ON ts.blog_id=b.blog_id LEFT JOIN md_tool_releases p ON p.tool_id=ts.tool_id
        LEFT JOIN md_tool_versions v ON v.revision=p.revision AND v.status='published'`
	eligible := ` WHERE b.editor_type='html' AND COALESCE(b.blog_type,'article')='article' AND COALESCE(b.password,'')=''`
	ownerArgs := []any{}
	if !isAdmin(c) {
		eligible += " AND b.member_id=?"
		ownerArgs = append(ownerArgs, middleware.GetMemberID(c))
	}
	where, args := eligible, append([]any{}, ownerArgs...)
	keyword := strings.TrimSpace(c.Query("q"))
	if len(keyword) > 800 {
		c.JSON(400, gin.H{"error": "invalid_request"})
		return
	}
	if keyword != "" {
		where += " AND b.blog_title LIKE ?"
		args = append(args, "%"+keyword+"%")
	}
	switch c.Query("status") {
	case "published":
		where += " AND v.revision IS NOT NULL"
	case "unpublished":
		where += " AND v.revision IS NULL"
	}
	order := "b.modify_time DESC,b.blog_id DESC"
	if c.Query("sort") == "name" {
		order = "b.blog_title COLLATE NOCASE,b.blog_id"
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	take, _ := strconv.Atoi(c.DefaultQuery("take", "10"))
	if take != 10 && take != 20 && take != 50 {
		take = 10
	}
	var total int64
	if err := models.DB.QueryRow("SELECT COUNT(*)"+base+where, args...).Scan(&total); err != nil {
		toolAPIError(c, err)
		return
	}
	pages := (total + int64(take) - 1) / int64(take)
	if pages < 1 {
		pages = 1
	}
	if int64(page) > pages {
		page = int(pages)
	}
	columns := "SELECT b.blog_id,b.blog_title,COALESCE(b.blog_desc,''),b.modify_time,v.revision IS NOT NULL,COALESCE(v.version,'')"
	pageArgs := append(append([]any{}, args...), take, (page-1)*take)
	rows, err := models.DB.Query(columns+base+where+" ORDER BY "+order+" LIMIT ? OFFSET ?", pageArgs...)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer rows.Close()
	articles := []toolPublishArticle{}
	for rows.Next() {
		article, err := scanToolPublishArticle(rows)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		articles = append(articles, *article)
	}
	if err := rows.Err(); err != nil {
		toolAPIError(c, err)
		return
	}
	rows.Close()
	var selected *toolPublishArticle
	if id, err := strconv.ParseInt(c.Query("selected"), 10, 64); err == nil && id > 0 {
		article, err := scanToolPublishArticle(models.DB.QueryRow(columns+base+eligible+" AND b.blog_id=?", append(append([]any{}, ownerArgs...), id)...))
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			toolAPIError(c, err)
			return
		}
		if err == nil {
			selected = article
		}
	}
	c.JSON(http.StatusOK, gin.H{"articles": articles, "selected": selected, "total": total, "page": page, "take": take, "total_pages": pages})
}
