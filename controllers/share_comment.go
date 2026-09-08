package controllers

import (
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

type shareCommentLimitEntry struct {
	Count int
	Until time.Time
}

type shareCommentPayload struct {
	CommentID         int64                 `json:"comment_id"`
	TargetType        string                `json:"target_type"`
	TargetID          int64                 `json:"target_id"`
	ShareIdentify     string                `json:"share_identify"`
	ParentCommentID   int64                 `json:"parent_comment_id"`
	RootCommentID     int64                 `json:"root_comment_id"`
	ReplyToCommentID  int64                 `json:"reply_to_comment_id"`
	ReplyToAuthorName string                `json:"reply_to_author_name"`
	AuthorName        string                `json:"author_name"`
	Content           string                `json:"content"`
	CreateTime        time.Time             `json:"create_time"`
	CanDelete         bool                  `json:"can_delete"`
	IsDeleted         bool                  `json:"is_deleted"`
	Replies           []shareCommentPayload `json:"replies,omitempty"`
}

type adminShareCommentPayload struct {
	CommentID         int64     `json:"comment_id"`
	TargetType        string    `json:"target_type"`
	TargetID          int64     `json:"target_id"`
	ShareIdentify     string    `json:"share_identify"`
	ParentCommentID   int64     `json:"parent_comment_id"`
	RootCommentID     int64     `json:"root_comment_id"`
	ReplyToCommentID  int64     `json:"reply_to_comment_id"`
	ReplyToAuthorName string    `json:"reply_to_author_name"`
	AuthorMemberID    int64     `json:"author_member_id"`
	AuthorName        string    `json:"author_name"`
	Content           string    `json:"content"`
	Status            string    `json:"status"`
	CreateTime        time.Time `json:"create_time"`
	ModifyTime        time.Time `json:"modify_time"`
}

var (
	shareCommentLimitMu sync.Mutex
	shareCommentLimits  = map[string]shareCommentLimitEntry{}
)

func ListShareComments(c *gin.Context) {
	detail, ok := resolveShareDetailForComments(c)
	if !ok {
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if !models.ShareCommentsEnabled() {
		apiListSuccess(c, []models.ShareComment{}, 0, normalizeCommentPage(page), normalizeCommentPageSize(pageSize))
		return
	}
	threads, total, err := models.ListShareCommentThreads(detail.ShareType, detail.TargetID, page, pageSize)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取评论失败")
		return
	}
	memberID := middleware.GetMemberID(c)
	payload := make([]shareCommentPayload, 0, len(threads))
	for i := range threads {
		payload = append(payload, buildShareCommentThreadPayload(c, detail, &threads[i], memberID))
	}
	apiListSuccess(c, payload, total, normalizeCommentPage(page), normalizeCommentPageSize(pageSize))
}

func CreateShareComment(c *gin.Context) {
	detail, ok := resolveShareDetailForComments(c)
	if !ok {
		return
	}
	if !models.ShareCommentsEnabled() {
		apiError(c, http.StatusForbidden, "评论模块未开启")
		return
	}
	var req struct {
		AuthorName       string `json:"author_name"`
		AuthorEmail      string `json:"author_email"`
		Content          string `json:"content"`
		ParentCommentID  int64  `json:"parent_comment_id"`
		ReplyToCommentID int64  `json:"reply_to_comment_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}

	memberID := middleware.GetMemberID(c)
	authorName := strings.TrimSpace(req.AuthorName)
	if memberID > 0 {
		authorName = middleware.GetAccount(c)
	}
	if authorName == "" {
		authorName = strings.TrimSpace(c.ClientIP())
	}
	email := strings.TrimSpace(req.AuthorEmail)
	if email != "" && !strings.Contains(email, "@") {
		apiError(c, http.StatusBadRequest, "邮箱格式无效")
		return
	}
	if memberID == 0 && !allowShareCommentSubmit(c.ClientIP(), detail.ShareType, detail.TargetID) {
		apiError(c, http.StatusTooManyRequests, "评论过于频繁，请稍后再试")
		return
	}

	comment, err := models.CreateShareComment(models.ShareCommentCreate{
		TargetType:       detail.ShareType,
		TargetID:         detail.TargetID,
		ShareIdentify:    detail.ShareIdentify,
		ParentCommentID:  req.ParentCommentID,
		ReplyToCommentID: req.ReplyToCommentID,
		AuthorMemberID:   memberID,
		AuthorName:       authorName,
		AuthorEmail:      email,
		Content:          req.Content,
		IPHash:           models.ShareCommentHash(c.ClientIP()),
		UserAgentHash:    models.ShareCommentHash(c.Request.UserAgent()),
	})
	if err != nil {
		apiError(c, http.StatusBadRequest, "评论内容无效")
		return
	}
	apiSuccess(c, buildShareCommentPayload(c, detail, comment, memberID))
}

func DeleteShareComment(c *gin.Context) {
	detail, ok := resolveShareDetailForCommentsByIdentify(c, c.Query("identify"))
	if !ok {
		return
	}
	if !models.ShareCommentsEnabled() {
		apiError(c, http.StatusForbidden, "评论模块未开启")
		return
	}
	commentID, err := strconv.ParseInt(c.Param("commentID"), 10, 64)
	if err != nil || commentID <= 0 {
		apiError(c, http.StatusBadRequest, "评论ID无效")
		return
	}
	comment, err := models.GetShareCommentByID(commentID)
	if err != nil || comment.Status != "visible" || comment.TargetType != detail.ShareType || comment.TargetID != detail.TargetID {
		apiError(c, http.StatusNotFound, "评论不存在")
		return
	}

	memberID := middleware.GetMemberID(c)
	if !canDeleteShareComment(c, detail, comment, memberID) {
		apiError(c, http.StatusForbidden, "无权删除评论")
		return
	}
	if err := models.SoftDeleteShareComment(commentID); err != nil {
		apiError(c, http.StatusInternalServerError, "删除评论失败")
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func ListAdminShareComments(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	status := c.Query("status")
	targetType := c.Query("target_type")

	items, total, err := models.ListShareCommentsAdmin(page, pageSize, keyword, status, targetType)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取评论失败")
		return
	}
	payload := make([]adminShareCommentPayload, 0, len(items))
	for i := range items {
		payload = append(payload, buildAdminShareCommentPayload(&items[i]))
	}
	apiListSuccess(c, payload, total, normalizeCommentPage(page), normalizeCommentPageSize(pageSize))
}

func HardDeleteAdminShareComments(c *gin.Context) {
	var req struct {
		CommentIDs []int64 `json:"comment_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || len(req.CommentIDs) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要删除的评论")
		return
	}
	affected, err := models.HardDeleteShareComments(req.CommentIDs)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "删除评论失败")
		return
	}
	apiSuccess(c, gin.H{"deleted": affected})
}

