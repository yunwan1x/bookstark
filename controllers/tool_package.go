package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/middleware"
	"bookstark/models"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
)

func UploadToolPackage(c *gin.Context) {
	if !canPublishTools(c) {
		c.JSON(403, gin.H{"error": "publication_forbidden"})
		return
	}
	if err := models.CleanupToolPackages(middleware.GetMemberID(c)); err != nil {
		toolAPIError(c, err)
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, toolpackage.MaxArchive+(1<<20))
	if err := c.Request.ParseMultipartForm(1 << 20); err != nil {
		c.JSON(413, gin.H{"error": "archive_too_large"})
		return
	}
	defer c.Request.MultipartForm.RemoveAll()
	file, h, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid_archive"})
		return
	}
	defer file.Close()
	if !strings.EqualFold(filepath.Ext(h.Filename), ".zip") {
		c.JSON(422, gin.H{"error": "invalid_archive"})
		return
	}
	var source models.ToolSource
	if raw := c.PostForm("tool_id"); raw != "" {
		id, e := strconv.ParseInt(raw, 10, 64)
		if e != nil {
			c.Status(400)
			return
		}
		source, e = models.GetToolSource(id)
		if e != nil || source.Kind != "package" || !checkOwnership(c, source.MemberID) {
			c.Status(403)
			return
		}
	}
	a, err := toolpackage.Unpack(file, h.Size)
	if err != nil {
		code := strings.SplitN(err.Error(), ":", 2)[0]
		c.JSON(422, gin.H{"error": code, "detail": err.Error()})
		return
	}
	if len(a.Config) > 0 {
		var metadata models.ToolMetadata
		if json.Unmarshal(a.Config, &metadata) != nil {
			c.JSON(422, gin.H{"error": "invalid_tool_manifest"})
			return
		}
	}
	if c.Request.Context().Err() != nil {
		return
	}
	owner := middleware.GetMemberID(c)
	if source.ID > 0 {
		owner = source.MemberID
	}
	p, err := models.SaveToolPackage(owner, filepath.Base(h.Filename), h.Size, a)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	committed := false
	defer func() {
		if !committed {
			_ = models.DiscardToolPackage(p.MemberID, p.Token)
		}
	}()
	if source.ID == 0 {
		r, e := models.DB.Exec(`INSERT INTO md_tools(member_id,kind,blog_id) VALUES(?,'package',NULL)`, p.MemberID)
		if e != nil {
			toolAPIError(c, e)
			return
		}
		source.ID, err = r.LastInsertId()
		if err != nil {
			toolAPIError(c, err)
			return
		}
	}
	if _, err = models.DB.Exec(`UPDATE md_tools SET package_token=? WHERE tool_id=?`, p.Token, source.ID); err != nil {
		toolAPIError(c, err)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	committed = true
	c.JSON(200, gin.H{"id": source.ID, "package": p})
}
func GetToolPackage(c *gin.Context) {
	p, err := models.GetToolPackage(c.Param("token"))
	if err != nil {
		c.Status(404)
		return
	}
	if !checkOwnership(c, p.MemberID) {
		c.Status(403)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.JSON(200, p)
}

func GetToolPackageDraftFile(c *gin.Context) {
	p, err := models.GetToolPackage(c.Param("token"))
	if err != nil {
		c.Status(404)
		return
	}
	if !checkOwnership(c, p.MemberID) {
		c.Status(403)
		return
	}
	name := strings.TrimPrefix(c.Param("filepath"), "/")
	if !toolpackage.ValidName(name) {
		c.Status(404)
		return
	}
	b, mime, err := models.ReadToolPackageFile(p, name)
	if err != nil {
		c.Status(404)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.Header("Content-Disposition", "attachment")
	c.Header("Content-Security-Policy", "sandbox")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Data(200, mime, b)
}

func ListToolPackagePublications(c *gin.Context) {
	if !canPublishTools(c) {
		c.Status(403)
		return
	}
	rows, err := models.DB.Query(`SELECT s.tool_id,s.package_token,p.metadata,COALESCE(v.metadata,'{}') FROM md_tools s JOIN md_tool_packages p ON p.token=s.package_token LEFT JOIN md_tool_releases r ON r.tool_id=s.tool_id LEFT JOIN md_tool_versions v ON v.revision=r.revision WHERE s.kind='package' AND s.member_id=? ORDER BY p.created DESC LIMIT 100`, middleware.GetMemberID(c))
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id int64
		var token, raw, release string
		if err = rows.Scan(&id, &token, &raw, &release); err != nil {
			toolAPIError(c, err)
			return
		}
		var p models.ToolPackage
		var m models.ToolMetadata
		if json.Unmarshal([]byte(raw), &p) != nil || json.Unmarshal([]byte(release), &m) != nil {
			c.Status(500)
			return
		}
		status := "draft"
		if m.Package == token {
			status = "published"
		}
		items = append(items, gin.H{"id": id, "package": token, "name": p.Name, "title": m.Title, "status": status, "created": p.Created})
	}
	if err = rows.Err(); err != nil {
		toolAPIError(c, err)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.JSON(200, gin.H{"tools": items})
}

func publicationForSource(c *gin.Context, s models.ToolSource) (gin.H, error) {
	if s.Kind == "article" {
		b, err := models.GetBlogByID(s.BlogID.Int64)
		if err != nil {
			return nil, err
		}
		return toolPublicationDataFor(c, s.ID, b.BlogTitle, b.BlogDesc)
	}
	data, err := toolPublicationDataFor(c, s.ID, "", "")
	if err != nil {
		return nil, err
	}
	token := c.Query("package")
	m := data["metadata"].(models.ToolMetadata)
	if token == "" {
		token = m.Package
		if token == "" {
			token = s.Package
		}
	}
	p, err := models.GetToolPackage(token)
	if err != nil {
		return nil, err
	}
	if !checkOwnership(c, p.MemberID) {
		return nil, models.ErrToolPermission
	}
	previousPermissions := m.Permissions
	if m.Version == "" {
		m = models.ToolMetadata{Category: "other", Access: "public", Version: "1.0.0", Permissions: models.ToolPermissions{Schema: 1}}
	}
	if len(p.Config) > 0 && (m.Package != p.Token || m.Status == "") {
		if err = json.Unmarshal(p.Config, &m); err != nil {
			return nil, err
		}
	}
	if len(p.Config) > 0 {
		var manifest struct {
			Version string `json:"version"`
		}
		if json.Unmarshal(p.Config, &manifest) == nil {
			data["manifest_version"] = manifest.Version
		}
	}
	data["permissions_changed"] = len(data["versions"].([]gin.H)) > 0 && !previousPermissions.SameManaged(m.Permissions)

	if m.Title == "" {
		m.Title = strings.TrimSuffix(p.Name, filepath.Ext(p.Name))
	}
	m.SourceKind = "package"
	m.Distribution = "files"
	m.Package = p.Token
	m.Entry = p.Entry
	if entry := c.Query("entry"); entry != "" {
		for _, e := range p.Entries {
			if e == entry {
				m.Entry = entry
			}
		}
	}
	data["metadata"] = m
	data["package"] = p
	data["title"] = m.Title
	data["description"] = m.Description
	return data, nil
}

// The random package URL is handed out only with an authorized content manifest.
// Recheck visibility on each request, including both current and historical policy.
func ServePublishedToolPackage(c *gin.Context) {
	token := c.Param("token")
	var raw, current string
	err := models.DB.QueryRow(`SELECT v.metadata,cv.metadata FROM md_tool_versions v JOIN md_tool_releases r USING(tool_id) JOIN md_tool_versions cv ON cv.revision=r.revision WHERE json_extract(v.metadata,'$.package')=? AND v.revision=? AND v.status='published'`, token, c.Query("revision")).Scan(&raw, &current)
	if err != nil {
		c.Status(404)
		return
	}
	var m, latest models.ToolMetadata
	if json.Unmarshal([]byte(raw), &m) != nil || json.Unmarshal([]byte(current), &latest) != nil {
		c.Status(500)
		return
	}
	if !mayInstallTool(c, latest) || !mayInstallTool(c, m) {
		return
	}
	p, err := models.GetToolPackage(token)
	if err != nil {
		c.Status(404)
		return
	}
	name := strings.TrimPrefix(c.Param("filepath"), "/")
	if !toolpackage.ValidName(name) {
		c.Status(404)
		return
	}
	b, mime, err := models.ReadToolPackageFile(p, name)
	if err != nil {
		c.Status(404)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.Header("Access-Control-Allow-Origin", "*")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Content-Security-Policy", "sandbox")
	c.Data(200, mime, b)
}
