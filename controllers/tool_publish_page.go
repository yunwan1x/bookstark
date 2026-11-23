package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"strconv"
)

func ToolPublishPage(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.Status(404)
		return
	}
	b, err := models.GetBlogByID(id)
	if err != nil {
		c.Status(404)
		return
	}
	if !checkOwnership(c, b.MemberID) {
		forbidden(c)
		return
	}
	data := commonData(c, "shares")
	data["ToolID"] = id
	c.HTML(200, "tool_publish.html", data)
}
func ToolPublishArticles(c *gin.Context) {
	member := middleware.GetMemberID(c)
	query := `SELECT blog_id,blog_title FROM md_blogs WHERE editor_type='html' AND blog_type='article' AND COALESCE(password,'')=''`
	args := []any{}
	if !isAdmin(c) {
		query += " AND member_id=?"
		args = append(args, member)
	}
	query += " ORDER BY modify_at DESC LIMIT 300"
	rows, err := models.DB.Query(query, args...)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id int64
		var title string
		rows.Scan(&id, &title)
		items = append(items, gin.H{"id": id, "title": title})
	}
	c.JSON(200, gin.H{"articles": items})
}
