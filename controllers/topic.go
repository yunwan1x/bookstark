package controllers

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

func TopicsPage(c *gin.Context) {
	data := commonData(c, "topics")
	data["AISystemPromptMD"] = models.GetSetting("ai_system_prompt_md")
	c.HTML(http.StatusOK, "topics.html", data)
}

func ListTopicsAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, "page_size_topics", "20")
	date := strings.TrimSpace(c.Query("date"))
	if date != "" && !validDate(date) {
		apiError(c, http.StatusBadRequest, "无效日期")
		return
	}
	items, total, err := models.ListTopics(memberID, models.TopicFilter{
		Keyword:  strings.TrimSpace(c.Query("keyword")),
		Date:     date,
		Page:     page,
		PageSize: pageSize,
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取专题列表失败")
		return
	}
	apiListSuccess(c, items, total, page, pageSize)
}

func GetTopicDailyCountsAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	year, _ := strconv.Atoi(c.DefaultQuery("year", "0"))
	month, _ := strconv.Atoi(c.DefaultQuery("month", "0"))
	if year == 0 || month == 0 {
		now := time.Now()
		year = now.Year()
		month = int(now.Month())
	}
	if month < 1 || month > 12 || year < 1970 || year > 9999 {
		apiError(c, http.StatusBadRequest, "无效月份")
		return
	}
	counts, err := models.GetTopicDailyCounts(memberID, year, month)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取专题日历失败")
		return
	}
	apiSuccess(c, counts)
}

func CreateTopicAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	var req topicRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	topic, ok := buildTopicFromRequest(c, nil, req)
	if !ok {
		return
	}
	topic.MemberID = memberID
	if err := models.CreateTopic(topic); err != nil {
		apiError(c, http.StatusInternalServerError, "创建专题失败")
		return
	}
	apiSuccess(c, topic)
}

func GetTopicAPI(c *gin.Context) {
	topicID, ok := parseTopicID(c)
	if !ok {
		return
	}
	detail, err := models.GetTopicDetail(topicID, middleware.GetMemberID(c))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "专题不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "获取专题详情失败")
		return
	}
	apiSuccess(c, detail)
}

func UpdateTopicAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	var req topicRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	updated, ok := buildTopicFromRequest(c, topic, req)
	if !ok {
		return
	}
	if err := models.UpdateTopic(updated); err != nil {
		apiError(c, http.StatusInternalServerError, "更新专题失败")
		return
	}
	apiSuccess(c, updated)
}

