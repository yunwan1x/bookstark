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
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "shares")
	data["ToolID"] = id
	publication, err := toolPublicationData(c, b)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	initial, err := json.Marshal(publication)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	data["PublicationJSON"] = template.JS(initial)
	m := publication["metadata"].(models.ToolMetadata)
	title, description := m.Title, m.Description
	if title == "" {
		title = b.BlogTitle
	}
	if description == "" {
		description = b.BlogDesc
	}
	category, access := m.Category, m.Access
	if category == "" {
		category = "document"
	}
	if access == "" {
		access = "inherit"
	}
	version := "1.0.0"
	if versions := publication["versions"].([]gin.H); len(versions) > 0 {
		parts := strings.SplitN(versions[0]["version"].(string), ".", 3)
		if len(parts) == 3 {
			patch, _ := strconv.Atoi(strings.SplitN(parts[2], "-", 2)[0])
			version = parts[0] + "." + parts[1] + "." + strconv.Itoa(patch+1)
		}
	}
	data["PublishForm"] = gin.H{"Source": b.BlogTitle, "Title": title, "Description": description, "Version": version, "Category": category, "Access": access, "Market": publication["market"].(marketSettings).Name, "Members": strings.Join(publication["member_accounts"].([]string), ", "), "Notes": m.Notes}

	flags := m.Permissions.Flags()
	if m.Version == "" {
		flags = map[string]bool{"read_files": true, "save_files": true}
	}
	groups := []gin.H{}
	labels := map[string][2]string{"files": {"文件与网络", "Files and network"}, "devices": {"设备与隐私", "Devices and privacy"}, "interaction": {"浏览器交互", "Browser interaction"}, "advanced": {"高级设备与接口", "Advanced devices and APIs"}}
	for _, key := range []string{"files", "devices", "interaction", "advanced"} {
		items := []gin.H{}
		for _, spec := range models.ToolPermissionCatalog {
			if spec.Group != key {
				continue
			}
			label, description := spec.Zh, spec.DescriptionZh
			if middleware.GetLang(c) == "en" {
				label, description = spec.En, spec.DescriptionEn
			}
			name := spec.Key
			id := "publishPermission_" + spec.Key
			if spec.Key == "read_files" {
				name = "read"
				id = "publishRead"
			}
			if spec.Key == "save_files" {
				name = "save"
				id = "publishSave"
			}
			if spec.Key == "network" {
				id = "publishNetwork"
			}
			items = append(items, gin.H{"Key": spec.Key, "Name": name, "ID": id, "Label": label, "Description": description, "Checked": flags[spec.Key]})
		}
		label := labels[key][0]
		if middleware.GetLang(c) == "en" {
			label = labels[key][1]
		}
		groups = append(groups, gin.H{"Key": key, "Label": label, "Items": items, "Advanced": key == "advanced"})
	}
	data["PermissionGroups"] = groups

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
	base := ` FROM md_blogs b LEFT JOIN md_tool_releases p ON p.blog_id=b.blog_id
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