func resolveShareDetailForComments(c *gin.Context) (*models.ShareDetail, bool) {
	return resolveShareDetailForCommentsByIdentify(c, c.Param("identify"))
}

func resolveShareDetailForCommentsByIdentify(c *gin.Context, identify string) (*models.ShareDetail, bool) {
	identify = strings.TrimSpace(identify)
	if identify == "" {
		apiError(c, http.StatusBadRequest, "分享标识不能为空")
		return nil, false
	}
	detail, err := models.GetShareDetailByIdentify(identify)
	if err != nil {
		apiError(c, http.StatusNotFound, "分享内容不存在")
		return nil, false
	}
	if detail.ShareType != "blog" && detail.ShareType != "book" && detail.ShareType != "document" {
		apiError(c, http.StatusBadRequest, "不支持的分享类型")
		return nil, false
	}
	return detail, true
}

func canDeleteShareComment(c *gin.Context, detail *models.ShareDetail, comment *models.ShareComment, memberID int64) bool {
	if isAdmin(c) {
		return true
	}
	if memberID > 0 && comment.AuthorMemberID == memberID {
		return true
	}
	ownerID, err := shareDetailOwnerID(detail)
	return err == nil && memberID > 0 && ownerID == memberID
}

func buildShareCommentPayload(c *gin.Context, detail *models.ShareDetail, comment *models.ShareComment, memberID int64) shareCommentPayload {
	isDeleted := comment.Status == "deleted"
	content := comment.Content
	authorName := comment.AuthorName
	if isDeleted {
		content = "评论已删除"
		authorName = ""
	}
	payload := shareCommentPayload{
		CommentID:         comment.CommentID,
		TargetType:        comment.TargetType,
		TargetID:          comment.TargetID,
		ShareIdentify:     comment.ShareIdentify,
		ParentCommentID:   comment.ParentCommentID,
		RootCommentID:     comment.RootCommentID,
		ReplyToCommentID:  comment.ReplyToCommentID,
		ReplyToAuthorName: comment.ReplyToAuthorName,
		AuthorName:        authorName,
		Content:           content,
		CreateTime:        comment.CreateTime,
		CanDelete:         !isDeleted && canDeleteShareComment(c, detail, comment, memberID),
		IsDeleted:         isDeleted,
	}
	return payload
}

