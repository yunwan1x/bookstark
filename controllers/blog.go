package controllers

import (
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

func BlogEditorPage(c *gin.Context) {
	identify := c.Param("identify")
	blog, err := models.GetBlogByIdentify(identify)
	if err != nil {
		c.String(http.StatusNotFound, "博客不存在")
		return
	}

	if !checkOwnership(c, blog.MemberID) {
		forbidden(c)
		return
	}

	labels, err := models.GetLabelsByResource(blog.BlogID, "blog")
	if err != nil {
		log.Printf("BlogEditorPage: GetLabelsByResource failed: %v", err)
	}
	labelStr := ""
	for i, l := range labels {
		if i > 0 {
			labelStr += ","
		}
		labelStr += l
	}

	data := commonData(c, "blogs")
	data["EditorType"] = "blog"
	data["Blog"] = blog
	data["BlogEditorType"] = blog.EditorType
	data["Labels"] = labelStr
	data["SaveInterval"] = models.GetSettingWithDefault("save_interval", "30")
	data["AISystemPromptMD"] = models.GetSetting("ai_system_prompt_md")
	data["AISystemPromptHTML"] = models.GetSetting("ai_system_prompt_html")
	data["AISystemPromptDrawing"] = models.GetSetting("ai_system_prompt_drawing")
	data["AIActionsSelection"] = models.GetSetting("ai_actions_selection")
	data["AIActionsHTML"] = models.GetSetting("ai_actions_html")
	data["AIActionsBook"] = models.GetSetting("ai_actions_book")
	data["AIActionsArticle"] = models.GetSetting("ai_actions_article")
	data["AIActionsEmpty"] = models.GetSetting("ai_actions_empty")
	data["HasPassword"] = blog.HasPassword()
	if blog.HasPassword() {
		data["BlogContentJS"] = "" // 有密码时不传内容
		data["BlogContentURL"] = ""
	} else if blog.EditorType == "html" || blog.EditorType == models.RichDocumentType {
		data["BlogContentJS"] = ""
		data["BlogContentURL"] = blogHTMLContentURL(blog.BlogID)
	} else {
		data["BlogContentJS"] = blog.BlogContent
		data["BlogContentURL"] = ""
	}
	recordRecentContent(c, "blog", blog.BlogID, "")
	c.HTML(http.StatusOK, "editor.html", data)
}

func validateBlogLocation(name string, lat, lng, accuracy *float64) error {
	if len([]rune(strings.TrimSpace(name))) > 200 {
		return fmt.Errorf("位置名称不能超过200个字符")
	}
	if lat == nil && lng == nil && accuracy == nil {
		return nil
	}
	if lat == nil || lng == nil {
		return fmt.Errorf("位置坐标不完整")
	}
	if math.IsNaN(*lat) || math.IsInf(*lat, 0) || *lat < -90 || *lat > 90 {
		return fmt.Errorf("纬度无效")
	}
	if math.IsNaN(*lng) || math.IsInf(*lng, 0) || *lng < -180 || *lng > 180 {
		return fmt.Errorf("经度无效")
	}
	if accuracy != nil && (math.IsNaN(*accuracy) || math.IsInf(*accuracy, 0) || *accuracy < 0) {
		return fmt.Errorf("位置精度无效")
	}
	return nil
}

func rejectOversizedBlogContent(c *gin.Context, editorType, content string) bool {
	maxContentLen := 500000
	if editorType == models.PresentationType {
		maxContentLen = 20 * 1024 * 1024
	}
	if editorType == "html" || editorType == "spreadsheet" || editorType == "drawing" || editorType == "mindmap" || editorType == models.RichDocumentType {
		maxContentLen = 5242880
	}
	if len(content) <= maxContentLen {
		return false
	}
	if editorType == "html" {
		apiError(c, http.StatusBadRequest, "HTML内容不能超过5MB")
	} else if editorType == "spreadsheet" {
		apiError(c, http.StatusBadRequest, "电子表格内容不能超过5MB")
	} else if editorType == "drawing" {
		apiError(c, http.StatusBadRequest, "画板内容不能超过5MB")
	} else if editorType == "mindmap" {
		apiError(c, http.StatusBadRequest, "脑图内容不能超过5MB")
	} else if editorType == models.RichDocumentType {
		apiError(c, http.StatusBadRequest, "富文档内容不能超过5MB")
	} else if editorType == models.PresentationType {
		apiError(c, http.StatusBadRequest, "演示文稿内容不能超过20MB")
	} else {
		apiError(c, http.StatusBadRequest, "博客内容不能超过500KB")
	}
	return true
}

func validateBlogDesc(desc string) error {
	if len([]rune(strings.TrimSpace(desc))) > 500 {
		return fmt.Errorf("文章描述不能超过500个字符")
	}
	return nil
}

func ListBlogs(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, "page_size_blogs", "12")
	keyword := c.Query("keyword")
	shared := c.Query("shared")
	encrypted := c.Query("encrypted")
	if page < 1 {
		page = 1
	}
	blogs, total, err := models.ListBlogsPagedWithLabels(memberID, page, pageSize, keyword, shared, encrypted, c.Query("type"), c.Query("visibility"), c.Query("label"), c.Query("date"), c.Query("pinned"), c.Query("editor_type"), c.Query("has_code"))
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取博客列表失败")
		return
	}

	apiListSuccess(c, blogs, total, page, pageSize)
}

