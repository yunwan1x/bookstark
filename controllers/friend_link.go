package controllers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

func ListFriendLinks(c *gin.Context) {
	items, err := models.ListFriendLinks()
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取友情链接失败")
		return
	}
	apiSuccess(c, gin.H{"items": items})
}

func ReplaceFriendLinks(c *gin.Context) {
	var req struct {
		Items []models.FriendLink `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式不正确")
		return
	}

	for _, item := range req.Items {
		if len(item.LinkName) > 100 {
			apiError(c, http.StatusBadRequest, "链接名称不能超过100个字符")
			return
		}
		if len(item.LinkURL) > 2048 {
			apiError(c, http.StatusBadRequest, "链接地址不能超过2048个字符")
			return
		}
	}

	memberID := middleware.GetMemberID(c)
	if err := models.ReplaceFriendLinks(req.Items, memberID); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	apiSuccessMsg(c, "保存成功")
}
