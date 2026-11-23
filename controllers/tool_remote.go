package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"context"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"net/url"
	"strconv"
	"strings"
)

func loadPublishedTool(id int64) (marketTool, error) {
	var t marketTool
	var raw string
	err := models.DB.QueryRow(`SELECT b.blog_id,p.title,p.description,COALESCE(m.account,''),COALESCE((SELECT share_identify FROM md_shares WHERE share_type='blog' AND target_id=b.blog_id LIMIT 1),b.blog_identify),p.content,p.revision FROM md_tool_releases p JOIN md_blogs b ON b.blog_id=p.blog_id LEFT JOIN md_members m ON m.member_id=b.member_id WHERE b.blog_id=? AND b.visibility=1 AND COALESCE(b.password,'')='' AND b.editor_type='html' AND COALESCE(b.blog_type,'article')='article'`, id).Scan(&t.ID, &t.Title, &t.Description, &t.Author, &t.Source, &raw, &t.Revision)
	if err != nil {
		return t, err
	}
	t.Content, err = decodeMarketContent(raw)
	return t, err
}
func remoteTool(ctx context.Context, member, id int64) (marketTool, string, error) {
	var origin string
	var remoteID int64
	var t marketTool
	err := models.DB.QueryRow("SELECT origin,remote_id FROM md_tool_remote_sources WHERE member_id=? AND id=?", member, -id).Scan(&origin, &remoteID)
	if err != nil {
		return t, "", err
	}
	u, _ := url.Parse(origin + "/api/tool-market/" + strconv.FormatInt(remoteID, 10))
	data, _, err := fetchToolURL(ctx, u)
	if err != nil {
		return t, "", err
	}
	if err = json.Unmarshal(data, &t); err != nil {
		return t, "", err
	}
	if t.ID != remoteID || t.Revision == "" || t.Content == "" {
		return t, "", fmt.Errorf("invalid remote tool")
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
	u, err := url.Parse(strings.TrimRight(req.Server, "/"))
	if err != nil || u.Host == "" || u.User != nil || (u.Scheme != "http" && u.Scheme != "https") || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		c.Status(400)
		return
	}
	origin := u.Scheme + "://" + u.Host
	u.Path = "/api/tool-market"
	data, _, err := fetchToolURL(c.Request.Context(), u)
	if err != nil {
		c.JSON(502, gin.H{"error": "catalog_unavailable"})
		return
	}
	var result struct {
		Tools []marketTool `json:"tools"`
	}
	if json.Unmarshal(data, &result) != nil || len(result.Tools) > 10000 {
		c.Status(502)
		return
	}
	member := middleware.GetMemberID(c)
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
func RemoteToolPackage(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok || id >= 0 {
		c.Status(404)
		return
	}
	t, _, err := remoteTool(c.Request.Context(), member, id)
	if err != nil {
		c.Status(502)
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(200, t)
}
