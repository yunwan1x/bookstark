package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"net/http"
	"net/url"
	"strconv"

	"github.com/gin-gonic/gin"
)

func ToolRuntimePage(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id == 0 {
		c.Status(http.StatusNotFound)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	if middleware.GetMemberID(c) <= 0 {
		c.Redirect(http.StatusFound, "/login?next="+url.QueryEscape(c.Request.URL.RequestURI()))
		return
	}
	data := commonData(c, "tools")
	data["Background"] = nil
	data["ToolID"] = id
	// Read only the installed tool summary, without embedding its HTML or values.
	if tool, err := models.GetInstalledTool(middleware.GetMemberID(c), id); err == nil {
		data["RuntimeName"] = tool.Title
		icon, style, color := models.ResolveToolAppearance(tool.ToolMetadata)
		data["RuntimeAppearance"] = gin.H{"Class": "fa-" + style + " fa-" + icon, "Color": color, "Background": color + "18"}
	}
	c.HTML(http.StatusOK, "tool_runtime.html", data)
}
