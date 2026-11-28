package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

func PublishMarketTool(router http.Handler) gin.HandlerFunc {
	return func(c *gin.Context) {
		article, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.Status(404)
			return
		}
		blog, err := models.GetBlogByID(article)
		if err != nil {
			c.Status(404)
			return
		}
		if !checkOwnership(c, blog.MemberID) {
			forbidden(c)
			return
		}
		id, err := models.EnsureArticleTool(article, blog.MemberID)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		source, err := models.GetToolSource(id)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		publishToolSource(c, router, source, blog)
	}
}
func PublishToolSource(router http.Handler) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.Status(404)
			return
		}
		source, err := models.GetToolSource(id)
		if err != nil {
			c.Status(404)
			return
		}
		if !checkOwnership(c, source.MemberID) {
			forbidden(c)
			return
		}
		var blog *models.Blog
		if source.BlogID.Valid {
			blog, err = models.GetBlogByID(source.BlogID.Int64)
			if err != nil {
				c.Status(404)
				return
			}
		}
		publishToolSource(c, router, source, blog)
	}
}
func publishToolSource(c *gin.Context, router http.Handler, source models.ToolSource, blog *models.Blog) {
	c.Header("Cache-Control", "private, no-store")
	id := source.ID
	var err error
	if c.Request.Method == "GET" {
		data, err := publicationForSource(c, source)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		c.JSON(http.StatusOK, data)
		return
	}
	if c.Request.Method == "DELETE" {
		tx, err := models.DB.Begin()
		if err != nil {
			toolAPIError(c, err)
			return
		}
		defer tx.Rollback()
		_, err = tx.Exec("UPDATE md_tool_versions SET status='withdrawn',metadata=json_set(metadata,'$.status','withdrawn') WHERE tool_id=? AND status='pending'", id)
		if err == nil {
			_, err = tx.Exec("DELETE FROM md_tool_releases WHERE tool_id=?", id)
		}
		if err == nil {
			err = tx.Commit()
		}
		if err != nil {
			toolAPIError(c, err)
			return
		}
		c.JSON(200, gin.H{"ok": true})
		return
	}
	if c.Request.Method == "PATCH" {
		updatePublishedToolInfo(c, source)
		return
	}
	settings := readMarketSettings(c)
	if !settings.Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	if !isAdmin(c) && !settings.MembersPublish {
		c.Status(403)
		return
	}
	if blog != nil && (blog.EditorType != "html" || blog.BlogType != "article" || blog.Password != "") {
		c.JSON(422, gin.H{"error": "publish_requires_html"})
		return
	}
	title, description := "", ""
	if blog != nil {
		title, description = blog.BlogTitle, blog.BlogDesc
	}
	req := toolPublication{Title: title, Description: description, ToolMetadata: models.ToolMetadata{Category: "other", Access: "inherit", Offline: true, Permissions: models.ToolPermissions{ReadFiles: true, SaveFiles: true}}}
	if c.Request.ContentLength != 0 {
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 16384)
		if c.ShouldBindJSON(&req) != nil {
			c.Status(400)
			return
		}
	}
	req.Permissions = req.Permissions.Effective()
	req.Title = strings.TrimSpace(req.Title)
	if !models.ValidToolAppearance(req.Icon, req.IconStyle, req.IconColor) {
		c.JSON(400, gin.H{"error": "invalid_tool_appearance"})
		return
	}
	req.IconColor = strings.ToLower(req.IconColor)
	if req.Version == "" {
		var count int
		models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_versions WHERE tool_id=?", id).Scan(&count)
		req.Version = fmt.Sprintf("1.0.%d", count)
	}
	if len(req.MemberAccounts) > 1000 {
		c.Status(400)
		return
	}
	if req.Access == "members" && len(req.MemberAccounts) > 0 {
		req.Members = nil
		for _, account := range req.MemberAccounts {
			m, e := models.GetMemberByAccount(strings.TrimSpace(account))
			if e != nil || m.Status != 1 {
				c.JSON(400, gin.H{"error": "invalid_market_member"})
				return
			}
			req.Members = append(req.Members, m.MemberID)
		}
	}
	for _, id := range req.Members {
		if id <= 0 {
			c.Status(400)
			return
		}
	}
	if len(req.Version) > 64 || !toolSemver.MatchString(req.Version) || len(req.Title) == 0 || len(req.Title) > 200 || len(req.Description) > 4000 || len(req.Notes) > 8000 || !validToolCategory(req.Category) || (req.Access != "inherit" && req.Access != "login" && req.Access != "public" && req.Access != "members") || len(req.Members) > 1000 || (req.Access == "members" && len(req.Members) == 0) {
		c.JSON(400, gin.H{"error": "invalid_publication"})
		return
	}
	var exists int
	if models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_versions WHERE tool_id=? AND version=?", id, req.Version).Scan(&exists) != nil || exists > 0 {
		c.JSON(409, gin.H{"error": "version_exists"})
		return
	}
	base := strings.TrimSuffix(settings.PublicURL, "/market")
	var content, resourceBase string
	var assets []toolpackage.Asset
	var files []toolpackage.File
	if source.Kind == "article" {
		content, err = decodeMarketContent(blog.BlogContent)
		if err != nil {
			c.JSON(422, gin.H{"error": "invalid_package"})
			return
		}
		resourceBase = base + "/shares/" + blog.BlogIdentify
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Minute)
		defer cancel()
		_, assets, err = toolpackage.Build(ctx, content, resourceBase, localToolFetch(router, base))
		req.Package = ""
		req.Entry = ""
	} else {
		p, e := models.GetToolPackage(req.Package)
		if e != nil || p.MemberID != source.MemberID || !checkOwnership(c, p.MemberID) {
			c.JSON(403, gin.H{"error": "publication_forbidden"})
			return
		}
		valid := false
		for _, entry := range p.Entries {
			if entry == req.Entry {
				valid = true
			}
		}
		if !valid {
			c.JSON(422, gin.H{"error": "invalid_entry"})
			return
		}
		resourceBase = base + "/api/tool-package-assets/" + p.Token + "/"
		var b []byte
		b, _, err = models.ReadToolPackageFile(p, req.Entry)
		content = string(b)
		files = p.Files
		if len(content) > 20<<20 {
			c.JSON(422, gin.H{"error": "invalid_entry"})
			return
		}
		// Verify all persisted bytes; package installation uses this full manifest.
		if err == nil {
			for _, f := range files {
				var data []byte
				data, _, err = models.ReadToolPackageFile(p, f.Name)
				if err != nil {
					break
				}
				assets = append(assets, toolpackage.Asset{Name: f.Name, MIME: f.MIME, URL: toolpackage.AssetURL(resourceBase, f.Name), Data: data})
			}
		}
	}
	if err != nil {
		c.JSON(422, gin.H{"error": "resource_download_failed", "detail": err.Error()})
		return
	}

	req.Title = strings.TrimSpace(req.Title)
	req.ToolMetadata.Title = req.Title
	req.ToolMetadata.Description = req.Description
	req.DataRoot = ""
	req.Size = int64(len(content))
	if source.Kind == "package" {
		req.Size = 0
	}
	for _, asset := range assets {
		req.Size += int64(len(asset.Data))
	}
	req.Distribution = "references"
	req.SourceKind = source.Kind
	if source.Kind == "package" {
		req.Distribution = "files"
	}
	req.AssetCount = len(assets)
	req.Offline = !req.Permissions.Network
	req.Status = "published"
	if !isAdmin(c) && settings.ReviewRequired {
		req.Status = "pending"
	}
	req.Hash, err = referenceDigest(marketTool{ToolMetadata: req.ToolMetadata, Title: req.Title, Description: req.Description, Content: content, ResourceBase: resourceBase, Files: files})
	if err != nil {
		toolAPIError(c, err)
		return
	}
	revision := fmt.Sprintf("%x", sha256.Sum256([]byte(req.Hash+fmt.Sprint(time.Now().UnixNano()))))
	if c.Query("preview") == "1" {
		previews := toolResourcePreviews(assets, base)
		if source.Kind == "package" {
			for index := range previews {
				previews[index].Kind = "package"
				previews[index].URL = toolpackage.AssetURL(base+"/api/tool-packages/"+req.Package+"/files", assets[index].Name)
			}
		}
		c.JSON(200, gin.H{"metadata": req.ToolMetadata, "resources": previews})
		return
	}
	metadata, _ := json.Marshal(req.ToolMetadata)
	tx, err := models.DB.Begin()
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer tx.Rollback()
	if req.Package != "" {
		var token string
		if err = tx.QueryRow("SELECT token FROM md_tool_packages WHERE token=?", req.Package).Scan(&token); err != nil {
			toolAPIError(c, err)
			return
		}
	}
	_, err = tx.Exec("INSERT INTO md_tool_versions(tool_id,version,revision,metadata,status,created,content,resource_base) VALUES(?,?,?,?,?,?,?,?)", id, req.Version, revision, string(metadata), req.Status, time.Now().UnixMilli(), content, resourceBase)
	if err == nil && req.Status == "published" {
		_, err = tx.Exec(`INSERT INTO md_tool_releases(tool_id,title,description,content,revision) VALUES(?,?,?,?,?) ON CONFLICT(tool_id) DO UPDATE SET title=excluded.title,description=excluded.description,content=excluded.content,revision=excluded.revision`, id, req.Title, req.Description, content, revision)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		toolAPIError(c, err)
		return
	}
	if req.Status == "published" && req.Package != "" {
		_ = models.PruneSupersededToolPackages(id, revision, req.Package)
	}
	// Store review metadata independently from the editable source article.
	c.JSON(200, gin.H{"ok": true, "id": id, "revision": revision, "metadata": req.ToolMetadata, "status": req.Status})
}

