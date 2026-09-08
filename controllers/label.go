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

func LabelsPage(c *gin.Context) {
	data := commonData(c, "labels")
	c.HTML(http.StatusOK, "labels.html", data)
}

func ListLabels(c *gin.Context) {
	keyword := c.Query("keyword")
	sortBy := c.DefaultQuery("sort_by", "name")
	sortOrder := c.DefaultQuery("sort_order", "asc")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	pageSize := getPageSize(c, "page_size_labels", "20")

	labels, total, usedCount, unusedCount, err := models.ListLabelsWithCountPaged(keyword, sortBy, sortOrder, page, pageSize)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取标签列表失败")
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code":         0,
		"data":         labels,
		"total":        total,
		"used_count":   usedCount,
		"unused_count": unusedCount,
		"page":         page,
		"page_size":    pageSize,
		"total_pages":  calcTotalPages(total, pageSize),
	})
}

func ListRecommendedLabels(c *gin.Context) {
	pageSize := getPageSize(c, "tag_recommend_page_size", "10")
	if pageSize > 50 {
		pageSize = 50
	}
	strategy := strings.TrimSpace(c.Query("strategy"))
	manualLabels := []string{}
	if raw := strings.TrimSpace(c.Query("manual_labels")); raw != "" {
		manualLabels = strings.Split(raw, ",")
	}
	labels, err := models.ListRecommendedLabels(strategy, manualLabels, pageSize)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取推荐标签失败")
		return
	}
	apiSuccess(c, labels)
}

func GetTagRecommendationSettings(c *gin.Context) {
	apiSuccess(c, models.GetTagRecommendationSettings())
}

func UpdateTagRecommendationSettings(c *gin.Context) {
	if !isAdmin(c) {
		apiError(c, http.StatusForbidden, "需要管理员权限")
		return
	}
	var req models.TagRecommendationSettings
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}
	if err := models.UpdateTagRecommendationSettings(req); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	apiSuccess(c, models.GetTagRecommendationSettings())
}

// CreateLabel 创建标签 — 所有登录用户均可创建，这是有意为之的设计：
// 标签是全局共享资源，用户在给自己的书籍/博客/书签打标签时需要能创建新标签。
// 标签的更新和删除操作已有管理员权限限制（见 UpdateLabel、DeleteLabel）。
func CreateLabel(c *gin.Context) {
	var req struct {
		LabelName string `json:"label_name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入标签名称")
		return
	}

	if len(req.LabelName) > 100 {
		apiError(c, http.StatusBadRequest, "标签名称不能超过100个字符")
		return
	}

	label := &models.Label{LabelName: req.LabelName}
	if err := label.Insert(); err != nil {
		apiError(c, http.StatusBadRequest, "标签已存在")
		return
	}

	apiSuccess(c, label)
}

func UpdateLabel(c *gin.Context) {
	if !isAdmin(c) {
		apiError(c, http.StatusForbidden, "需要管理员权限")
		return
	}
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	var req struct {
		LabelName string `json:"label_name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入标签名称")
		return
	}

	if len(req.LabelName) > 100 {
		apiError(c, http.StatusBadRequest, "标签名称不能超过100个字符")
		return
	}

	label, err := models.GetLabelByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "标签不存在")
		return
	}

	label.LabelName = req.LabelName
	if err := label.Update(); err != nil {
		apiError(c, http.StatusBadRequest, "标签名可能已存在")
		return
	}

	apiSuccessMsg(c, "更新成功")
}

