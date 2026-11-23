package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/middleware"
	"bookstark/models"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"net/url"
	"reflect"
	"regexp"
	"strconv"
	"strings"
)

func loadPublishedTool(id int64) (marketTool, error) {
	var t marketTool
	var raw string
	err := models.DB.QueryRow(`SELECT b.blog_id,p.title,p.description,COALESCE(m.account,''),COALESCE((SELECT share_identify FROM md_shares WHERE share_type='blog' AND target_id=b.blog_id LIMIT 1),b.blog_identify),p.revision,COALESCE(v.metadata,''),v.revision IS NOT NULL AND COALESCE(v.resource_base,'')='',COALESCE(v.resource_base,'') FROM md_tool_releases p JOIN md_blogs b ON b.blog_id=p.blog_id LEFT JOIN md_members m ON m.member_id=b.member_id LEFT JOIN md_tool_versions v ON v.revision=p.revision AND v.status='published' WHERE b.blog_id=? AND b.editor_type='html' AND COALESCE(b.blog_type,'article')='article'`, id).Scan(&t.ID, &t.Title, &t.Description, &t.Author, &t.Source, &t.Revision, &raw, &t.Frozen, &t.ResourceBase)
	if err != nil {
		return t, err
	}
	if raw != "" {
		if err := json.Unmarshal([]byte(raw), &t.ToolMetadata); err != nil {
			return t, err
		}
	}
	return t, nil
}

// Call only after the request has passed the tool's installation policy. In
// particular, metadata-only requests never read or inflate the resource bundle.
func loadPublishedToolPackage(t *marketTool) error {
	var data []byte
	if t.Frozen {
		if err := models.DB.QueryRow("SELECT package FROM md_tool_versions WHERE revision=? AND status='published'", t.Revision).Scan(&data); err != nil {
			return err
		}
		bundle, e := decodeToolBundle(data)
		if e != nil {
			return e
		}
		t.Content = bundle.Content
		t.Resources = bundle.Assets
		return nil
	}
	var raw string
	if t.ResourceBase != "" {
		if err := models.DB.QueryRow("SELECT content FROM md_tool_versions WHERE revision=? AND status='published'", t.Revision).Scan(&raw); err != nil {
			return err
		}
	} else if err := models.DB.QueryRow("SELECT content FROM md_tool_releases WHERE blog_id=? AND revision=?", t.ID, t.Revision).Scan(&raw); err != nil {
		return err
	}

	var err error
	t.Content, err = decodeMarketContent(raw)
	return err
}
func remoteTool(ctx context.Context, member, id int64, withAssets ...bool) (marketTool, string, error) {
	includeAssets := len(withAssets) == 0 || withAssets[0]
	var origin string
	var remoteID int64
	var t marketTool
	err := models.DB.QueryRow("SELECT origin,remote_id FROM md_tool_remote_sources WHERE member_id=? AND id=?", member, -id).Scan(&origin, &remoteID)
	if err != nil {
		return t, "", err
	}
	u, _ := url.Parse(origin + "/api/tool-market/" + strconv.FormatInt(remoteID, 10))
	data, status, err := requestMarket(ctx, origin, u.RequestURI()+"?metadata=1", "GET", nil, clientMarketToken(member, origin))
	if err == nil && status != 200 {
		return t, "", fmt.Errorf("market_status_%d", status)
	}
	if err != nil {
		return t, "", err
	}
	if err = json.Unmarshal(data, &t); err != nil {
		return t, "", err
	}
	if t.ID != remoteID || t.Revision == "" {
		return t, "", fmt.Errorf("invalid remote tool")
	}
	if !t.Frozen && (t.Version != "" || t.Hash != "") && t.Distribution != "references" {
		return t, "", fmt.Errorf("invalid tool distribution")
	}
	if !t.Frozen && includeAssets && t.Content == "" {
		// Upgraded servers still expose legacy releases. Their metadata response
		// intentionally omits HTML; fetch it only for an actual installation.
		var legacy marketTool
		data, status, err = requestMarket(ctx, origin, u.RequestURI(), "GET", nil, clientMarketToken(member, origin))
		if err != nil {
			return t, "", err
		}
		if status != 200 {
			return t, "", fmt.Errorf("market_status_%d", status)
		}
		if json.Unmarshal(data, &legacy) != nil || legacy.ID != remoteID || legacy.Revision != t.Revision || legacy.Frozen || legacy.Content == "" {
			return t, "", fmt.Errorf("invalid legacy tool")
		}
		if t.Distribution == "references" {
			if legacy.Hash != t.Hash || legacy.ResourceBase == "" || legacy.Version != t.Version || legacy.Permissions != t.Permissions || legacy.Access != t.Access || !reflect.DeepEqual(legacy.Members, t.Members) {
				return t, "", fmt.Errorf("reference manifest mismatch")
			}
			t.ResourceBase = legacy.ResourceBase
		}
		t.Content = legacy.Content
	}
	if t.Frozen && includeAssets {
		if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(t.Revision) {
			return t, "", fmt.Errorf("invalid revision")
		}
		packed, status, e := requestMarket(ctx, origin, "/market/packages/"+t.Revision, "GET", nil, clientMarketToken(member, origin))
		if e != nil {
			return t, "", e
		}
		if status != 200 {
			return t, "", fmt.Errorf("market_status_%d", status)
		}
		if fmt.Sprintf("%x", sha256.Sum256(packed)) != t.Hash {
			return t, "", fmt.Errorf("invalid package digest")
		}
		bundle, e := decodeToolBundle(packed)
		if e != nil {
			return t, "", e
		}
		if bundle.Version != t.Version || bundle.Permissions != t.Permissions || bundle.Access != t.Access || !reflect.DeepEqual(bundle.Members, t.Members) {
			return t, "", fmt.Errorf("package policy mismatch")
		}
		t.Content = bundle.Content
		t.Resources = bundle.Assets
	}
	if includeAssets && t.Distribution == "references" {
		digest, e := referenceDigest(t)
		if e != nil || digest != t.Hash || t.ResourceBase == "" {
			return t, "", fmt.Errorf("reference manifest mismatch")
		}
	}
	if err := validateFrozenTool(t); includeAssets && err != nil {
		return t, "", err
	}
	if !includeAssets {
		t.Content = ""
		t.Resources = nil
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
		Tools []marketTool `json:"tools"`
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
func RemoteToolPackage(c *gin.Context) {
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
func validateFrozenTool(t marketTool) error {
	if len(t.Content) > 20<<20 {
		return fmt.Errorf("invalid tool HTML size")
	}
	if !t.Frozen {
		return nil
	}
	if len(t.Resources) > toolpackage.MaxFiles {
		return fmt.Errorf("invalid package")
	}
	names := map[string]bool{}
	total := 0
	for _, a := range t.Resources {
		if !regexp.MustCompile(`^[a-f0-9]{64}(\.[a-zA-Z0-9_-]{1,12})?$`).MatchString(a.Name) || names[a.Name] || len(a.Data) > toolpackage.MaxFile || len(a.MIME) > 255 || strings.ContainsAny(a.MIME, "\r\n") {
			return fmt.Errorf("invalid asset")
		}
		names[a.Name] = true
		total += len(a.Data)
	}
	if total > toolpackage.MaxBytes {
		return fmt.Errorf("package too large")
	}
	return nil
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
