package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"log"
	"net/http"
)

func recordRecentContent(c *gin.Context, kind string, id int64, share string) {
	memberID := middleware.GetMemberID(c)
	if memberID <= 0 {
		return
	}
	c.Header("Cache-Control", "private, no-store")
	if err := models.RecordRecentContent(memberID, kind, id, share); err != nil {
		// History must never prevent the original content from opening.
		log.Printf("record recent content: %v", err)
	}
}

func ClearHomeRecent(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	if err := models.ClearRecentContent(middleware.GetMemberID(c)); err != nil {
		apiError(c, http.StatusInternalServerError, "Could not clear recent content")
		return
	}
	apiSuccess(c, gin.H{})
}
