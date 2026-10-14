package controllers

import (
	"encoding/json"
	"html/template"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/i18n"
	"bookstark/middleware"
	"bookstark/models"
)

// SharesPage renders the public shares list page
func SharesPage(c *gin.Context) {
	PublicFeedPage(c)
}

// ShareViewPage renders a single share content preview
func ShareViewPage(c *gin.Context) {
	identify := c.Param("identify")

	detail, err := models.GetShareDetailByIdentify(identify)
	if err != nil {
		c.String(http.StatusNotFound, "分享内容不存在")
		return
	}
	prepareShareHTMLPayload(detail)

	friendLinks, err := models.ListEnabledFriendLinks()
	if err != nil {
		log.Printf("ShareViewPage: ListEnabledFriendLinks failed: %v", err)
	}

	lang := middleware.GetLang(c)
	t := i18n.MakeT(lang)
	bundleJSON, _ := json.Marshal(i18n.JSBundle(lang))

	c.HTML(http.StatusOK, "share_view.html", gin.H{
		"Share":                 detail,
		"FriendLinks":           friendLinks,
		"CSRFToken":             middleware.GetCSRFToken(c),
		"MemberID":              middleware.GetMemberID(c),
		"Account":               middleware.GetAccount(c),
		"Lang":                  lang,
		"T":                     t,
		"JSBundle":              template.JS(bundleJSON),
		"ShareCommentsEnabled":  models.ShareCommentsEnabled(),
		"ShareCommentMaxLength": models.ShareCommentMaxLength(),
		"SaveInterval":          models.GetSettingWithDefault("save_interval", "30"),
		"AISystemPromptMD":      models.GetSetting("ai_system_prompt_md"),
		"AISystemPromptHTML":    models.GetSetting("ai_system_prompt_html"),
		"AISystemPromptDrawing": models.GetSetting("ai_system_prompt_drawing"),
		"AIActionsSelection":    models.GetSetting("ai_actions_selection"),
		"AIActionsHTML":         models.GetSetting("ai_actions_html"),
		"AIActionsBook":         models.GetSetting("ai_actions_book"),
		"AIActionsArticle":      models.GetSetting("ai_actions_article"),
		"AIActionsEmpty":        models.GetSetting("ai_actions_empty"),
		"AIEnabled":             models.GetSettingWithDefault("ai_enabled", "0") == "1",
	})
}

// ListShares returns paginated shares as JSON (public)
func ListShares(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, "page_size_shares", "12")
	keyword := c.Query("keyword")
	filter := c.Query("type") // "article", "note", "book", or ""
	if page < 1 {
		page = 1
	}

	shares, total, err := models.ListSharesPaged(page, pageSize, keyword, filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取分享列表失败")
		return
	}
	apiListSuccess(c, shares, total, page, pageSize)
}

// GetShare returns a single share detail (public)
func GetShare(c *gin.Context) {
	identify := c.Param("identify")

	detail, err := models.GetShareDetailByIdentify(identify)
	if err != nil {
		apiError(c, http.StatusNotFound, "分享内容不存在")
		return
	}
	prepareShareHTMLPayload(detail)
	apiSuccess(c, detail)
}

