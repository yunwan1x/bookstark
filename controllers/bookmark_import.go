package controllers

import (
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/models"
)

func ImportBookmarkHTML(c *gin.Context) {
	memberIDStr := c.PostForm("member_id")
	memberID, err := strconv.ParseInt(memberIDStr, 10, 64)
	if err != nil || memberID <= 0 {
		apiError(c, http.StatusBadRequest, "请选择目标用户")
		return
	}

	var status int
	err = models.DB.QueryRow("SELECT status FROM md_members WHERE member_id = ?", memberID).Scan(&status)
	if err != nil || status != 1 {
		apiError(c, http.StatusBadRequest, "目标用户不存在或未通过审批")
		return
	}

	file, _, err := c.Request.FormFile("file")
	if err != nil {
		apiError(c, http.StatusBadRequest, "请上传书签 HTML 文件")
		return
	}
	defer file.Close()

	bookmarks, err := models.ParseBookmarkHTML(file)
	if err != nil {
		apiError(c, http.StatusBadRequest, "解析书签文件失败："+err.Error())
		return
	}
	if len(bookmarks) == 0 {
		apiError(c, http.StatusBadRequest, "未在文件中找到有效的书签")
		return
	}

	var customTime time.Time
	if dateStr := c.PostForm("custom_date"); dateStr != "" {
		t, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			apiError(c, http.StatusBadRequest, "日期格式无效，请使用 YYYY-MM-DD 格式")
			return
		}
		customTime = t
	}

	result, err := models.ImportBookmarks(bookmarks, memberID, customTime)
	if err != nil {
		log.Printf("ImportBookmarkHTML: %v", err)
		apiError(c, http.StatusInternalServerError, "导入书签失败")
		return
	}

	apiSuccess(c, result)
}