func DeleteLabel(c *gin.Context) {
	if !isAdmin(c) {
		apiError(c, http.StatusForbidden, "需要管理员权限")
		return
	}
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	if err := models.DeleteLabel(id); err != nil {
		if strings.Contains(err.Error(), "不存在") {
			apiError(c, http.StatusNotFound, err.Error())
		} else {
			apiError(c, http.StatusInternalServerError, "删除失败")
		}
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func DeleteUnusedLabels(c *gin.Context) {
	if !isAdmin(c) {
		apiError(c, http.StatusForbidden, "需要管理员权限")
		return
	}

	count, err := models.DeleteUnusedLabels()
	if err != nil {
		apiError(c, http.StatusInternalServerError, "清除失败")
		return
	}

	apiSuccess(c, gin.H{"deleted": count})
}

func BindLabels(c *gin.Context) {
	var req struct {
		LabelID      int64   `json:"label_id" binding:"required"`
		ResourceIDs  []int64 `json:"resource_ids" binding:"required"`
		RelationType string  `json:"relation_type" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if len(req.ResourceIDs) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}

	if req.RelationType != "book" && req.RelationType != "blog" && req.RelationType != "bookmark" && req.RelationType != "document" {
		apiError(c, http.StatusBadRequest, "relation_type 必须是 book、blog、bookmark 或 document")
		return
	}

	// 所有权校验：验证目标资源属于当前用户
	memberID := middleware.GetMemberID(c)
	if !isAdmin(c) {
		unownedCount, err := models.CheckResourcesOwnership(req.ResourceIDs, req.RelationType, memberID)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "校验资源所有权失败")
			return
		}
		if unownedCount > 0 {
			apiError(c, http.StatusForbidden, "无权操作不属于自己的资源")
			return
		}
	}

	if err := models.BindLabels(req.LabelID, req.ResourceIDs, req.RelationType); err != nil {
		apiError(c, http.StatusInternalServerError, "绑定失败")
		return
	}

	// 同步资源的 label 字段
	for _, rid := range req.ResourceIDs {
		if err := models.SyncResourceLabelField(rid, req.RelationType); err != nil {
			log.Printf("BindLabels: SyncResourceLabelField failed for resource %d (%s): %v", rid, req.RelationType, err)
		}
		if req.RelationType == "bookmark" {
			if err := models.TouchBookmarkModifyTime(rid); err != nil {
				log.Printf("BindLabels: TouchBookmarkModifyTime failed for resource %d: %v", rid, err)
			}
		}
	}

	apiSuccessMsg(c, "绑定成功")
}

func UnbindLabels(c *gin.Context) {
	var req struct {
		LabelID      int64   `json:"label_id" binding:"required"`
		ResourceIDs  []int64 `json:"resource_ids" binding:"required"`
		RelationType string  `json:"relation_type" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if len(req.ResourceIDs) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}

	if req.RelationType != "book" && req.RelationType != "blog" && req.RelationType != "bookmark" && req.RelationType != "document" {
		apiError(c, http.StatusBadRequest, "relation_type 必须是 book、blog、bookmark 或 document")
		return
	}

	// 所有权校验：验证目标资源属于当前用户
	memberID := middleware.GetMemberID(c)
	if !isAdmin(c) {
		unownedCount, err := models.CheckResourcesOwnership(req.ResourceIDs, req.RelationType, memberID)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "校验资源所有权失败")
			return
		}
		if unownedCount > 0 {
			apiError(c, http.StatusForbidden, "无权操作不属于自己的资源")
			return
		}
	}

	if err := models.UnbindLabels(req.LabelID, req.ResourceIDs, req.RelationType); err != nil {
		apiError(c, http.StatusInternalServerError, "解绑失败")
		return
	}

	// 同步资源的 label 字段
	for _, rid := range req.ResourceIDs {
		if err := models.SyncResourceLabelField(rid, req.RelationType); err != nil {
			log.Printf("UnbindLabels: SyncResourceLabelField failed for resource %d (%s): %v", rid, req.RelationType, err)
		}
		if req.RelationType == "bookmark" {
			if err := models.TouchBookmarkModifyTime(rid); err != nil {
				log.Printf("UnbindLabels: TouchBookmarkModifyTime failed for resource %d: %v", rid, err)
			}
		}
	}

	apiSuccessMsg(c, "解绑成功")
}

func GetLabelDetail(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	detail, err := models.GetLabelDetail(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "标签不存在")
		return
	}

	apiSuccess(c, detail)
}

func MergeLabels(c *gin.Context) {
	if !isAdmin(c) {
		apiError(c, http.StatusForbidden, "需要管理员权限")
		return
	}

	var req struct {
		TargetID  int64   `json:"target_id" binding:"required"`
		SourceIDs []int64 `json:"source_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	if len(req.SourceIDs) < 1 {
		apiError(c, http.StatusBadRequest, "请至少选择一个源标签")
		return
	}
	if len(req.SourceIDs) > 100 {
		apiError(c, http.StatusBadRequest, "合并源标签最多100个")
		return
	}

	if err := models.MergeLabels(req.TargetID, req.SourceIDs); err != nil {
		apiError(c, http.StatusInternalServerError, "合并失败")
		return
	}

	apiSuccessMsg(c, "合并成功")
}

// GetResourceLabels returns labels for a specific resource (book/blog/bookmark)
func GetResourceLabels(c *gin.Context) {
	relationType := c.Param("type")
	resourceID, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	if relationType != "book" && relationType != "blog" && relationType != "bookmark" && relationType != "document" {
		apiError(c, http.StatusBadRequest, "type 必须是 book、blog、bookmark 或 document")
		return
	}

	labels, err := models.GetLabelsByResource(resourceID, relationType)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取标签失败")
		return
	}

	apiSuccess(c, labels)
}

// UpdateResourceLabels replaces all labels for a resource (rebind)
func UpdateResourceLabels(c *gin.Context) {
	relationType := c.Param("type")
	resourceID, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	if relationType != "book" && relationType != "blog" && relationType != "bookmark" && relationType != "document" {
		apiError(c, http.StatusBadRequest, "type 必须是 book、blog、bookmark 或 document")
		return
	}

	// Ownership check
	memberID := middleware.GetMemberID(c)
	if !isAdmin(c) {
		unownedCount, err := models.CheckResourcesOwnership([]int64{resourceID}, relationType, memberID)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "校验资源所有权失败")
			return
		}
		if unownedCount > 0 {
			apiError(c, http.StatusForbidden, "无权操作不属于自己的资源")
			return
		}
	}

	var req struct {
		Labels string `json:"labels"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	if err := models.RebindLabels(resourceID, relationType, req.Labels); err != nil {
		apiError(c, http.StatusInternalServerError, "更新标签失败")
		return
	}

	// 同步资源的 label 字段
	if err := models.SyncResourceLabelField(resourceID, relationType); err != nil {
		log.Printf("UpdateResourceLabels: SyncResourceLabelField failed for resource %d (%s): %v", resourceID, relationType, err)
	}
	if relationType == "bookmark" {
		if err := models.TouchBookmarkModifyTime(resourceID); err != nil {
			log.Printf("UpdateResourceLabels: TouchBookmarkModifyTime failed for resource %d: %v", resourceID, err)
		}
	}

	labels, _ := models.GetLabelsByResource(resourceID, relationType)
	apiSuccess(c, labels)
}
