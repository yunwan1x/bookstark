package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"log"
	"net/http"
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
	c.JSON(http.StatusOK, gin.H{"code": 0, "sections": sections})
}
