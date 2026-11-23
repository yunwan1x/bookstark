package controllers

import (
	"bookstark/models"

	"bookstark/internal/toolpackage"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"io"
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
type toolBundle struct {
	Version     string                 `json:"version"`
	Permissions models.ToolPermissions `json:"permissions"`
	Access      string                 `json:"access"`
	Members     []int64                `json:"members,omitempty"`
	Title       string                 `json:"title"`
	Description string                 `json:"description"`
	Content     string                 `json:"content"`
	Assets      []toolpackage.Asset    `json:"assets"`
}

func encodeToolBundle(b toolBundle) ([]byte, error) {
	var out bytes.Buffer
	writer := gzip.NewWriter(&out)
	if err := json.NewEncoder(writer).Encode(b); err != nil {
		return nil, err
	}
	if err := writer.Close(); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}
func decodeToolBundle(data []byte) (toolBundle, error) {
	var b toolBundle
	r, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return b, err
	}
	defer r.Close()
	err = json.NewDecoder(io.LimitReader(r, 400<<20)).Decode(&b)
	return b, err
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
			_, err = models.DB.Exec("DELETE FROM md_tool_releases WHERE blog_id=?", id)
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
		content, assets, err := toolpackage.Build(ctx, content, base+"/shares/"+blog.BlogIdentify, localToolFetch(router, base))
		if err != nil {
			c.JSON(422, gin.H{"error": "resource_download_failed"})
			return
		}
		data, err := encodeToolBundle(toolBundle{Version: req.Version, Permissions: req.Permissions, Access: req.Access, Members: req.Members, Title: req.Title, Description: req.Description, Content: content, Assets: assets})
		if err != nil {
			toolAPIError(c, err)
			return
		}
		req.Title = strings.TrimSpace(req.Title)
		req.ToolMetadata.Title = req.Title
		req.ToolMetadata.Description = req.Description
		req.DataRoot = ""
		req.Size = int64(len(data))
		req.AssetCount = len(assets)
		req.Offline = !req.Permissions.Network
		req.Status = "published"
		if !isAdmin(c) && settings.ReviewRequired {
			req.Status = "pending"
		}
		req.Hash = fmt.Sprintf("%x", sha256.Sum256(data))
		revision := fmt.Sprintf("%x", sha256.Sum256(append(append([]byte{}, data...), []byte(req.Version+req.Title+req.Description+fmt.Sprint(time.Now().UnixNano()))...)))
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
		_, err = tx.Exec("INSERT INTO md_tool_versions(blog_id,version,revision,metadata,package,status,created) VALUES(?,?,?,?,?,?,?)", id, req.Version, revision, string(metadata), data, req.Status, time.Now().UnixMilli())
		if err == nil && req.Status == "published" {
			encoded, _ := models.EncodeHTMLContent(content)
			_, err = tx.Exec(`INSERT INTO md_tool_releases(blog_id,title,description,content,revision) VALUES(?,?,?,?,?) ON CONFLICT(blog_id) DO UPDATE SET title=excluded.title,description=excluded.description,content=excluded.content,revision=excluded.revision`, id, req.Title, req.Description, encoded, revision)
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
	var data []byte
	err := models.DB.QueryRow("SELECT blog_id,metadata,package FROM md_tool_versions WHERE revision=? AND status='pending'", req.Revision).Scan(&id, &raw, &data)
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
		bundle, e := decodeToolBundle(data)
		if e != nil {
			toolAPIError(c, e)
			return
		}
		encoded, _ := models.EncodeHTMLContent(bundle.Content)
		_, err = tx.Exec(`INSERT INTO md_tool_releases(blog_id,title,description,content,revision) VALUES(?,?,?,?,?) ON CONFLICT(blog_id) DO UPDATE SET title=excluded.title,description=excluded.description,content=excluded.content,revision=excluded.revision`, id, bundle.Title, bundle.Description, encoded, req.Revision)
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

func ToolVersionPackage(c *gin.Context) {
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
	var data []byte
	if models.DB.QueryRow("SELECT package FROM md_tool_versions WHERE revision=? AND status='published'", revision).Scan(&data) != nil {
		c.Status(404)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.Header("Content-Disposition", `attachment; filename="tool-`+revision+`.gz"`)
	c.Data(200, "application/gzip", data)
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