func CreateBlog(c *gin.Context) {
	var req struct {
		BlogTitle        string   `json:"blog_title"`
		BlogIdentify     string   `json:"blog_identify"`
		Labels           string   `json:"labels"`
		BlogType         string   `json:"blog_type"`
		EditorType       string   `json:"editor_type"`
		Visibility       int      `json:"visibility"`
		BlogContent      string   `json:"blog_content"`
		BlogDesc         string   `json:"blog_desc"`
		NewPassword      string   `json:"new_password"`
		LocationName     string   `json:"location_name"`
		Latitude         *float64 `json:"latitude"`
		Longitude        *float64 `json:"longitude"`
		LocationAccuracy *float64 `json:"location_accuracy"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	// 笔记类型标题可选，自动从内容生成
	if req.BlogType == "note" && req.BlogTitle == "" {
		req.BlogTitle = "note-" + time.Now().Format("20060102150405")
	}

	if req.BlogTitle == "" {
		apiError(c, http.StatusBadRequest, "请输入标题")
		return
	}

	if len(req.BlogTitle) > 200 {
		apiError(c, http.StatusBadRequest, "标题不能超过200个字符")
		return
	}
	if !isSupportedDocumentType(req.EditorType) {
		apiError(c, http.StatusBadRequest, "不支持的文章类型")
		return
	}
	if req.EditorType == models.RichDocumentType && req.BlogContent == "" {
		req.BlogContent = models.DefaultRichDocument()
	}
	if req.EditorType == models.PresentationType && req.BlogContent == "" {
		req.BlogContent = models.DefaultPresentation(req.BlogTitle)
	}
	if rejectOversizedBlogContent(c, req.EditorType, req.BlogContent) {
		return
	}
	if err := validateContentForType(req.EditorType, req.BlogContent); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := validateBlogDesc(req.BlogDesc); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := validateBlogLocation(req.LocationName, req.Latitude, req.Longitude, req.LocationAccuracy); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}

	if req.BlogIdentify == "" {
		prefix := "blog"
		if req.BlogType == "note" {
			prefix = "note"
		}
		req.BlogIdentify = generateIdentify(prefix)
	}

	memberID := middleware.GetMemberID(c)

	// 笔记跳过标题唯一性检查
	exists, err := models.BlogTitleExists(req.BlogTitle, memberID, 0)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "检查博客标题失败")
		return
	}
	if exists {
		apiError(c, http.StatusConflict, "已存在同名博客")
		return
	}

	blog := &models.Blog{
		BlogTitle:        req.BlogTitle,
		BlogIdentify:     req.BlogIdentify,
		MemberID:         memberID,
		BlogContent:      req.BlogContent,
		BlogDesc:         strings.TrimSpace(req.BlogDesc),
		ModifyTime:       time.Now(),
		CreateTime:       time.Now(),
		BlogType:         req.BlogType,
		EditorType:       req.EditorType,
		Visibility:       req.Visibility,
		Password:         req.NewPassword,
		LocationName:     strings.TrimSpace(req.LocationName),
		Latitude:         req.Latitude,
		Longitude:        req.Longitude,
		LocationAccuracy: req.LocationAccuracy,
	}

	if err := blog.Insert(); err != nil {
		apiError(c, http.StatusBadRequest, "创建失败，标识可能已存在")
		return
	}

	if req.Labels != "" {
		models.BindLabelsFromNames(blog.BlogID, "blog", req.Labels)
	}

	// 同步 label 字段（blog 表无 label 列，此处为预留逻辑）
	if err := models.SyncResourceLabelField(blog.BlogID, "blog"); err != nil {
		log.Printf("CreateBlog: SyncResourceLabelField failed for blog %d: %v", blog.BlogID, err)
	}

	apiSuccess(c, blog)
}

func GetBlog(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	blog, err := models.GetBlogByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "博客不存在")
		return
	}

	if !checkOwnership(c, blog.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	// 有密码时不返回内容（需验证密码后获取），但返回 has_password 标记
	hasPassword := blog.HasPassword()
	result := gin.H{
		"blog_id":           blog.BlogID,
		"blog_title":        blog.BlogTitle,
		"blog_identify":     blog.BlogIdentify,
		"member_id":         blog.MemberID,
		"blog_type":         blog.BlogType,
		"editor_type":       blog.EditorType,
		"blog_desc":         blog.BlogDesc,
		"has_password":      hasPassword,
		"modify_time":       blog.ModifyTime,
		"modify_at":         blog.ModifyAt,
		"create_time":       blog.CreateTime,
		"version":           blog.Version,
		"location_name":     blog.LocationName,
		"latitude":          blog.Latitude,
		"longitude":         blog.Longitude,
		"location_accuracy": blog.LocationAccuracy,
	}
	if hasPassword {
		result["blog_content"] = ""
	} else if blog.EditorType == "html" || blog.EditorType == models.RichDocumentType {
		result["blog_content"] = ""
		result["content_url"] = blogHTMLContentURL(blog.BlogID)
		result["content_encoding"] = "gzip"
		result["content_compressed"] = models.IsCompressedContent(blog.BlogContent)
	} else {
		result["blog_content"] = blog.BlogContent
	}
	recordRecentContent(c, "blog", blog.BlogID, "")
	apiSuccess(c, result)
}

func UpdateBlog(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	var req struct {
		BlogTitle        string   `json:"blog_title"`
		BlogContent      *string  `json:"blog_content"`
		BlogDesc         *string  `json:"blog_desc"`
		NewPassword      string   `json:"new_password"`
		CurrentPassword  string   `json:"current_password"`
		Password         string   `json:"password"` // 编辑器保存时用于加密的密码
		Labels           string   `json:"labels"`
		LocationName     string   `json:"location_name"`
		Latitude         *float64 `json:"latitude"`
		Longitude        *float64 `json:"longitude"`
		LocationAccuracy *float64 `json:"location_accuracy"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	if len(req.BlogTitle) > 200 {
		apiError(c, http.StatusBadRequest, "博客标题不能超过200个字符")
		return
	}
	if req.BlogDesc != nil {
		if err := validateBlogDesc(*req.BlogDesc); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
	}
	if err := validateBlogLocation(req.LocationName, req.Latitude, req.Longitude, req.LocationAccuracy); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}

	blog, err := models.GetBlogByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "博客不存在")
		return
	}

	if req.BlogContent != nil && rejectOversizedBlogContent(c, blog.EditorType, *req.BlogContent) {
		return
	}
	if req.BlogContent != nil {
		if err := validateContentForType(blog.EditorType, *req.BlogContent); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
	}

	if !checkOwnership(c, blog.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	memberID := middleware.GetMemberID(c)

	if req.BlogTitle != "" {
		// 检查重名（排除自身）
		titleExists, _ := models.BlogTitleExists(req.BlogTitle, memberID, id)
		if titleExists {
			apiError(c, http.StatusConflict, "已存在同名博客")
			return
		}
		blog.BlogTitle = req.BlogTitle
	}
	if req.BlogDesc != nil {
		blog.BlogDesc = strings.TrimSpace(*req.BlogDesc)
	}
	blog.ModifyAt = memberID
	if req.LocationName != "" || req.Latitude != nil || req.Longitude != nil || req.LocationAccuracy != nil {
		blog.LocationName = strings.TrimSpace(req.LocationName)
		blog.Latitude = req.Latitude
		blog.Longitude = req.Longitude
		blog.LocationAccuracy = req.LocationAccuracy
	}

	// 密码管理逻辑
	hasPassword := blog.HasPassword()
	settingNewPassword := req.NewPassword != ""
	clearingPassword := req.NewPassword == "" && req.CurrentPassword != ""

	if settingNewPassword {
		// 设置或修改密码
		if hasPassword {
			// 已有密码，需要验证当前密码
			if !blog.VerifyPassword(req.CurrentPassword) {
				apiError(c, http.StatusBadRequest, "当前密码不正确")
				return
			}
			// 解密当前内容
			if models.IsEncrypted(blog.BlogContent) {
				plain, err := models.DecryptContent(req.CurrentPassword, blog.BlogContent)
				if err != nil {
					apiError(c, http.StatusBadRequest, "解密内容失败")
					return
				}
				blog.BlogContent = plain
			}
		}
		// 如果请求中有新内容，使用新内容；否则使用解密后的内容
		if req.BlogContent != nil {
			blog.BlogContent = *req.BlogContent
		}
		encoded, err := encodeContentBeforeEncryption(blog.EditorType, blog.BlogContent)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "编码内容失败")
			return
		}
		// 用新密码加密内容
		encrypted, err := models.EncryptContent(req.NewPassword, encoded)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "加密内容失败")
			return
		}
		blog.BlogContent = encrypted
		blog.Password = req.NewPassword
	} else if clearingPassword {
		// 清除密码
		if !blog.VerifyPassword(req.CurrentPassword) {
			apiError(c, http.StatusBadRequest, "当前密码不正确")
			return
		}
		// 解密内容
		if models.IsEncrypted(blog.BlogContent) {
			plain, err := models.DecryptContent(req.CurrentPassword, blog.BlogContent)
			if err != nil {
				apiError(c, http.StatusBadRequest, "解密内容失败")
				return
			}
			blog.BlogContent = plain
		}
		blog.Password = ""
	} else if hasPassword {
		// 博客有密码但未修改密码，编辑器保存场景
		if req.Password != "" {
			// 验证密码并加密新内容
			if !blog.VerifyPassword(req.Password) {
				apiError(c, http.StatusBadRequest, "密码不正确")
				return
			}
			content := blog.BlogContent
			if req.BlogContent != nil {
				content = *req.BlogContent
			} else if models.IsEncrypted(content) {
				plain, err := models.DecryptContent(req.Password, content)
				if err != nil {
					apiError(c, http.StatusBadRequest, "解密内容失败")
					return
				}
				content = plain
			}
			encoded, err := encodeContentBeforeEncryption(blog.EditorType, content)
			if err != nil {
				apiError(c, http.StatusInternalServerError, "编码内容失败")
				return
			}
			encrypted, err := models.EncryptContent(req.Password, encoded)
			if err != nil {
				apiError(c, http.StatusInternalServerError, "加密内容失败")
				return
			}
			blog.BlogContent = encrypted
		} else {
			// 有密码但未提供密码，不允许保存内容变更
			// 只更新标题等非内容字段
			if req.BlogContent != nil {
				apiError(c, http.StatusBadRequest, "请先验证密码")
				return
			}
		}
	} else {
		// 无密码，直接更新内容
		if req.BlogContent != nil {
			blog.BlogContent = *req.BlogContent
		}
	}

	if err := blog.Update(); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}

	if req.Labels != "" {
		models.RebindLabels(id, "blog", req.Labels)
	}

	// 同步 label 字段（blog 表无 label 列，此处为预留逻辑）
	if err := models.SyncResourceLabelField(id, "blog"); err != nil {
		log.Printf("UpdateBlog: SyncResourceLabelField failed for blog %d: %v", id, err)
	}

	apiSuccessMsg(c, "更新成功")
}

