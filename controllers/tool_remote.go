package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"context"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"net/url"
	"reflect"
	"strconv"
	"strings"
)

func loadPublishedTool(id int64) (marketTool, error) {
	var t marketTool
	var raw string
	err := models.DB.QueryRow(`SELECT b.blog_id,p.title,p.description,COALESCE(m.account,''),COALESCE((SELECT share_identify FROM md_shares WHERE share_type='blog' AND target_id=b.blog_id LIMIT 1),b.blog_identify),p.revision,v.metadata,v.resource_base,v.created FROM md_tool_releases p JOIN md_blogs b ON b.blog_id=p.blog_id JOIN md_tool_versions v ON v.revision=p.revision AND v.status='published' LEFT JOIN md_members m ON m.member_id=b.member_id WHERE b.blog_id=? AND b.editor_type='html' AND COALESCE(b.blog_type,'article')='article'`, id).Scan(&t.ID, &t.Title, &t.Description, &t.Author, &t.Source, &t.Revision, &raw, &t.ResourceBase, &t.Updated)
	if err != nil {
		return t, err
	}
	updated := t.Updated
	err = json.Unmarshal([]byte(raw), &t.ToolMetadata)
	t.Updated = updated
	return t, err
}

// Read HTML only after checking the installation policy. Metadata requests never
// load the article body or download any of its referenced resources.
func loadPublishedToolContent(t *marketTool) error {
	if err := models.DB.QueryRow("SELECT content FROM md_tool_versions WHERE revision=? AND status='published'", t.Revision).Scan(&t.Content); err != nil {
		return err
	}
	if len(t.Content) > 20<<20 {
		return fmt.Errorf("invalid tool HTML size")
	}
	return nil
}

func remoteTool(ctx context.Context, member, id int64, withContent ...bool) (marketTool, string, error) {
	includeContent := len(withContent) == 0 || withContent[0]
	var origin string
	var remoteID int64
	var t marketTool
	if err := models.DB.QueryRow("SELECT origin,remote_id FROM md_tool_remote_sources WHERE member_id=? AND id=?", member, -id).Scan(&origin, &remoteID); err != nil {
		return t, "", err
	}
	endpoint := "/api/tool-market/" + strconv.FormatInt(remoteID, 10)
	data, status, err := requestMarket(ctx, origin, endpoint+"?metadata=1", "GET", nil, clientMarketToken(member, origin))
	if err != nil {
		return t, "", err
	}
	if status != 200 {
		return t, "", fmt.Errorf("market_status_%d", status)
	}
	if err := json.Unmarshal(data, &t); err != nil {
		return t, "", err
	}
	if t.ID != remoteID || t.Distribution != "references" || !toolSemver.MatchString(t.Version) || len(t.Version) > 64 || !toolDigest.MatchString(t.Revision) || !toolDigest.MatchString(t.Hash) {
		return t, "", fmt.Errorf("invalid reference manifest")
	}
	if includeContent && t.Content == "" {
		var full marketTool
		data, status, err = requestMarket(ctx, origin, endpoint, "GET", nil, clientMarketToken(member, origin))
		if err != nil {
			return t, "", err
		}
		if status != 200 {
			return t, "", fmt.Errorf("market_status_%d", status)
		}
		if json.Unmarshal(data, &full) != nil || full.ID != remoteID || full.Revision != t.Revision || full.Distribution != "references" || full.Hash != t.Hash || full.Version != t.Version || full.Permissions != t.Permissions || full.Access != t.Access || !reflect.DeepEqual(full.Members, t.Members) {
			return t, "", fmt.Errorf("reference manifest mismatch")
		}
		t.Content, t.ResourceBase = full.Content, full.ResourceBase
	}
	if includeContent {
		if len(t.Content) > 20<<20 {
			return t, "", fmt.Errorf("invalid tool HTML size")
		}
		digest, e := referenceDigest(t)
		if e != nil || digest != t.Hash || t.ResourceBase == "" {
			return t, "", fmt.Errorf("reference manifest mismatch")
		}
	} else {
		t.Content = ""
	}
	t.ID = id
	t.Source = origin + "/shares/" + url.PathEscape(t.Source)
	return t, origin, nil
}

// Catalog IDs are mapped per account and origin, preventing cross-server ID collisions.
func RemoteToolCatalog(c *gin.Context) {
	var req struct {
		Server string `json:"server"`
	}
	if c.ShouldBindJSON(&req) != nil {
		c.Status(400)
		return
	}
	origin, err := normalizeMarketURL(req.Server)
	if err != nil {
		c.Status(400)
		return
	}
	member := middleware.GetMemberID(c)
	data, status, err := requestMarket(c.Request.Context(), origin, "/api/tool-market", "GET", nil, clientMarketToken(member, origin))
	if err != nil || status != 200 {
		c.JSON(502, gin.H{"error": "catalog_unavailable"})
		return
	}
	var result struct {
		Tools  []marketTool      `json:"tools"`
		Market map[string]string `json:"market"`
	}
	if json.Unmarshal(data, &result) != nil || len(result.Tools) > 10000 {
		c.Status(502)
		return
	}
	for i := range result.Tools {
		t := &result.Tools[i]
		remoteID := t.ID
		if remoteID <= 0 || t.Revision == "" {
			c.Status(502)
			return
		}
		_, err = models.DB.Exec("INSERT OR IGNORE INTO md_tool_remote_sources(member_id,origin,remote_id) VALUES(?,?,?)", member, origin, remoteID)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		err = models.DB.QueryRow("SELECT id FROM md_tool_remote_sources WHERE member_id=? AND origin=? AND remote_id=?", member, origin, remoteID).Scan(&t.ID)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		t.ID = -t.ID
		t.Source = origin + "/shares/" + url.PathEscape(t.Source)
		t.Content = ""
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(200, result)
}
func RemoteToolItem(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok || id >= 0 {
		c.Status(404)
		return
	}
	t, _, err := remoteTool(c.Request.Context(), member, id, c.Query("metadata") != "1")
	if err != nil {
		remoteMarketError(c, err)
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(200, t)
}

func remoteMarketError(c *gin.Context, err error) {
	if strings.Contains(err.Error(), "401") {
		c.JSON(401, gin.H{"error": "market_login_required"})
	} else if strings.Contains(err.Error(), "403") {
		c.JSON(403, gin.H{"error": "market_forbidden"})
	} else {
		c.JSON(502, gin.H{"error": "catalog_unavailable"})
	}
}
func RemoteToolHistory(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok || id >= 0 {
		c.Status(404)
		return
	}
	var origin string
	var remoteID int64
	if models.DB.QueryRow("SELECT origin,remote_id FROM md_tool_remote_sources WHERE member_id=? AND id=?", member, -id).Scan(&origin, &remoteID) != nil {
		c.Status(404)
		return
	}
	data, status, err := requestMarket(c.Request.Context(), origin, "/api/tool-market/"+strconv.FormatInt(remoteID, 10)+"/history", "GET", nil, clientMarketToken(member, origin))
	if err != nil || status != 200 {
		c.Status(502)
		return
	}
	var result struct {
		Versions []struct {
			Version string `json:"version"`
			Notes   string `json:"notes"`
			Size    int64  `json:"size"`
			Created int64  `json:"created"`
		} `json:"versions"`
	}
	if json.Unmarshal(data, &result) != nil || len(result.Versions) > 1000 {
		c.Status(502)
		return
	}
	c.JSON(200, result)
}
