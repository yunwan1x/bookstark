package controllers

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

const topicCommentRequestMaxBytes = 256 << 10

type topicCommentRequest struct {
	TargetType      string `json:"target_type"`
	TargetID        int64  `json:"target_id"`
	ParentCommentID int64  `json:"parent_comment_id"`
	Content         string `json:"content"`
}

func ListTopicCommentsAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	targetType := models.NormalizeTopicCommentTargetType(c.Query("target_type"))
	targetID, _ := strconv.ParseInt(c.Query("target_id"), 10, 64)
	if targetType == "" {
		targetID = 0
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "100"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 100
	} else if pageSize > 200 {
		pageSize = 200
	}
	items, total, err := models.ListTopicComments(
		topic.TopicID,
		middleware.GetMemberID(c),
		targetType,
		targetID,
		page,
		pageSize,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "评论目标不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "加载评论失败")
		return
	}
	apiListSuccess(c, items, total, page, pageSize)
}

func CreateTopicCommentAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, topicCommentRequestMaxBytes)
	var req topicCommentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			apiError(c, http.StatusRequestEntityTooLarge, "评论请求过大")
		} else {
			apiError(c, http.StatusBadRequest, "请求参数无效")
		}
		return
	}
	comment := &models.TopicComment{
		TopicID:         topic.TopicID,
		TargetType:      req.TargetType,
		TargetID:        req.TargetID,
		MemberID:        middleware.GetMemberID(c),
		ParentCommentID: req.ParentCommentID,
		Content:         req.Content,
	}
	if err := models.CreateTopicComment(comment); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "评论目标不存在")
			return
		}
		if errors.Is(err, models.ErrTopicCommentInvalidContent) {
			apiError(c, http.StatusBadRequest, "评论不能为空且不能超过 20000 字")
			return
		}
		if errors.Is(err, models.ErrTopicCommentReplyUnsupported) {
			apiError(c, http.StatusBadRequest, "专题评论只支持一级评论")
			return
		}
		apiError(c, http.StatusInternalServerError, "发表评论失败")
		return
	}
	apiSuccess(c, comment)
}

func UpdateTopicCommentAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	commentID, ok := parseParamID(c, "commentId", "无效评论ID")
	if !ok {
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, topicCommentRequestMaxBytes)
	var req topicCommentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			apiError(c, http.StatusRequestEntityTooLarge, "评论请求过大")
		} else {
			apiError(c, http.StatusBadRequest, "请求参数无效")
		}
		return
	}
	comment, err := models.UpdateTopicComment(
		commentID,
		topic.TopicID,
		middleware.GetMemberID(c),
		req.Content,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "评论不存在")
			return
		}
		if errors.Is(err, models.ErrTopicCommentInvalidContent) {
			apiError(c, http.StatusBadRequest, "评论不能为空且不能超过 20000 字")
			return
		}
		apiError(c, http.StatusInternalServerError, "更新评论失败")
		return
	}
	apiSuccess(c, comment)
}

func DeleteTopicCommentAPI(c *gin.Context) {
	topic, ok := mustOwnTopic(c)
	if !ok {
		return
	}
	commentID, ok := parseParamID(c, "commentId", "无效评论ID")
	if !ok {
		return
	}
	if err := models.DeleteTopicComment(commentID, topic.TopicID, middleware.GetMemberID(c)); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			apiError(c, http.StatusNotFound, "评论不存在")
			return
		}
		apiError(c, http.StatusInternalServerError, "删除评论失败")
		return
	}
	apiSuccessMsg(c, "评论已删除")
}