func DeleteBlog(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	blog, err := models.GetBlogByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "博客不存在")
		return
	}
	if !checkOwnership(c, blog.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if err := models.DeleteBlog(id); err != nil {
		if strings.Contains(err.Error(), "不存在") {
			apiError(c, http.StatusNotFound, err.Error())
		} else {
			apiError(c, http.StatusInternalServerError, "删除失败")
		}
		return
	}
	apiSuccessMsg(c, "删除成功")
}

// VerifyBlogPassword verifies a blog's password and returns decrypted content
func VerifyBlogPassword(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	var req struct {
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入密码")
		return
	}

	blog, err := models.GetBlogByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "博客不存在")
		return
	}

	if !checkOwnership(c, blog.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if !blog.HasPassword() {
		apiError(c, http.StatusBadRequest, "该博客未设置密码")
		return
	}

	if !blog.VerifyPassword(req.Password) {
		apiError(c, http.StatusBadRequest, "密码不正确")
		return
	}

	// 解密内容
	content := blog.BlogContent
	if models.IsEncrypted(content) {
		plain, err := models.DecryptContent(req.Password, content)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "解密内容失败")
			return
		}
		content = plain
	}
	if blog.EditorType == "html" || blog.EditorType == models.RichDocumentType {
		plain, err := models.DecodeContentForType(blog.EditorType, content)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "解压内容失败")
			return
		}
		content = plain
	}

	apiSuccess(c, gin.H{"blog_content": content})
}

