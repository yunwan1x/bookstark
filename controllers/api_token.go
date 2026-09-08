package controllers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

// ListApiTokens 列出当前用户的 API Token
func ListApiTokens(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	tokens, err := models.ListApiTokensByMember(memberID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取 Token 列表失败")
		return
	}
	if tokens == nil {
		tokens = []models.ApiToken{}
	}
	apiSuccess(c, tokens)
}

// CreateApiToken 创建 API Token
func CreateApiToken(c *gin.Context) {
	var req struct {
		Name string `json:"name"`
	}
	c.ShouldBindJSON(&req)

	if len(req.Name) > 100 {
		apiError(c, http.StatusBadRequest, "Token名称不能超过100个字符")
		return
	}

	memberID := middleware.GetMemberID(c)
	token, err := models.CreateApiToken(memberID, req.Name)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "创建 Token 失败")
		return
	}
	// 使该用户相关的缓存失效（新 Token 不在缓存中，但为安全起见清除）
	models.InvalidateApiTokenCache(token.Token)
	apiSuccess(c, gin.H{"data": token, "token": token.Token})
}

// DeleteApiToken 删除 API Token
func DeleteApiToken(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效的 Token ID")
		return
	}

	memberID := middleware.GetMemberID(c)
	// 先查询 token 字符串，用于清除缓存
	token, _ := models.GetApiTokenByID(id, memberID)
	if err := models.DeleteApiToken(id, memberID); err != nil {
		apiError(c, http.StatusInternalServerError, "删除 Token 失败")
		return
	}
	// 使被删除 Token 的缓存失效
	if token != "" {
		models.InvalidateApiTokenCache(token)
	}
	apiSuccessMsg(c, "已删除")
}