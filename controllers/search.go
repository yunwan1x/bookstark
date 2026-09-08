package controllers

import (
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

// SearchPage renders the search results page.
func SearchPage(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	data := commonData(c, "search")
	data["Keyword"] = q
	c.HTML(http.StatusOK, "search.html", data)
}

// SearchAPI handles GET /api/search?q=xxx
func SearchAPI(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		apiError(c, http.StatusBadRequest, "请输入搜索词")
		return
	}
	if len(q) > 100 {
		q = q[:100]
	}

	memberID := middleware.GetMemberID(c)
	result, err := models.GlobalSearch(memberID, q)
	if err != nil {
		log.Printf("SearchAPI: GlobalSearch failed: %v", err)
		apiError(c, http.StatusInternalServerError, "搜索失败")
		return
	}

	apiSuccess(c, result)
}