// ToggleBlogPinAPI toggles pin state
func ToggleBlogPinAPI(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	memberID := middleware.GetMemberID(c)
	pinned, err := models.ToggleBlogPin(id, memberID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, err.Error())
		return
	}
	apiSuccess(c, gin.H{"is_pinned": pinned})
}

// ToggleBlogVisibilityAPI cycles visibility
func ToggleBlogVisibilityAPI(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	memberID := middleware.GetMemberID(c)
	vis, err := models.ToggleBlogVisibility(id, memberID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, err.Error())
		return
	}
	apiSuccess(c, gin.H{"visibility": vis})
}

// BatchPinBlogsAPI pins multiple blogs
func BatchPinBlogsAPI(c *gin.Context) {
	var req struct {
		IDs []int64 `json:"ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	memberID := middleware.GetMemberID(c)
	affected, err := models.BatchPinBlogs(req.IDs, memberID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "操作失败")
		return
	}
	apiSuccess(c, gin.H{"affected": affected})
}

// NotesPage renders the notes timeline page
func NotesPage(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	pageSize := getPageSize(c, "page_size_notes", "20")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	blogType := c.DefaultQuery("type", "")
	keyword := c.Query("keyword")
	if page < 1 {
		page = 1
	}

	blogs, total, err := models.ListBlogsPagedWithLabels(memberID, page, pageSize, keyword, "", "", blogType, "", "", "", "", "", "")
	if err != nil {
		log.Printf("NotesPage: ListBlogsPagedWithLabels failed: %v", err)
	}

	// Calendar data: current month
	now := time.Now()
	dailyCounts, _ := models.GetBlogDailyCounts(memberID, now.Year(), int(now.Month()))
	taskDailyCounts, _ := models.GetTaskDailyCounts(memberID, now.Year(), int(now.Month()))

	// Labels for sidebar filter, separated by blog type
	noteLabels, _ := models.ListLabelsByMemberForType(memberID, "blog", "note")
	articleLabels, _ := models.ListLabelsByMemberForType(memberID, "blog", "article")

	data := commonData(c, "notes")
	data["ActiveKnowledgeTab"] = c.Query("tab")
	data["Blogs"] = blogs
	data["Total"] = total
	data["Page"] = page
	data["PageSize"] = pageSize
	data["BlogType"] = blogType
	data["DailyCounts"] = dailyCounts
	data["TaskDailyCounts"] = taskDailyCounts
	data["CalYear"] = now.Year()
	data["CalMonth"] = int(now.Month())
	data["NoteLabels"] = noteLabels
	data["ArticleLabels"] = articleLabels
	data["AISystemPromptMD"] = models.GetSetting("ai_system_prompt_md")
	data["AISystemPromptDrawing"] = models.GetSetting("ai_system_prompt_drawing")
	data["AIActionsNote"] = models.GetSetting("ai_actions_note")
	data["AIActionsTask"] = models.GetSetting("ai_actions_task")
	c.HTML(http.StatusOK, "notes.html", data)
}

// NotesPublicPage renders public notes timeline
func NotesPublicPage(c *gin.Context) {
	pageSize := getPageSize(c, "page_size_notes", "20")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}

	// Get public notes (visibility=1) via existing API with visibility filter
	blogs, total, err := models.ListBlogsPagedWithLabels(0, page, pageSize, "", "", "", "note", "1", "", "", "", "", "")
	if err != nil {
		log.Printf("NotesPublicPage: failed: %v", err)
	}
	for i := range blogs {
		blogs[i].LocationName = ""
		blogs[i].Latitude = nil
		blogs[i].Longitude = nil
		blogs[i].LocationAccuracy = nil
	}

	data := commonData(c, "notes")
	data["Blogs"] = blogs
	data["Total"] = total
	data["Page"] = page
	data["PageSize"] = pageSize
	data["ShareCommentsEnabled"] = models.ShareCommentsEnabled()
	data["ShareCommentMaxLength"] = models.ShareCommentMaxLength()
	c.HTML(http.StatusOK, "notes_public.html", data)
}

// GetBlogDailyCountsAPI returns calendar heatmap data
func GetBlogDailyCountsAPI(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	year, _ := strconv.Atoi(c.DefaultQuery("year", "0"))
	month, _ := strconv.Atoi(c.DefaultQuery("month", "0"))
	if year == 0 || month == 0 {
		now := time.Now()
		year = now.Year()
		month = int(now.Month())
	}
	counts, err := models.GetBlogDailyCounts(memberID, year, month)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取日历数据失败")
		return
	}
	apiSuccess(c, counts)
}
