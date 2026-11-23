package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type marketTool struct {
	models.ToolMetadata
	Resources   []toolpackage.Asset `json:"resources,omitempty"`
	Frozen      bool                `json:"frozen"`
	ID          int64               `json:"id"`
	Title       string              `json:"title"`
	Description string              `json:"description"`
	Author      string              `json:"author"`
	Source      string              `json:"source"`
	Revision    string              `json:"revision"`
	Content     string              `json:"content,omitempty"`
}

func ToolMarketPage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	c.HTML(http.StatusOK, "tool_market.html", commonData(c, "shares"))
}

func ToolMarketCatalog(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	if !readMarketSettings(c).Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	rows, err := models.DB.Query(`SELECT b.blog_id,p.title,p.description,COALESCE(m.account,''),
 COALESCE((SELECT s.share_identify FROM md_shares s WHERE s.share_type='blog' AND s.target_id=b.blog_id LIMIT 1),b.blog_identify),p.revision
 FROM md_tool_releases p JOIN md_blogs b ON b.blog_id=p.blog_id LEFT JOIN md_members m ON m.member_id=b.member_id
 WHERE b.editor_type='html' AND COALESCE(b.blog_type,'article')='article'
 ORDER BY b.modify_at DESC,b.blog_id DESC`)
	if err != nil {
		c.JSON(500, gin.H{"error": "catalog_unavailable"})
		return
	}
	defer rows.Close()
	items := []marketTool{}
	for rows.Next() {
		var item marketTool
		if err := rows.Scan(&item.ID, &item.Title, &item.Description, &item.Author, &item.Source, &item.Revision); err != nil {
			c.JSON(500, gin.H{"error": "catalog_unavailable"})
			return
		}
		items = append(items, item)
	}
	if rows.Err() != nil {
		c.JSON(500, gin.H{"error": "catalog_unavailable"})
		return
	}
	rows.Close()
	for i := range items {
		items[i].ToolMetadata = latestToolMetadata(items[i].ID)
		if items[i].Access == "" {
			items[i].Access = "inherit"
		}
	}
	c.JSON(200, gin.H{"tools": items})
}

func ToolMarketPackage(c *gin.Context) {
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
		if err := loadPublishedToolPackage(&item); err != nil {
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