// PublishShare creates a share (auth required)
func PublishShare(c *gin.Context) {
	var req struct {
		ShareType  string `json:"share_type" binding:"required"`
		TargetID   int64  `json:"target_id" binding:"required"`
		EnableEdit bool   `json:"enable_edit"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.ShareType != "blog" && req.ShareType != "book" && req.ShareType != "document" {
		apiError(c, http.StatusBadRequest, "类型无效")
		return
	}

	memberID := middleware.GetMemberID(c)

	// Verify resource ownership
	if !isAdmin(c) {
		var ownerID int64
		switch req.ShareType {
		case "blog":
			blog, err := models.GetBlogByID(req.TargetID)
			if err != nil {
				apiError(c, http.StatusNotFound, "资源不存在")
				return
			}
			ownerID = blog.MemberID
		case "book":
			book, err := models.GetBookByID(req.TargetID)
			if err != nil {
				apiError(c, http.StatusNotFound, "资源不存在")
				return
			}
			ownerID = book.MemberID
		case "document":
			doc, err := models.GetDocumentByID(req.TargetID)
			if err != nil {
				apiError(c, http.StatusNotFound, "文档不存在")
				return
			}
			ownerID = doc.MemberID
		}
		if ownerID != memberID {
			apiError(c, http.StatusForbidden, "无权操作")
			return
		}
	}

	if req.EnableEdit && req.ShareType == "book" {
		apiError(c, http.StatusBadRequest, "书籍整本不支持编辑链接")
		return
	}

	if req.EnableEdit && req.ShareType == "blog" {
		blog, err := models.GetBlogByID(req.TargetID)
		if err != nil {
			apiError(c, http.StatusNotFound, "资源不存在")
			return
		}
		if blog.HasPassword() {
			apiError(c, http.StatusBadRequest, "加密文章不支持编辑链接")
			return
		}
	}

	var editToken string
	if req.EnableEdit {
		var err error
		editToken, err = models.GenerateEditToken()
		if err != nil {
			apiError(c, http.StatusInternalServerError, "生成编辑令牌失败")
			return
		}
	}
	share, err := models.CreateShare(req.ShareType, req.TargetID, memberID, editToken)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "发布失败")
		return
	}
	// 发布博客分享时同步将文章可见性设为公开，避免分享链接因 visibility != 1 而显示分享不存在
	if req.ShareType == "blog" {
		if _, err := models.DB.Exec("UPDATE md_blogs SET visibility = 1 WHERE blog_id = ? AND COALESCE(visibility,0) != 1", req.TargetID); err != nil {
			log.Printf("PublishShare: set visibility failed for blog_id=%d: %v", req.TargetID, err)
		}
	}
	apiSuccess(c, gin.H{
		"share_identify": share.ShareIdentify,
		"edit_token":     share.EditToken,
	})
}

// UnpublishShare removes a share (auth required)
func UnpublishShare(c *gin.Context) {
	shareType := c.Param("type")
	if shareType != "blog" && shareType != "book" && shareType != "document" {
		apiError(c, http.StatusBadRequest, "不支持的分享类型")
		return
	}
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	// Public blogs need not have an explicit share row; authorize against the resource.
	var owner int64
	var err error
	if shareType == "blog" {
		var blog *models.Blog
		blog, err = models.GetBlogByID(id)
		if err == nil {
			owner = blog.MemberID
		}
	} else if shareType == "book" {
		var book *models.Book
		book, err = models.GetBookByID(id)
		if err == nil {
			owner = book.MemberID
		}
	} else {
		var doc *models.Document
		doc, err = models.GetDocumentByID(id)
		if err == nil {
			owner = doc.MemberID
		}
	}
	if err != nil {
		apiError(c, http.StatusNotFound, "分享不存在")
		return
	}
	if !checkOwnership(c, owner) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if err := models.UnpublishPublicShare(shareType, id); err != nil {
		apiError(c, http.StatusInternalServerError, "撤回失败")
		return
	}
	apiSuccessMsg(c, "撤回成功")
}

// GetShareStatus returns which IDs are published (auth required)
func GetShareStatus(c *gin.Context) {
	shareType := c.Query("type")
	idsStr := c.Query("ids")
	if shareType == "" || idsStr == "" {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}

	var ids []int64
	for _, s := range strings.Split(idsStr, ",") {
		s = strings.TrimSpace(s)
		if id, err := strconv.ParseInt(s, 10, 64); err == nil {
			ids = append(ids, id)
		}
		if len(ids) >= 200 {
			break
		}
	}

	status, err := models.GetShareStatus(shareType, ids)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询失败")
		return
	}
	apiSuccess(c, status)
}

// VerifySharePassword verifies a share's password and returns decrypted content (public)
func VerifySharePassword(c *gin.Context) {
	identify := c.Param("identify")

	var req struct {
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入密码")
		return
	}

	detail, err := models.GetShareDetailByIdentify(identify)
	if err != nil {
		apiError(c, http.StatusNotFound, "分享内容不存在")
		return
	}

	if !detail.HasPassword {
		apiError(c, http.StatusBadRequest, "该分享未设置密码")
		return
	}

	if detail.ShareType != "blog" {
		apiError(c, http.StatusBadRequest, "不支持的类型")
		return
	}

	// 获取博客并验证密码
	blog, err := models.GetBlogByID(detail.TargetID)
	if err != nil {
		apiError(c, http.StatusNotFound, "博客不存在")
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

	apiSuccess(c, gin.H{"content": content})
}

func ToggleSharePin(c *gin.Context) {
	if !isAdmin(c) {
		apiError(c, http.StatusForbidden, "无权限")
		return
	}
	shareType := c.Param("type")
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效的ID")
		return
	}
	if shareType != "blog" && shareType != "book" {
		apiError(c, http.StatusBadRequest, "不支持的分享类型")
		return
	}

	pinned, err := models.ToggleSharePin(shareType, targetID)
	if err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	apiSuccess(c, gin.H{"is_pinned": pinned})
}

// GetBookShareDoc returns a document's content for a public book share (no auth required)
func GetBookShareDoc(c *gin.Context) {
	identify := c.Param("identify")
	docIdentify := c.Param("docIdentify")

	// Load the share and verify it's a book type
	share, err := models.GetShareDetailByIdentify(identify)
	if err != nil || share.ShareType != "book" {
		apiError(c, http.StatusNotFound, "分享不存在")
		return
	}

	// Load the document by its identify
	doc, err := models.GetDocumentByIdentify(docIdentify)
	if err != nil {
		apiError(c, http.StatusNotFound, "文档不存在")
		return
	}

	// Verify the document belongs to the shared book
	if doc.BookID != share.TargetID {
		apiError(c, http.StatusForbidden, "无权访问")
		return
	}

	result := gin.H{
		"title":    doc.DocumentName,
		"content":  doc.Markdown,
		"doc_type": doc.DocType,
	}
	if doc.DocType == "html" || doc.DocType == models.RichDocumentType {
		result["content"] = ""
		result["content_url"] = bookShareDocHTMLContentURL(identify, docIdentify)
		result["content_encoding"] = "gzip"
		result["content_compressed"] = models.IsCompressedContent(doc.Markdown)
	}
	apiSuccess(c, result)
}

// ManageEditToken enables, disables, or resets the edit token for a share (auth required)
func ManageEditToken(c *gin.Context) {
	shareType := c.Param("type")
	targetID, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	ownerID, err := models.GetShareMemberID(shareType, targetID)
	if err != nil {
		apiError(c, http.StatusNotFound, "分享记录不存在")
		return
	}
	if !checkOwnership(c, ownerID) {
		apiError(c, http.StatusForbidden, "无权限")
		return
	}

	var req struct {
		Action string `json:"action"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}

	var token string
	switch req.Action {
	case "enable", "reset":
		token, err = models.GenerateEditToken()
		if err != nil {
			apiError(c, http.StatusInternalServerError, "生成令牌失败")
			return
		}
	case "disable":
		token = ""
	default:
		apiError(c, http.StatusBadRequest, "action 无效，可选: enable, disable, reset")
		return
	}

	if err := models.SetEditToken(shareType, targetID, token); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}

	apiSuccess(c, gin.H{"edit_token": token})
}

