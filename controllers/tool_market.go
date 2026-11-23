package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type marketTool struct {
	models.ToolMetadata
	ResourceBase string `json:"resource_base,omitempty"`
	ID           int64  `json:"id"`
	Title        string `json:"title"`
	Description  string `json:"description"`
	Author       string `json:"author"`
	Source       string `json:"source"`
	Revision     string `json:"revision"`
	Content      string `json:"content,omitempty"`
}

func ToolMarketPage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "shares")
	data["Type"] = "tool"
	data["CanConfigureTools"] = isAdmin(c)
	data["CanPublishTools"] = middleware.GetMemberID(c) > 0 && readMarketSettings(c).Enabled && (isAdmin(c) || readMarketSettings(c).MembersPublish)
	c.HTML(http.StatusOK, "tool_market.html", data)
}

func ToolMarketCatalog(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	if !readMarketSettings(c).Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	rows, err := models.DB.Query(`SELECT b.blog_id,p.title,p.description,COALESCE(m.account,''),
 COALESCE((SELECT s.share_identify FROM md_shares s WHERE s.share_type='blog' AND s.target_id=b.blog_id LIMIT 1),b.blog_identify),p.revision,v.metadata,v.created
 FROM md_tool_releases p JOIN md_blogs b ON b.blog_id=p.blog_id JOIN md_tool_versions v ON v.revision=p.revision AND v.status='published' LEFT JOIN md_members m ON m.member_id=b.member_id
 WHERE b.editor_type='html' AND COALESCE(b.blog_type,'article')='article'
 ORDER BY v.created DESC,b.blog_id DESC`)
	if err != nil {
		c.JSON(500, gin.H{"error": "catalog_unavailable"})
		return
	}
	defer rows.Close()
	items := []marketTool{}
	for rows.Next() {
		var item marketTool
		var raw string
		var updated int64
		if err := rows.Scan(&item.ID, &item.Title, &item.Description, &item.Author, &item.Source, &item.Revision, &raw, &updated); err != nil {
			c.JSON(500, gin.H{"error": "catalog_unavailable"})
			return
		}
		if err := json.Unmarshal([]byte(raw), &item.ToolMetadata); err != nil {
			toolAPIError(c, err)
			return
		}
		item.Updated = updated
		items = append(items, item)
	}
	if rows.Err() != nil {
		c.JSON(500, gin.H{"error": "catalog_unavailable"})
		return
	}
	rows.Close()
	c.JSON(200, gin.H{"tools": items, "market": gin.H{"name": readMarketSettings(c).Name}})
}

func ToolMarketItem(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.Status(404)
		return
	}
	item, err := loadPublishedTool(id)
	if err != nil {
		c.Status(404)
		return
	}
	if !mayInstallTool(c, item.ToolMetadata) {
		return
	}
	if c.Query("metadata") != "1" {
		if err := loadPublishedToolContent(&item); err != nil {
			c.Status(404)
			return
		}
	}
	c.JSON(200, item)
}

func decodeMarketContent(raw string) (string, error) {
	const maxSize = 20 << 20
	if !models.IsCompressedContent(raw) {
		if len(raw) > maxSize {
			return "", fmt.Errorf("package too large")
		}
		return raw, nil
	}
	data, err := models.CompressedContentGzipBytes(raw)
	if err != nil {
		return "", err
	}
	reader, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	defer reader.Close()
	content, err := io.ReadAll(io.LimitReader(reader, maxSize+1))
	if err != nil {
		return "", err
	}
	if len(content) > maxSize {
		return "", fmt.Errorf("package too large")
	}
	return string(content), nil
}
