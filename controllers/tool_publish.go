package controllers

import (
	"bookstark/models"

	"bookstark/internal/toolpackage"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

var toolSemver = regexp.MustCompile(`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[a-zA-Z0-9.-]+)?$`)

type toolPublication struct {
	MemberAccounts []string `json:"member_accounts"`
	Title          string   `json:"title"`
	Description    string   `json:"description"`
	models.ToolMetadata
}

type toolResourcePreview struct {
	URL        string `json:"url"`
	Kind       string `json:"kind"`
	MIME       string `json:"mime"`
	Size       int64  `json:"size"`
	Account    string `json:"account,omitempty"`
	WebDAVPath string `json:"webdav_path,omitempty"`
}

func toolResourcePreviews(assets []toolpackage.Asset, origin string) []toolResourcePreview {
	resources := make([]toolResourcePreview, 0, len(assets))
	base, _ := url.Parse(origin)
	for _, asset := range assets {
		u, err := url.Parse(asset.URL)
		if err != nil {
			continue
		}
		resource := toolResourcePreview{URL: u.Redacted(), Kind: "external", MIME: asset.MIME, Size: int64(len(asset.Data))}
		if base != nil && strings.EqualFold(u.Scheme, base.Scheme) && strings.EqualFold(u.Host, base.Host) {
			switch {
			case strings.HasPrefix(u.Path, "/dav-public/"):
				resource.Kind = "webdav"
				parts := strings.SplitN(strings.TrimPrefix(u.Path, "/dav-public/"), "/", 2)
				if len(parts) == 2 {
					resource.Account = parts[0]
					resource.WebDAVPath = "/" + parts[1]
				}
			case strings.HasPrefix(u.Path, "/upload-files/"):
				resource.Kind = "upload"
			case strings.HasPrefix(u.Path, "/static/"):
				resource.Kind = "static"
			default:
				resource.Kind = "other"
			}
		}
		resources = append(resources, resource)
	}
	return resources
}

func latestToolMetadata(id int64) models.ToolMetadata {
	var raw string
	var m models.ToolMetadata
	if models.DB.QueryRow("SELECT v.metadata FROM md_tool_versions v JOIN md_tool_releases p ON p.revision=v.revision WHERE p.tool_id=?", id).Scan(&raw) == nil {
		json.Unmarshal([]byte(raw), &m)
	}
	return m
}

// toolPublicationData is shared by the settings HTML and the metadata API.
func toolPublicationData(c *gin.Context, blog *models.Blog) (gin.H, error) {
	id, err := models.EnsureArticleTool(blog.BlogID, blog.MemberID)
	if err != nil {
		return nil, err
	}
	return toolPublicationDataFor(c, id, blog.BlogTitle, blog.BlogDesc)
}
func toolPublicationDataFor(c *gin.Context, id int64, title, description string) (gin.H, error) {
	var current string
	_ = models.DB.QueryRow("SELECT revision FROM md_tool_releases WHERE tool_id=?", id).Scan(&current)
	m := latestToolMetadata(id)
	if current == "" {
		var pending string
		if err := models.DB.QueryRow("SELECT metadata FROM md_tool_versions WHERE tool_id=? AND status='pending' ORDER BY created DESC,rowid DESC LIMIT 1", id).Scan(&pending); err == nil {
			if err := json.Unmarshal([]byte(pending), &m); err != nil {
				return nil, err
			}
		}
	}
	rows, err := models.DB.Query("SELECT version,revision,status,created FROM md_tool_versions WHERE tool_id=? ORDER BY created DESC,rowid DESC", id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	versions := []gin.H{}
	for rows.Next() {
		var version, revision, status string
		var created int64
		if err := rows.Scan(&version, &revision, &status, &created); err != nil {
			return nil, err
		}
		versions = append(versions, gin.H{"version": version, "revision": revision, "status": status, "created": created})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	accounts := []string{}
	for _, memberID := range m.Members {
		var account string
		if err := models.DB.QueryRow("SELECT account FROM md_members WHERE member_id=?", memberID).Scan(&account); err == nil {
			accounts = append(accounts, account)
		}
	}
	var publishedPackage string
	var publishedPermissions models.ToolPermissions
	if current != "" {
		publishedPackage = m.Package
		publishedPermissions = m.Permissions
	}
	return gin.H{"id": id, "published": current != "", "revision": current, "published_package": publishedPackage, "published_permissions": publishedPermissions, "title": title, "description": description, "metadata": m, "member_accounts": accounts, "versions": versions, "market": readMarketSettings(c), "icons": models.ToolIconOptions}, nil
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
		rows, err := models.DB.Query(`SELECT v.tool_id,v.version,v.revision,v.created,COALESCE(json_extract(v.metadata,'$.title'),b.blog_title),COALESCE(m.account,'') FROM md_tool_versions v JOIN md_tools ts USING(tool_id) LEFT JOIN md_blogs b ON b.blog_id=ts.blog_id LEFT JOIN md_members m ON m.member_id=ts.member_id WHERE v.status='pending' ORDER BY v.created`)
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
	err := models.DB.QueryRow("SELECT tool_id,metadata,content FROM md_tool_versions WHERE revision=? AND status='pending'", req.Revision).Scan(&id, &raw, &content)
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

		_, err = tx.Exec(`INSERT INTO md_tool_releases(tool_id,title,description,content,revision) VALUES(?,?,?,?,?) ON CONFLICT(tool_id) DO UPDATE SET title=excluded.title,description=excluded.description,content=excluded.content,revision=excluded.revision`, id, m.Title, m.Description, content, req.Revision)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		toolAPIError(c, err)
		return
	}
	if req.Approve && m.Package != "" {
		_ = models.PruneSupersededToolPackages(id, req.Revision, m.Package)
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
	if models.DB.QueryRow("SELECT tool_id,metadata FROM md_tool_versions WHERE revision=? AND status='published'", revision).Scan(&id, &raw) != nil {
		c.Status(404)
		return
	}
	// A withdrawn tool cannot be newly downloaded, including old versions.
	var current string
	if models.DB.QueryRow("SELECT revision FROM md_tool_releases WHERE tool_id=?", id).Scan(&current) != nil {
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
	if models.DB.QueryRow("SELECT revision FROM md_tool_releases WHERE tool_id=?", id).Scan(&current) != nil {
		c.Status(404)
		return
	}
	rows, err := models.DB.Query("SELECT metadata,created FROM md_tool_versions WHERE tool_id=? AND status='published' ORDER BY created DESC", id)
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