// GetShareEdit returns content for editing via share edit token (public with token)
func GetShareEdit(c *gin.Context) {
	identify := c.Param("identify")
	token := c.Query("token")
	if token == "" {
		apiError(c, http.StatusForbidden, "缺少编辑令牌")
		return
	}

	share, err := models.GetShareByIdentifyWithToken(identify)
	if err != nil {
		apiError(c, http.StatusNotFound, "分享不存在")
		return
	}
	if share.EditToken == "" || share.EditToken != token {
		apiError(c, http.StatusForbidden, "编辑令牌无效")
		return
	}

	var title, content, docType string
	var modifyTime time.Time
	hasPassword := false

	switch share.ShareType {
	case "blog":
		blog, err := models.GetBlogByID(share.TargetID)
		if err != nil {
			apiError(c, http.StatusNotFound, "文章不存在")
			return
		}
		title = blog.BlogTitle
		content = blog.BlogContent
		docType = blog.EditorType
		hasPassword = blog.HasPassword()
		modifyTime = blog.ModifyTime
	case "document":
		doc, err := models.GetDocumentByID(share.TargetID)
		if err != nil {
			apiError(c, http.StatusNotFound, "文档不存在")
			return
		}
		title = doc.DocumentName
		content = doc.Markdown
		docType = doc.DocType
		if doc.ModifyTime != nil {
			modifyTime = *doc.ModifyTime
		}
	default:
		apiError(c, http.StatusBadRequest, "该类型不支持编辑")
		return
	}

	result := gin.H{
		"editable":     true,
		"title":        title,
		"content":      content,
		"doc_type":     docType,
		"share_type":   share.ShareType,
		"modify_time":  modifyTime.Format("2006-01-02 15:04:05"),
		"has_password": hasPassword,
	}
	if hasPassword {
		result["content"] = ""
	}
	if (docType == "html" || docType == models.RichDocumentType) && !hasPassword {
		result["content"] = ""
		result["content_url"] = shareEditHTMLContentURL(identify, token)
		result["content_encoding"] = "gzip"
		result["content_compressed"] = models.IsCompressedContent(content)
	}
	apiSuccess(c, result)
}