func updatePublishedToolInfo(c *gin.Context, source models.ToolSource) {
	settings := readMarketSettings(c)
	if !settings.Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	if !isAdmin(c) && !settings.MembersPublish {
		c.Status(403)
		return
	}
	var revision, rawMeta, content, resourceBase string
	err := models.DB.QueryRow(`SELECT r.revision,v.metadata,v.content,v.resource_base FROM md_tool_releases r JOIN md_tool_versions v ON v.revision=r.revision AND v.status='published' WHERE r.tool_id=?`, source.ID).Scan(&revision, &rawMeta, &content, &resourceBase)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	var current models.ToolMetadata
	if err = json.Unmarshal([]byte(rawMeta), &current); err != nil {
		toolAPIError(c, err)
		return
	}
	var req struct {
		Title          string                  `json:"title"`
		Description    string                  `json:"description"`
		Category       string                  `json:"category"`
		Icon           string                  `json:"icon"`
		IconStyle      string                  `json:"icon_style"`
		IconColor      string                  `json:"icon_color"`
		Access         string                  `json:"access"`
		Members        []int64                 `json:"members"`
		MemberAccounts []string                `json:"member_accounts"`
		Notes          string                  `json:"notes"`
		Package        string                  `json:"package"`
		Entry          string                  `json:"entry"`
		Permissions    *models.ToolPermissions `json:"permissions"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 16384)
	if c.ShouldBindJSON(&req) != nil {
		c.Status(400)
		return
	}
	if (req.Package != "" && req.Package != current.Package) || (req.Entry != "" && req.Entry != current.Entry) || (req.Permissions != nil && !current.Permissions.SameManaged(req.Permissions.Effective())) {
		c.JSON(409, gin.H{"error": "version_bump_required"})
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	if !models.ValidToolAppearance(req.Icon, req.IconStyle, req.IconColor) {
		c.JSON(400, gin.H{"error": "invalid_tool_appearance"})
		return
	}
	req.IconColor = strings.ToLower(req.IconColor)
	if len(req.MemberAccounts) > 1000 {
		c.Status(400)
		return
	}
	if req.Access == "members" {
		if len(req.MemberAccounts) > 0 {
			req.Members = nil
			for _, account := range req.MemberAccounts {
				m, e := models.GetMemberByAccount(strings.TrimSpace(account))
				if e != nil || m.Status != 1 {
					c.JSON(400, gin.H{"error": "invalid_market_member"})
					return
				}
				req.Members = append(req.Members, m.MemberID)
			}
		}
		for _, memberID := range req.Members {
			if memberID <= 0 {
				c.Status(400)
				return
			}
		}
	} else {
		req.Members = nil
	}
	if len(req.Title) == 0 || len(req.Title) > 200 || len(req.Description) > 4000 || len(req.Notes) > 8000 || !validToolCategory(req.Category) || (req.Access != "inherit" && req.Access != "login" && req.Access != "public" && req.Access != "members") || len(req.Members) > 1000 || (req.Access == "members" && len(req.Members) == 0) {
		c.JSON(400, gin.H{"error": "invalid_publication"})
		return
	}
	var files []toolpackage.File
	base := strings.TrimSuffix(settings.PublicURL, "/market")
	if current.Distribution == "files" {
		p, e := models.GetToolPackage(current.Package)
		if e != nil {
			toolAPIError(c, e)
			return
		}
		files = p.Files
		resourceBase = base + "/api/tool-package-assets/" + current.Package + "/"
	} else if u, e := url.Parse(resourceBase); e == nil && u.Path != "" {
		resourceBase = base + u.Path
	}
	current.Title = req.Title
	current.Description = req.Description
	current.Category = req.Category
	current.Icon = req.Icon
	current.IconStyle = req.IconStyle
	current.IconColor = req.IconColor
	current.Access = req.Access
	current.Members = req.Members
	current.Notes = req.Notes
	current.Hash, err = referenceDigest(marketTool{ToolMetadata: current, Title: current.Title, Description: current.Description, Content: content, ResourceBase: resourceBase, Files: files})
	if err != nil {
		toolAPIError(c, err)
		return
	}
	metadata, _ := json.Marshal(current)
	tx, err := models.DB.Begin()
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer tx.Rollback()
	result, err := tx.Exec("UPDATE md_tool_releases SET title=?,description=? WHERE tool_id=? AND revision=?", current.Title, current.Description, source.ID, revision)
	if err == nil {
		n, e := result.RowsAffected()
		if e != nil {
			err = e
		} else if n != 1 {
			c.JSON(409, gin.H{"error": "conflict"})
			return
		}
	}
	if err == nil {
		_, err = tx.Exec("UPDATE md_tool_versions SET metadata=?,resource_base=? WHERE revision=? AND status='published'", string(metadata), resourceBase, revision)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"ok": true, "id": source.ID, "revision": revision, "metadata": current, "status": current.Status, "updated_in_place": true})
}
