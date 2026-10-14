package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"log"
	"net/http"
	"time"
)

func PersonalHomePage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	c.HTML(http.StatusOK, "home.html", commonData(c, "home"))
}

func HomeSummary(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	order := c.DefaultQuery("order", "updated")
	if order != "updated" && order != "created" {
		apiError(c, http.StatusBadRequest, "不支持的排序方式")
		return
	}
	sections, err := models.ListHomeSections(middleware.GetMemberID(c), isAdmin(c), order)
	if err != nil {
		log.Printf("home summary: %v", err)
		apiError(c, http.StatusInternalServerError, "首页加载失败，请重试")
		return
	}
	layout, err := models.GetHomeLayout(middleware.GetMemberID(c))
	if err != nil {
		log.Printf("home layout: %v", err)
		apiError(c, http.StatusInternalServerError, "首页加载失败，请重试")
		return
	}
	stats, err := models.GetHomeStats(middleware.GetMemberID(c), time.Now())
	if err != nil {
		log.Printf("home stats: %v", err)
		apiError(c, http.StatusInternalServerError, "首页加载失败，请重试")
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "sections": sections, "layout": layout, "stats": stats})
}

func SaveHomeLayout(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 8192)
	var req struct {
		Layout []models.HomeLayoutItem `json:"layout"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Layout == nil {
		apiError(c, http.StatusBadRequest, "Invalid home layout")
		return
	}
	layout, err := models.NormalizeHomeLayout(req.Layout)
	if err != nil {
		apiError(c, http.StatusBadRequest, "Invalid home layout")
		return
	}
	if err = models.SaveHomeLayout(middleware.GetMemberID(c), layout); err != nil {
		log.Printf("save home layout: %v", err)
		apiError(c, http.StatusInternalServerError, "Could not save home layout")
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "layout": layout})
}