// SaveShareEdit saves content via share edit token (public with token)
func SaveShareEdit(c *gin.Context) {
	identify := c.Param("identify")
	token := c.Query("token")
	if token == "" {
		apiError(c, http.StatusForbidden, "缺少编辑令牌")
		return
	}

	share, err := models.GetShareByIdentifyWithToken(identify)
	if err != nil {
		apiError(c, http.StatusNotFound, "分享不存在")
		return
	}
	if share.EditToken == "" || share.EditToken != token {
		apiError(c, http.StatusForbidden, "编辑令牌无效或已失效")
		return
	}

	var req struct {
		Content  string `json:"content"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}

	now := time.Now()

	switch share.ShareType {
	case "blog":
		blog, err := models.GetBlogByID(share.TargetID)
		if err != nil {
			apiError(c, http.StatusNotFound, "文章不存在")
			return
		}
		maxEditContentLen := 500 * 1024
		if blog.EditorType == models.PresentationType {
			maxEditContentLen = 20 * 1024 * 1024
		}
		if blog.EditorType == "html" || blog.EditorType == "spreadsheet" || blog.EditorType == "drawing" || blog.EditorType == "mindmap" || blog.EditorType == models.RichDocumentType {
			maxEditContentLen = 5 * 1024 * 1024
		}
		if len(req.Content) > maxEditContentLen {
			apiError(c, http.StatusBadRequest, "内容过大")
			return
		}
		if err := validateContentForType(blog.EditorType, req.Content); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
		if blog.HasPassword() {
			if req.Password == "" || !blog.VerifyPassword(req.Password) {
				apiError(c, http.StatusForbidden, "文章密码错误")
				return
			}
			encoded, err := encodeContentBeforeEncryption(blog.EditorType, req.Content)
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
			blog.BlogContent = req.Content
		}
		blog.ModifyAt = now.Unix()
		if err := blog.Update(); err != nil {
			apiError(c, http.StatusInternalServerError, "保存失败")
			return
		}
	case "document":
		doc, err := models.GetDocumentByID(share.TargetID)
		if err != nil {
			apiError(c, http.StatusNotFound, "文档不存在")
			return
		}
		maxEditContentLen := 500 * 1024
		if doc.DocType == models.PresentationType {
			maxEditContentLen = 20 * 1024 * 1024
		}
		if doc.DocType == "html" || doc.DocType == "spreadsheet" || doc.DocType == "drawing" || doc.DocType == "mindmap" || doc.DocType == models.RichDocumentType {
			maxEditContentLen = 5 * 1024 * 1024
		}
		if len(req.Content) > maxEditContentLen {
			apiError(c, http.StatusBadRequest, "内容过大")
			return
		}
		if err := validateContentForType(doc.DocType, req.Content); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
		if err := models.UpdateDocumentContent(share.TargetID, req.Content, now.Unix()); err != nil {
			apiError(c, http.StatusInternalServerError, "保存失败")
			return
		}
	default:
		apiError(c, http.StatusBadRequest, "该类型不支持编辑")
		return
	}

	apiSuccess(c, gin.H{
		"modify_time": now.Format("2006-01-02 15:04:05"),
	})
}

// UploadShareEditImage lets an edit-token holder upload editor images
// through the same processing and deduplication path as the authenticated editor.
func UploadShareEditImage(c *gin.Context) {
	identify := c.Param("identify")
	token := c.Query("token")
	share, err := models.GetShareByIdentifyWithToken(identify)
	if err != nil || token == "" || share.EditToken == "" || share.EditToken != token {
		apiError(c, http.StatusForbidden, "编辑令牌无效或已失效")
		return
	}
	contentType := ""
	switch share.ShareType {
	case "blog":
		blog, loadErr := models.GetBlogByID(share.TargetID)
		if loadErr == nil {
			contentType = blog.EditorType
			if blog.HasPassword() && !blog.VerifyPassword(c.PostForm("password")) {
				apiError(c, http.StatusForbidden, "文章密码错误")
				return
			}
		}
	case "document":
		doc, loadErr := models.GetDocumentByID(share.TargetID)
		if loadErr == nil {
			contentType = doc.DocType
		}
	}
	if contentType != models.RichDocumentType && contentType != models.PresentationType {
		apiError(c, http.StatusBadRequest, "该类型不支持图片上传")
		return
	}
	c.Set("memberID", share.MemberID)
	c.Set("uploadCategory", "editor")
	UploadImage(c)
}
