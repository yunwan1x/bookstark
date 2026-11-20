package controllers

import (
	"github.com/gin-gonic/gin"
	"net/http"
)

// LocalToolsPage serves editors only. Drafts and embedded images never reach a write API.
func LocalToolsPage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "shares")
	data["AIEnabled"] = false
	c.HTML(http.StatusOK, "local_tools.html", data)
}