func buildShareCommentThreadPayload(c *gin.Context, detail *models.ShareDetail, thread *models.ShareCommentThread, memberID int64) shareCommentPayload {
	payload := buildShareCommentPayload(c, detail, &thread.Comment, memberID)
	payload.Replies = make([]shareCommentPayload, 0, len(thread.Replies))
	for i := range thread.Replies {
		payload.Replies = append(payload.Replies, buildShareCommentPayload(c, detail, &thread.Replies[i], memberID))
	}
	return payload
}

func buildAdminShareCommentPayload(comment *models.ShareComment) adminShareCommentPayload {
	return adminShareCommentPayload{
		CommentID:         comment.CommentID,
		TargetType:        comment.TargetType,
		TargetID:          comment.TargetID,
		ShareIdentify:     comment.ShareIdentify,
		ParentCommentID:   comment.ParentCommentID,
		RootCommentID:     comment.RootCommentID,
		ReplyToCommentID:  comment.ReplyToCommentID,
		ReplyToAuthorName: comment.ReplyToAuthorName,
		AuthorMemberID:    comment.AuthorMemberID,
		AuthorName:        comment.AuthorName,
		Content:           comment.Content,
		Status:            comment.Status,
		CreateTime:        comment.CreateTime,
		ModifyTime:        comment.ModifyTime,
	}
}

func shareDetailOwnerID(detail *models.ShareDetail) (int64, error) {
	switch detail.ShareType {
	case "blog":
		blog, err := models.GetBlogByID(detail.TargetID)
		if err != nil {
			return 0, err
		}
		return blog.MemberID, nil
	case "book":
		book, err := models.GetBookByID(detail.TargetID)
		if err != nil {
			return 0, err
		}
		return book.MemberID, nil
	case "document":
		doc, err := models.GetDocumentByID(detail.TargetID)
		if err != nil {
			return 0, err
		}
		return doc.MemberID, nil
	default:
		return 0, http.ErrNoLocation
	}
}

func allowShareCommentSubmit(ip, targetType string, targetID int64) bool {
	const maxSubmits = 5
	window := time.Minute
	now := time.Now()
	key := models.ShareCommentHash(ip + "|" + targetType + "|" + strconv.FormatInt(targetID, 10))
	shareCommentLimitMu.Lock()
	defer shareCommentLimitMu.Unlock()
	entry := shareCommentLimits[key]
	if now.After(entry.Until) {
		shareCommentLimits[key] = shareCommentLimitEntry{Count: 1, Until: now.Add(window)}
		return true
	}
	if entry.Count >= maxSubmits {
		return false
	}
	entry.Count++
	shareCommentLimits[key] = entry
	return true
}

func normalizeCommentPage(page int) int {
	if page < 1 {
		return 1
	}
	return page
}

func normalizeCommentPageSize(pageSize int) int {
	if pageSize < 1 || pageSize > 100 {
		return 20
	}
	return pageSize
}
