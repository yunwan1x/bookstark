package controllers

import (
	"bookstark/models"

	"bookstark/internal/toolpackage"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var toolSemver = regexp.MustCompile(`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[a-zA-Z0-9.-]+)?$`)

type toolPublication struct {
	MemberAccounts []string `json:"member_accounts"`
	Title          string   `json:"title"`
	Description    string   `json:"description"`
	models.ToolMetadata
}

func latestToolMetadata(id int64) models.ToolMetadata {
	var raw string
	var m models.ToolMetadata
	if models.DB.QueryRow("SELECT v.metadata FROM md_tool_versions v JOIN md_tool_releases p ON p.revision=v.revision WHERE p.blog_id=?", id).Scan(&raw) == nil {
		json.Unmarshal([]byte(raw), &m)
	}
	return m
}
func PublishMarketTool(router http.Handler) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Cache-Control", "private, no-store")
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.Status(404)
			return
		}
		blog, err := models.GetBlogByID(id)
		if err != nil {
			c.Status(404)
			return
		}
		if !checkOwnership(c, blog.MemberID) {
			forbidden(c)
			return
		}
		var current string
		_ = models.DB.QueryRow("SELECT revision FROM md_tool_releases WHERE blog_id=?", id).Scan(&current)
		if c.Request.Method == "GET" {
			m := latestToolMetadata(id)
			rows, err := models.DB.Query("SELECT version,revision,status,created FROM md_tool_versions WHERE blog_id=? ORDER BY created DESC,rowid DESC", id)
			if err != nil {
				toolAPIError(c, err)
				return
			}
			defer rows.Close()
			versions := []gin.H{}
			for rows.Next() {
				var version, revision, status string
				var created int64
				if err := rows.Scan(&version, &revision, &status, &created); err != nil {
					toolAPIError(c, err)
					return
				}
				versions = append(versions, gin.H{"version": version, "revision": revision, "status": status, "created": created})
			}
			if err := rows.Err(); err != nil {
				toolAPIError(c, err)
				return
			}
			rows.Close()
			accounts := []string{}
			for _, memberID := range m.Members {
				var account string
				if err := models.DB.QueryRow("SELECT account FROM md_members WHERE member_id=?", memberID).Scan(&account); err == nil {
					accounts = append(accounts, account)
				}
			}
			c.JSON(200, gin.H{"published": current != "", "revision": current, "title": blog.BlogTitle, "description": blog.BlogDesc, "metadata": m, "member_accounts": accounts, "versions": versions, "market": readMarketSettings(c)})
			return
		}
		if c.Request.Method == "DELETE" {
			tx, err := models.DB.Begin()
			if err != nil {
				toolAPIError(c, err)
				return
			}
			defer tx.Rollback()
			_, err = tx.Exec("UPDATE md_tool_versions SET status='withdrawn',metadata=json_set(metadata,'$.status','withdrawn') WHERE blog_id=? AND status='pending'", id)
			if err == nil {
				_, err = tx.Exec("DELETE FROM md_tool_releases WHERE blog_id=?", id)
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
		settings := readMarketSettings(c)
		if !settings.Enabled {
			c.JSON(503, gin.H{"error": "market_disabled"})
			return
		}
		if !isAdmin(c) && !settings.MembersPublish {
			c.Status(403)
			return
		}
		if blog.EditorType != "html" || blog.BlogType != "article" || blog.Password != "" {
			c.JSON(422, gin.H{"error": "publish_requires_html"})
			return
		}
		req := toolPublication{Title: blog.BlogTitle, Description: blog.BlogDesc, ToolMetadata: models.ToolMetadata{Category: "other", Access: "inherit", Offline: true, Permissions: models.ToolPermissions{ReadFiles: true, SaveFiles: true}}}
		if c.Request.ContentLength != 0 {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 16384)
			if c.ShouldBindJSON(&req) != nil {
				c.Status(400)
				return
			}
		}
		req.Title = strings.TrimSpace(req.Title)
		if req.Version == "" {
			var count int
			models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_versions WHERE blog_id=?", id).Scan(&count)
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
		if models.DB.QueryRow("SELECT COUNT(*) FROM md_tool_versions WHERE blog_id=? AND version=?", id, req.Version).Scan(&exists) != nil || exists > 0 {
			c.JSON(409, gin.H{"error": "version_exists"})
			return
		}
		content, err := decodeMarketContent(blog.BlogContent)
		if err != nil {
			c.JSON(422, gin.H{"error": "invalid_package"})
			return
		}
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Minute)
		defer cancel()
		base := strings.TrimSuffix(settings.PublicURL, "/market")
		resourceBase := base + "/shares/" + blog.BlogIdentify
		// Validate and measure dependencies without retaining a second copy.
		_, assets, err := toolpackage.Build(ctx, content, resourceBase, localToolFetch(router, base))
		if err != nil {
			c.JSON(422, gin.H{"error": "resource_download_failed"})
			return
		}
		req.Title = strings.TrimSpace(req.Title)
		req.ToolMetadata.Title = req.Title
		req.ToolMetadata.Description = req.Description
		req.DataRoot = ""
		req.Size = int64(len(content))
		for _, asset := range assets {
			req.Size += int64(len(asset.Data))
		}
		req.Distribution = "references"
		req.AssetCount = len(assets)
		req.Offline = !req.Permissions.Network
		req.Status = "published"
		if !isAdmin(c) && settings.ReviewRequired {
			req.Status = "pending"
		}
		req.Hash, err = referenceDigest(marketTool{ToolMetadata: req.ToolMetadata, Title: req.Title, Description: req.Description, Content: content, ResourceBase: resourceBase})
		if err != nil {
			toolAPIError(c, err)
			return
		}
		revision := fmt.Sprintf("%x", sha256.Sum256([]byte(req.Hash+fmt.Sprint(time.Now().UnixNano()))))
		if c.Query("preview") == "1" {
			c.JSON(200, gin.H{"metadata": req.ToolMetadata})
			return
		}
		metadata, _ := json.Marshal(req.ToolMetadata)
		tx, err := models.DB.Begin()
		if err != nil {
			toolAPIError(c, err)
			return
		}
		defer tx.Rollback()
		_, err = tx.Exec("INSERT INTO md_tool_versions(blog_id,version,revision,metadata,status,created,content,resource_base) VALUES(?,?,?,?,?,?,?,?)", id, req.Version, revision, string(metadata), req.Status, time.Now().UnixMilli(), content, resourceBase)
		if err == nil && req.Status == "published" {
			_, err = tx.Exec(`INSERT INTO md_tool_releases(blog_id,title,description,content,revision) VALUES(?,?,?,?,?) ON CONFLICT(blog_id) DO UPDATE SET title=excluded.title,description=excluded.description,content=excluded.content,revision=excluded.revision`, id, req.Title, req.Description, content, revision)
		}
		if err == nil {
			err = tx.Commit()
		}
		if err != nil {
			toolAPIError(c, err)
			return
		}
		// Store review metadata independently from the editable source article.
		c.JSON(200, gin.H{"ok": true, "revision": revision, "metadata": req.ToolMetadata, "status": req.Status})
	}
}
func validToolCategory(s string) bool {
	switch s {
	case "document", "image", "media", "development", "productivity", "other":
		return true
	}
	return false
}
func ToolMarketReviews(c *gin.Context) {
	if c.Request.Method == "GET" {
		rows, err := models.DB.Query(`SELECT v.blog_id,v.version,v.revision,v.created,COALESCE(json_extract(v.metadata,'$.title'),b.blog_title),COALESCE(m.account,'') FROM md_tool_versions v JOIN md_blogs b ON b.blog_id=v.blog_id LEFT JOIN md_members m ON m.member_id=b.member_id WHERE v.status='pending' ORDER BY v.created`)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		defer rows.Close()
		items := []gin.H{}
		for rows.Next() {
			var id, created int64
			var ver, rev, title, author string
			rows.Scan(&id, &ver, &rev, &created, &title, &author)
			items = append(items, gin.H{"id": id, "version": ver, "revision": rev, "title": title, "author": author})
		}
		c.JSON(200, gin.H{"items": items})
		return
	}
	var req struct {
		Revision string `json:"revision"`
		Approve  bool   `json:"approve"`
	}
	if c.ShouldBindJSON(&req) != nil {
		c.Status(400)
		return
	}
	var id int64
	var raw string
	var content string
	err := models.DB.QueryRow("SELECT blog_id,metadata,content FROM md_tool_versions WHERE revision=? AND status='pending'", req.Revision).Scan(&id, &raw, &content)
	if err != nil {
		c.Status(404)
		return
	}
	var m models.ToolMetadata
	json.Unmarshal([]byte(raw), &m)
	m.Status = "rejected"
	if req.Approve {
		m.Status = "published"
	}
	meta, _ := json.Marshal(m)
	tx, err := models.DB.Begin()
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer tx.Rollback()
	result, err := tx.Exec("UPDATE md_tool_versions SET status=?,metadata=? WHERE revision=? AND status='pending'", m.Status, string(meta), req.Revision)
	if err == nil {
		n, e := result.RowsAffected()
		if e != nil {
			err = e
		} else if n != 1 {
			c.JSON(409, gin.H{"error": "conflict"})
			return
		}
	}

	if err == nil && req.Approve {

		_, err = tx.Exec(`INSERT INTO md_tool_releases(blog_id,title,description,content,revision) VALUES(?,?,?,?,?) ON CONFLICT(blog_id) DO UPDATE SET title=excluded.title,description=excluded.description,content=excluded.content,revision=excluded.revision`, id, m.Title, m.Description, content, req.Revision)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"ok": true})
}

