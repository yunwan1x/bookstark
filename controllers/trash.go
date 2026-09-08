package controllers

import (
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

// TrashPage 回收站页面
func TrashPage(c *gin.Context) {
	data := commonData(c, "trash")
	c.HTML(http.StatusOK, "trash.html", data)
}

// ListTrashAPI 获取回收站列表
func ListTrashAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	isAdmin := isAdmin(c)

	// 非管理员只能看自己的
	queryMemberID := memberID
	if isAdmin && c.Query("all") == "1" {
		queryMemberID = 0 // 0 表示查看所有
	}

	resourceType := c.Query("type")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	pageSize := getPageSize(c, "page_size_default", "20")

	items, total, err := models.ListTrash(queryMemberID, resourceType, page, pageSize)
	if err != nil {
		log.Printf("ListTrashAPI: %v", err)
		apiError(c, http.StatusInternalServerError, "获取回收站列表失败")
		return
	}

	if items == nil {
		items = []models.TrashItem{}
	}

	apiListSuccess(c, items, total, page, pageSize)
}

// RestoreTrashAPI 恢复回收站项目
func RestoreTrashAPI(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效的ID")
		return
	}

	memberID := middleware.GetMemberID(c)
	isAdmin := isAdmin(c)

	// 权限检查
	if !isAdmin {
		trash, err := models.GetTrashByID(id)
		if err != nil || trash.MemberID != memberID {
			apiError(c, http.StatusForbidden, "无权操作")
			return
		}
	}

	if err := models.RestoreFromTrash(id); err != nil {
		log.Printf("RestoreTrashAPI: %v", err)
		apiError(c, http.StatusInternalServerError, err.Error())
		return
	}

	apiSuccessMsg(c, "恢复成功")
}

// PermanentDeleteTrashAPI 永久删除回收站项目
func PermanentDeleteTrashAPI(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效的ID")
		return
	}

	memberID := middleware.GetMemberID(c)
	isAdmin := isAdmin(c)

	if err := models.PermanentDeleteTrash(id, memberID, isAdmin); err != nil {
		log.Printf("PermanentDeleteTrashAPI: %v", err)
		apiError(c, http.StatusInternalServerError, "删除失败")
		return
	}

	apiSuccessMsg(c, "已永久删除")
}

// TrashFilter 回收站批量操作的筛选条件
type TrashFilter struct {
	Type string `json:"type"`
}

// resolveTrashIDs 从请求的 IDs 或 Filter 中解析出回收站ID列表
func resolveTrashIDs(c *gin.Context, ids []int64, filter *TrashFilter) ([]int64, bool, error) {
	if len(ids) > 0 {
		return ids, false, nil
	}
	if filter == nil {
		return nil, false, nil
	}
	memberID := middleware.GetMemberID(c)
	isAdmin := isAdmin(c)
	queryMemberID := memberID
	if isAdmin && c.Query("all") == "1" {
		queryMemberID = 0
	}
	resolvedIDs, err := models.ListTrashIDsByFilter(queryMemberID, filter.Type)
	if err != nil {
		return nil, true, err
	}
	return resolvedIDs, true, nil
}

// BatchRestoreTrashAPI 批量恢复
func BatchRestoreTrashAPI(c *gin.Context) {
	var req struct {
		IDs    []int64      `json:"ids"`
		Filter *TrashFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveTrashIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询回收站失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要恢复的项目")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "一次最多恢复200项")
		return
	}

	memberID := middleware.GetMemberID(c)
	isAdmin := isAdmin(c)

	errors, err := models.BatchRestoreTrash(ids, memberID, isAdmin)
	if err != nil {
		log.Printf("BatchRestoreTrashAPI: %v", err)
		apiError(c, http.StatusInternalServerError, "批量恢复失败")
		return
	}

	if len(errors) > 0 {
		c.JSON(http.StatusOK, APIResponse{Code: 1, Message: strings.Join(errors, "; "), Data: errors})
		return
	}

	apiSuccessMsg(c, "批量恢复成功")
}

// PurgeTrashAPI 清空回收站
func PurgeTrashAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	isAdmin := isAdmin(c)

	if err := models.PurgeTrash(memberID, isAdmin); err != nil {
		log.Printf("PurgeTrashAPI: %v", err)
		apiError(c, http.StatusInternalServerError, "清空回收站失败")
		return
	}

	apiSuccessMsg(c, "回收站已清空")
}

// BatchDeleteTrashAPI 批量永久删除回收站项目
func BatchDeleteTrashAPI(c *gin.Context) {
	var req struct {
		IDs    []int64      `json:"ids"`
		Filter *TrashFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveTrashIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询回收站失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要删除的项目")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "一次最多删除200项")
		return
	}

	memberID := middleware.GetMemberID(c)
	isAdmin := isAdmin(c)

	errors, err := models.BatchDeleteTrash(ids, memberID, isAdmin)
	if err != nil {
		log.Printf("BatchDeleteTrashAPI: %v", err)
		apiError(c, http.StatusInternalServerError, "批量删除失败")
		return
	}

	if len(errors) > 0 {
		c.JSON(http.StatusOK, APIResponse{Code: 1, Message: strings.Join(errors, "; "), Data: errors})
		return
	}

	apiSuccessMsg(c, "批量删除成功")
}

// TrashCountAPI 回收站数量（用于导航 badge）
func TrashCountAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	count, err := models.CountTrashByMember(memberID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询失败")
		return
	}
	apiSuccess(c, gin.H{"count": count})
}