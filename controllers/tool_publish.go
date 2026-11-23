package controllers

import (
	"bookstark/models"
	"crypto/sha256"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"strconv"
)

func PublishMarketTool(c *gin.Context) {
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
	if c.Request.Method == "GET" {
		var revision string
		_ = models.DB.QueryRow("SELECT revision FROM md_tool_releases WHERE blog_id=?", id).Scan(&revision)
		c.JSON(200, gin.H{"published": revision != "", "revision": revision})
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
	if blog.EditorType != "html" || blog.BlogType != "article" || blog.Visibility != 1 || blog.Password != "" {
		c.JSON(422, gin.H{"error": "publish_requires_public_html"})
		return
	}
	if _, err = decodeMarketContent(blog.BlogContent); err != nil {
		c.JSON(422, gin.H{"error": "invalid_package"})
		return
	}
	// Each explicit publication changes the revision, including resource-only updates.
	revision := fmt.Sprintf("%x", sha256.Sum256([]byte(blog.BlogContent+blog.BlogTitle+blog.BlogDesc+uuid.NewString())))
	_, err = models.DB.Exec(`INSERT INTO md_tool_releases(blog_id,title,description,content,revision) VALUES(?,?,?,?,?) ON CONFLICT(blog_id) DO UPDATE SET title=excluded.title,description=excluded.description,content=excluded.content,revision=excluded.revision`, id, blog.BlogTitle, blog.BlogDesc, blog.BlogContent, revision)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"ok": true, "revision": revision})
}
