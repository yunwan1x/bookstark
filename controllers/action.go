package controllers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

func ListTasksAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "30"))
	parentID, _ := strconv.ParseInt(c.DefaultQuery("parent_id", "0"), 10, 64)
	topicID, _ := strconv.ParseInt(c.DefaultQuery("topic_id", "0"), 10, 64)
	_, parentSet := c.GetQuery("parent_id")

	var done *bool
	if raw, ok := c.GetQuery("done"); ok {
		v := raw == "1" || raw == "true"
		done = &v
	}

	tasks, total, err := models.ListTasks(memberID, models.TaskFilter{
		Keyword:         strings.TrimSpace(c.Query("keyword")),
		Done:            done,
		ParentID:        parentID,
		ParentSet:       parentSet,
		TopicID:         topicID,
		DueBefore:       strings.TrimSpace(c.Query("due_before")),
		DueAfter:        strings.TrimSpace(c.Query("due_after")),
		DueOn:           strings.TrimSpace(c.Query("due_on")),
		ModifiedDate:    strings.TrimSpace(c.Query("date")),
		IncludeChildren: c.Query("include_children") == "1",
		Page:            page,
		PageSize:        pageSize,
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取待办列表失败")
		return
	}
	apiListSuccess(c, tasks, total, page, pageSize)
}

func GetTaskDailyCountsAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	year, _ := strconv.Atoi(c.DefaultQuery("year", "0"))
	month, _ := strconv.Atoi(c.DefaultQuery("month", "0"))
	if year == 0 || month == 0 {
		now := time.Now()
		year = now.Year()
		month = int(now.Month())
	}
	counts, err := models.GetTaskDailyCounts(memberID, year, month)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取待办日历失败")
		return
	}
	apiSuccess(c, counts)
}

func GetTaskAPI(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	task, err := models.GetTaskByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "待办不存在")
		return
	}
	if !checkOwnership(c, task.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}
	apiSuccess(c, task)
}

func CreateTaskAPI(c *gin.Context) {
	var req actionTaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入待办内容")
		return
	}
	task, ok := buildTaskFromRequest(c, &req, nil)
	if !ok {
		return
	}
	if err := models.CreateTask(task); err != nil {
		apiError(c, http.StatusInternalServerError, "创建待办失败")
		return
	}
	apiSuccess(c, task)
}

func UpdateTaskAPI(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	old, err := models.GetTaskByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "待办不存在")
		return
	}
	if !checkOwnership(c, old.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}
	var req actionTaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入待办内容")
		return
	}
	task, ok := buildTaskFromRequest(c, &req, old)
	if !ok {
		return
	}
	task.TaskID = id
	task.MemberID = old.MemberID
	task.CompleteTime = old.CompleteTime
	if err := models.UpdateTask(task); err != nil {
		apiError(c, http.StatusInternalServerError, "更新待办失败")
		return
	}
	apiSuccessMsg(c, "更新成功")
}

func UpdateTaskDoneAPI(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	task, err := models.GetTaskByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "待办不存在")
		return
	}
	if !checkOwnership(c, task.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}
	var req struct {
		Done bool `json:"done"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数无效")
		return
	}
	if err := models.UpdateTaskDone(id, req.Done); err != nil {
		apiError(c, http.StatusInternalServerError, "更新完成状态失败")
		return
	}
	apiSuccessMsg(c, "更新成功")
}

func DeleteTaskAPI(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	task, err := models.GetTaskByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "待办不存在")
		return
	}
	if !checkOwnership(c, task.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}
	if err := models.DeleteTask(id); err != nil {
		apiError(c, http.StatusInternalServerError, "删除待办失败")
		return
	}
	apiSuccessMsg(c, "删除成功")
}

type actionTaskRequest struct {
	Content  string `json:"content" binding:"required"`
	DueDate  string `json:"due_date"`
	Done     bool   `json:"done"`
	ParentID int64  `json:"parent_id"`
	TopicID  *int64 `json:"topic_id"`
}

func buildTaskFromRequest(c *gin.Context, req *actionTaskRequest, old *models.Task) (*models.Task, bool) {
	content := strings.TrimSpace(req.Content)
	dueDate := strings.TrimSpace(req.DueDate)
	if dueDate == "" {
		dueDate = time.Now().AddDate(0, 0, 7).Format("2006-01-02")
	}
	if content == "" {
		apiError(c, http.StatusBadRequest, "请输入待办内容")
		return nil, false
	}
	if len([]rune(content)) > 1000 {
		apiError(c, http.StatusBadRequest, "待办内容不能超过1000个字符")
		return nil, false
	}
	if !validDate(dueDate) {
		apiError(c, http.StatusBadRequest, "日期格式应为 YYYY-MM-DD")
		return nil, false
	}
	memberID := middleware.GetMemberID(c)
	topicID := int64(0)
	if old != nil {
		topicID = old.TopicID
	}
	if req.TopicID != nil {
		topicID = *req.TopicID
	}
	if topicID > 0 {
		topic, err := models.GetTopicByID(topicID)
		if err != nil || !checkOwnership(c, topic.MemberID) {
			apiError(c, http.StatusBadRequest, "专题不存在")
			return nil, false
		}
	}
	if req.ParentID > 0 {
		if old != nil && req.ParentID == old.TaskID {
			apiError(c, http.StatusBadRequest, "父待办不能选择自己")
			return nil, false
		}
		parent, err := models.GetTaskByID(req.ParentID)
		if err != nil || !checkOwnership(c, parent.MemberID) {
			apiError(c, http.StatusBadRequest, "父待办不存在")
			return nil, false
		}
		if old != nil {
			isDescendant, err := models.IsTaskDescendant(old.TaskID, req.ParentID, memberID)
			if err != nil {
				apiError(c, http.StatusInternalServerError, "检查父待办失败")
				return nil, false
			}
			if isDescendant {
				apiError(c, http.StatusBadRequest, "父待办不能选择自己的子待办")
				return nil, false
			}
		}
	}
	return &models.Task{
		Content:  content,
		DueDate:  dueDate,
		Done:     req.Done,
		ParentID: req.ParentID,
		TopicID:  topicID,
		MemberID: memberID,
	}, true
}

func validDate(s string) bool {
	if s == "" {
		return true
	}
	if len(s) != 10 {
		return false
	}
	for i, ch := range s {
		if i == 4 || i == 7 {
			if ch != '-' {
				return false
			}
			continue
		}
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}