func ToolVersionManifest(c *gin.Context) {
	revision := c.Param("revision")
	if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(revision) {
		c.Status(404)
		return
	}
	var id int64
	var raw string
	if models.DB.QueryRow("SELECT blog_id,metadata FROM md_tool_versions WHERE revision=? AND status='published'", revision).Scan(&id, &raw) != nil {
		c.Status(404)
		return
	}
	// A withdrawn tool cannot be newly downloaded, including old versions.
	var current string
	if models.DB.QueryRow("SELECT revision FROM md_tool_releases WHERE blog_id=?", id).Scan(&current) != nil {
		c.Status(404)
		return
	}
	if !mayInstallTool(c, latestToolMetadata(id)) {
		return
	}
	var metadata models.ToolMetadata
	if json.Unmarshal([]byte(raw), &metadata) != nil {
		c.Status(500)
		return
	}
	if !mayInstallTool(c, metadata) {
		return
	}
	var resourceBase, content string
	if models.DB.QueryRow("SELECT content,resource_base FROM md_tool_versions WHERE revision=? AND status='published'", revision).Scan(&content, &resourceBase) != nil {
		c.Status(404)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.JSON(200, marketTool{ToolMetadata: metadata, ID: id, Title: metadata.Title, Description: metadata.Description, Revision: revision, Content: content, ResourceBase: resourceBase})
}

func ToolReleaseHistory(c *gin.Context) {
	if !readMarketSettings(c).Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.Status(404)
		return
	}
	var current string
	if models.DB.QueryRow("SELECT revision FROM md_tool_releases WHERE blog_id=?", id).Scan(&current) != nil {
		c.Status(404)
		return
	}
	rows, err := models.DB.Query("SELECT metadata,created FROM md_tool_versions WHERE blog_id=? AND status='published' ORDER BY created DESC", id)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var raw string
		var at int64
		if err := rows.Scan(&raw, &at); err != nil {
			toolAPIError(c, err)
			return
		}
		var m models.ToolMetadata
		if json.Unmarshal([]byte(raw), &m) != nil {
			c.Status(500)
			return
		}
		items = append(items, gin.H{"version": m.Version, "notes": m.Notes, "size": m.Size, "created": at})
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(200, gin.H{"versions": items})
}
