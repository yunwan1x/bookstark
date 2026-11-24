package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/middleware"
	"bookstark/models"
	"bytes"
	"compress/gzip"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"

	"github.com/gin-gonic/gin"
)

type marketTool struct {
	models.ToolMetadata
	PublishURL   string             `json:"publish_url,omitempty"`
	Owner        int64              `json:"-"`
	ArticleID    sql.NullInt64      `json:"-"`
	Files        []toolpackage.File `json:"files,omitempty"`
	ResourceBase string             `json:"resource_base,omitempty"`
	ID           int64              `json:"id"`
	Title        string             `json:"title"`
	Description  string             `json:"description"`
	Author       string             `json:"author"`
	Source       string             `json:"source"`
	Revision     string             `json:"revision"`
	Content      string             `json:"content,omitempty"`
}

func canPublishTools(c *gin.Context) bool {
	settings := readMarketSettings(c)
	return middleware.GetMemberID(c) > 0 && settings.Enabled && (isAdmin(c) || settings.MembersPublish)
}

func ToolMarketPage(c *gin.Context) {
	if raw, exists := c.GetQuery("open"); exists {
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || id == 0 {
			c.Status(http.StatusNotFound)
			return
		}
		query := c.Request.URL.Query()
		query.Del("open")
		query.Del("return")
		back := "/market"
		if query.Encode() != "" {
			back += "?" + query.Encode()
		}
		c.Header("Cache-Control", "private, no-store")
		c.Redirect(http.StatusFound, "/tools/run/"+strconv.FormatInt(id, 10)+"?return="+url.QueryEscape(back))
		return
	}
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "shares")
	data["Type"] = "tool"
	data["Background"] = nil
	data["LoginURL"] = "/login?next=" + url.QueryEscape(c.Request.URL.RequestURI())
	addPublicWidgetData(data, true)
	data["CanConfigureTools"] = isAdmin(c)
	data["CanPublishTools"] = canPublishTools(c)
	c.HTML(http.StatusOK, "tool_market.html", data)
}

func ToolMarketCatalog(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	if !readMarketSettings(c).Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	rows, err := models.DB.Query(publishedToolSelect + " ORDER BY v.created DESC,ts.tool_id DESC")
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
		if err := rows.Scan(&item.Owner, &item.ArticleID, &item.ID, &item.Title, &item.Description, &item.Author, &item.Source, &item.Revision, &raw, &item.ResourceBase, &updated); err != nil {
			c.JSON(500, gin.H{"error": "catalog_unavailable"})
			return
		}
		if err := json.Unmarshal([]byte(raw), &item.ToolMetadata); err != nil {
			toolAPIError(c, err)
			return
		}
		item.Updated = updated
		item.Package = ""
		item.ResourceBase = ""
		if canPublishTools(c) && checkOwnership(c, item.Owner) {
			if item.SourceKind == "package" {
				item.PublishURL = "/market/packages/" + strconv.FormatInt(item.ID, 10)
			} else {
				item.PublishURL = "/market/publish/" + strconv.FormatInt(item.ArticleID.Int64, 10)
			}
		}
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