func DeleteTopicAPI(c *gin.Context) {
	topicID, ok := parseTopicID(c)
	if !ok {
		return
	}
	if err := models.DeleteTopic(topicID, middleware.GetMemberID(c)); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "专题不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "删除专题失败")
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func ToggleTopicPinAPI(c *gin.Context) {
	topicID, ok := parseTopicID(c)
	if !ok {
		return
	}
	var req struct {
		IsPinned bool `json:"is_pinned"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if err := models.ToggleTopicPin(topicID, middleware.GetMemberID(c), req.IsPinned); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "专题不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "更新置顶失败")
		return
	}
	apiSuccessMsg(c, "更新成功")
}

func CreateTopicSummaryAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	var req topicSummaryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	summary := &models.TopicSummary{
		TopicID:     topic.TopicID,
		Content:     strings.TrimSpace(req.Content),
		SummaryType: models.NormalizeTopicSummaryType(req.SummaryType),
		OrderSort:   req.OrderSort,
	}
	if summary.Content == "" {
		apiError(c, http.StatusBadRequest, "请输入小结")
		return
	}
	if len([]rune(summary.Content)) > 20000 {
		apiError(c, http.StatusBadRequest, "小结不能超过20000个字符")
		return
	}
	if !models.ValidTopicSummaryType(summary.SummaryType) {
		apiError(c, http.StatusBadRequest, "不支持的小结类型")
		return
	}
	if err := models.CreateTopicSummary(summary); err != nil {
		apiError(c, http.StatusInternalServerError, "创建小结失败")
		return
	}
	apiSuccess(c, summary)
}

func UpdateTopicSummaryAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	summaryID, ok := parseParamID(c, "summaryId", "无效小结ID")
	if !ok {
		return
	}
	var req topicSummaryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	summary := &models.TopicSummary{
		SummaryID:   summaryID,
		TopicID:     topic.TopicID,
		Content:     strings.TrimSpace(req.Content),
		SummaryType: models.NormalizeTopicSummaryType(req.SummaryType),
		OrderSort:   req.OrderSort,
	}
	if summary.Content == "" {
		apiError(c, http.StatusBadRequest, "请输入小结")
		return
	}
	if len([]rune(summary.Content)) > 20000 {
		apiError(c, http.StatusBadRequest, "小结不能超过20000个字符")
		return
	}
	if !models.ValidTopicSummaryType(summary.SummaryType) {
		apiError(c, http.StatusBadRequest, "不支持的小结类型")
		return
	}
	if err := models.UpdateTopicSummary(summary); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "小结不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "更新小结失败")
		return
	}
	apiSuccess(c, summary)
}

func DeleteTopicSummaryAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	summaryID, ok := parseParamID(c, "summaryId", "无效小结ID")
	if !ok {
		return
	}
	if err := models.DeleteTopicSummary(summaryID, topic.TopicID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "小结不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "删除小结失败")
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func SortTopicSummariesAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	var req struct {
		Items []models.SortItem `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if err := models.SortTopicSummaries(topic.TopicID, req.Items); err != nil {
		apiError(c, http.StatusInternalServerError, "排序失败")
		return
	}
	apiSuccessMsg(c, "排序成功")
}

func CreateTopicResourceAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	var req topicResourceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	resource, ok := buildTopicResourceFromRequest(c, topic, req)
	if !ok {
		return
	}
	if err := models.CreateTopicResource(resource); err != nil {
		if errors.Is(err, models.ErrTopicResourceDuplicate) {
			apiError(c, http.StatusConflict, "已在专题中")
			return
		}
		apiError(c, http.StatusInternalServerError, "添加资料失败")
		return
	}
	apiSuccess(c, resource)
}

func DeleteTopicResourceAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	resourceID, ok := parseParamID(c, "resourceId", "无效资料ID")
	if !ok {
		return
	}
	if err := models.DeleteTopicResource(resourceID, topic.TopicID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "资料不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "删除资料失败")
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func SortTopicResourcesAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	var req struct {
		Items []models.SortItem `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if err := models.SortTopicResources(topic.TopicID, req.Items); err != nil {
		apiError(c, http.StatusInternalServerError, "排序失败")
		return
	}
	apiSuccessMsg(c, "排序成功")
}

type topicRequest struct {
	Title    string `json:"title"`
	Question string `json:"question"`
	IsPinned bool   `json:"is_pinned"`
}

type topicSummaryRequest struct {
	Content     string `json:"content"`
	SummaryType string `json:"summary_type"`
	OrderSort   int    `json:"order_sort"`
}

type topicResourceRequest struct {
	ResourceType string `json:"resource_type"`
	TargetID     int64  `json:"target_id"`
	Title        string `json:"title_snapshot"`
	Description  string `json:"desc_snapshot"`
	OrderSort    int    `json:"order_sort"`
}

func buildTopicFromRequest(c *gin.Context, existing *models.Topic, req topicRequest) (*models.Topic, bool) {
	title := strings.TrimSpace(req.Title)
	if title == "" {
		apiError(c, http.StatusBadRequest, "请输入专题名称")
		return nil, false
	}
	if len([]rune(title)) > 200 {
		apiError(c, http.StatusBadRequest, "专题名称不能超过200个字符")
		return nil, false
	}
	if len([]rune(req.Question)) > 2000 {
		apiError(c, http.StatusBadRequest, "专题问题不能超过2000个字符")
		return nil, false
	}
	topic := existing
	if topic == nil {
		topic = &models.Topic{}
	}
	topic.Title = title
	topic.Question = strings.TrimSpace(req.Question)
	topic.IsPinned = req.IsPinned
	return topic, true
}

func buildTopicResourceFromRequest(c *gin.Context, topic *models.Topic, req topicResourceRequest) (*models.TopicResource, bool) {
	resourceType := strings.TrimSpace(req.ResourceType)
	if !models.ValidTopicResourceType(resourceType) {
		apiError(c, http.StatusBadRequest, "不支持的资料类型")
		return nil, false
	}
	if req.TargetID <= 0 {
		apiError(c, http.StatusBadRequest, "请选择有效资源")
		return nil, false
	}
	if !topicResourceOwned(topic.MemberID, resourceType, req.TargetID) {
		apiError(c, http.StatusNotFound, "资源不存在或无权访问")
		return nil, false
	}
	title := strings.TrimSpace(req.Title)
	description := strings.TrimSpace(req.Description)
	if title == "" || description == "" {
		resolvedTitle, resolvedDescription := resolveTopicResourceSnapshot(resourceType, req.TargetID)
		if title == "" {
			title = resolvedTitle
		}
		if description == "" {
			description = resolvedDescription
		}
	}
	if title == "" {
		title = "未命名资料"
	}
	if len([]rune(title)) > 500 {
		apiError(c, http.StatusBadRequest, "资料标题不能超过500个字符")
		return nil, false
	}
	if len([]rune(description)) > 2000 {
		apiError(c, http.StatusBadRequest, "资料说明不能超过2000个字符")
		return nil, false
	}
	return &models.TopicResource{
		TopicID:       topic.TopicID,
		ResourceType:  resourceType,
		TargetID:      req.TargetID,
		TitleSnapshot: title,
		DescSnapshot:  description,
		OrderSort:     req.OrderSort,
	}, true
}

func topicResourceOwned(memberID int64, resourceType string, resourceID int64) bool {
	var owner int64
	var err error
	switch resourceType {
	case models.TopicResourceDocument:
		err = models.DB.QueryRow("SELECT member_id FROM md_documents WHERE document_id = ?", resourceID).Scan(&owner)
	case models.TopicResourceNote:
		err = models.DB.QueryRow("SELECT member_id FROM md_blogs WHERE blog_id = ? AND COALESCE(blog_type,'article') = 'note'", resourceID).Scan(&owner)
	case models.TopicResourceArticle:
		err = models.DB.QueryRow("SELECT member_id FROM md_blogs WHERE blog_id = ? AND COALESCE(blog_type,'article') = 'article'", resourceID).Scan(&owner)
	case models.TopicResourceBookmark:
		err = models.DB.QueryRow("SELECT member_id FROM md_bookmark WHERE bookmark_id = ?", resourceID).Scan(&owner)
	case models.TopicResourceTask:
		err = models.DB.QueryRow("SELECT member_id FROM md_tasks WHERE task_id = ?", resourceID).Scan(&owner)
	default:
		return false
	}
	return err == nil && owner == memberID
}

func resolveTopicResourceSnapshot(resourceType string, resourceID int64) (string, string) {
	var title, description string
	switch resourceType {
	case models.TopicResourceDocument:
		_ = models.DB.QueryRow("SELECT document_name FROM md_documents WHERE document_id = ?", resourceID).Scan(&title)
	case models.TopicResourceNote, models.TopicResourceArticle:
		_ = models.DB.QueryRow("SELECT blog_title, CASE WHEN COALESCE(blog_desc,'') != '' THEN blog_desc ELSE substr(COALESCE(blog_content,''), 1, 200) END FROM md_blogs WHERE blog_id = ?", resourceID).Scan(&title, &description)
	case models.TopicResourceBookmark:
		_ = models.DB.QueryRow("SELECT title, description FROM md_bookmark WHERE bookmark_id = ?", resourceID).Scan(&title, &description)
	case models.TopicResourceTask:
		_ = models.DB.QueryRow("SELECT substr(content, 1, 500) FROM md_tasks WHERE task_id = ?", resourceID).Scan(&title)
	}
	return strings.TrimSpace(title), strings.TrimSpace(description)
}

func parseTopicID(c *gin.Context) (int64, bool) {
	return parseParamID(c, "id", "无效专题ID")
}

func parseParamID(c *gin.Context, name, msg string) (int64, bool) {
	id, err := strconv.ParseInt(c.Param(name), 10, 64)
	if err != nil || id <= 0 {
		apiError(c, http.StatusBadRequest, msg)
		return 0, false
	}
	return id, true
}

func mustOwnTopic(c *gin.Context) (*models.Topic, bool) {
	topicID, ok := parseTopicID(c)
	if !ok {
		return nil, false
	}
	topic, err := models.GetTopicByID(topicID)
	if err != nil {
		apiError(c, http.StatusNotFound, "专题不存在")
		return nil, false
	}
	if !checkOwnership(c, topic.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return nil, false
	}
	return topic, true
}
