package controllers

import (
	"bookstark/i18n"
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"log"
	"net/http"
	"strconv"
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
	today := time.Now().Format("2006-01-02")
	start, end := c.DefaultQuery("start", today), c.DefaultQuery("end", today)
	from, err1 := time.ParseInLocation("2006-01-02", start, time.Local)
	to, err2 := time.ParseInLocation("2006-01-02", end, time.Local)
	limit, err3 := strconv.Atoi(c.DefaultQuery("limit", "10"))
	month := c.DefaultQuery("month", time.Now().Format("2006-01"))
	_, err4 := time.Parse("2006-01", month)
	if err1 != nil || err2 != nil || err3 != nil || err4 != nil || from.After(to) || to.Sub(from) > 366*24*time.Hour || (limit != 5 && limit != 10 && limit != 20 && limit != 50) {
		apiError(c, http.StatusBadRequest, i18n.T(i18n.GetLang(c), "home.invalid_filter"))
		return
	}
	sections, err := models.ListHomeSections(middleware.GetMemberID(c), isAdmin(c), order, models.HomeFilter{Start: start, End: end, Month: month, Limit: limit, Location: time.Local})
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
	c.JSON(http.StatusOK, gin.H{"code": 0, "sections": sections, "layout": layout, "start": start, "end": end, "limit": limit})
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
