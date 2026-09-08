package controllers

import (
	"net/http"
	"net/url"
	"strconv"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

func blogHTMLContentURL(id int64) string {
	return "/api/blogs/" + strconv.FormatInt(id, 10) + "/content/raw"
}

func documentHTMLContentURL(id int64) string {
	return "/api/docs/" + strconv.FormatInt(id, 10) + "/content/raw"
}

func shareHTMLContentURL(identify string) string {
	return "/api/shares/" + url.PathEscape(identify) + "/content/raw"
}

func bookShareDocHTMLContentURL(shareIdentify, docIdentify string) string {
	return "/api/shares/" + url.PathEscape(shareIdentify) + "/docs/" + url.PathEscape(docIdentify) + "/content/raw"
}

func shareEditHTMLContentURL(identify, token string) string {
	return "/api/shares/" + url.PathEscape(identify) + "/edit/content/raw?token=" + url.QueryEscape(token)
}

func prepareShareHTMLPayload(detail *models.ShareDetail) {
	if detail == nil || !isRawContentType(detail.DocType) {
		return
	}
	if !detail.HasPassword {
		detail.ContentURL = shareHTMLContentURL(detail.ShareIdentify)
	}
	detail.Content = ""
}

func isRawContentType(contentType string) bool {
	return contentType == "html" || contentType == models.RichDocumentType
}

func rawContentMIME(contentType string) string {
	if contentType == models.RichDocumentType {
		return "application/json; charset=utf-8"
	}
	if contentType == "html" {
		return "text/html; charset=utf-8"
	}
	return "text/plain; charset=utf-8"
}

func writeRawContent(c *gin.Context, contentType, content string) {
	mime := rawContentMIME(contentType)
	c.Header("Content-Type", mime)
	c.Header("Cache-Control", "no-store")
	if models.IsCompressedContent(content) {
		gzipBytes, err := models.CompressedContentGzipBytes(content)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "读取压缩内容失败")
			return
		}
		c.Header("Content-Encoding", "gzip")
		c.Header("Vary", "Accept-Encoding")
		c.Data(http.StatusOK, mime, gzipBytes)
		return
	}
	c.Data(http.StatusOK, mime, []byte(content))
}

func GetBlogHTMLRawContent(c *gin.Context) {
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
	if !isRawContentType(blog.EditorType) {
		apiError(c, http.StatusBadRequest, "不是可读取的原始内容")
		return
	}
	if blog.HasPassword() {
		apiError(c, http.StatusForbidden, "请先验证密码")
		return
	}
	writeRawContent(c, blog.EditorType, blog.BlogContent)
}

func VerifyBlogPasswordRaw(c *gin.Context) {
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
	if !isRawContentType(blog.EditorType) {
		apiError(c, http.StatusBadRequest, "不是可读取的原始内容")
		return
	}
	if !blog.HasPassword() {
		writeRawContent(c, blog.EditorType, blog.BlogContent)
		return
	}
	if !blog.VerifyPassword(req.Password) {
		apiError(c, http.StatusBadRequest, "密码不正确")
		return
	}
	content := blog.BlogContent
	if models.IsEncrypted(content) {
		plain, err := models.DecryptContent(req.Password, content)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "解密内容失败")
			return
		}
		content = plain
	}
	writeRawContent(c, blog.EditorType, content)
}

func GetDocumentHTMLRawContent(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效文档ID")
		return
	}
	doc, err := models.GetDocumentByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "文档不存在")
		return
	}
	if !checkOwnership(c, doc.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}
	if !isRawContentType(doc.DocType) {
		apiError(c, http.StatusBadRequest, "不是可读取的原始内容")
		return
	}
	writeRawContent(c, doc.DocType, doc.Markdown)
}

func GetShareHTMLRawContent(c *gin.Context) {
	identify := c.Param("identify")
	detail, err := models.GetShareDetailByIdentify(identify)
	if err != nil {
		apiError(c, http.StatusNotFound, "分享内容不存在")
		return
	}
	if !isRawContentType(detail.DocType) {
		apiError(c, http.StatusBadRequest, "不是可读取的原始内容")
		return
	}
	if detail.HasPassword {
		apiError(c, http.StatusForbidden, "请先验证密码")
		return
	}
	writeRawContent(c, detail.DocType, detail.Content)
}

func VerifySharePasswordRaw(c *gin.Context) {
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
	if detail.ShareType != "blog" || !isRawContentType(detail.DocType) {
		apiError(c, http.StatusBadRequest, "不支持的类型")
		return
	}
	blog, err := models.GetBlogByID(detail.TargetID)
	if err != nil {
		apiError(c, http.StatusNotFound, "博客不存在")
		return
	}
	if !blog.VerifyPassword(req.Password) {
		apiError(c, http.StatusBadRequest, "密码不正确")
		return
	}
	content := blog.BlogContent
	if models.IsEncrypted(content) {
		plain, err := models.DecryptContent(req.Password, content)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "解密内容失败")
			return
		}
		content = plain
	}
	writeRawContent(c, detail.DocType, content)
}

func GetBookShareDocHTMLRawContent(c *gin.Context) {
	identify := c.Param("identify")
	docIdentify := c.Param("docIdentify")
	share, err := models.GetShareDetailByIdentify(identify)
	if err != nil || share.ShareType != "book" {
		apiError(c, http.StatusNotFound, "分享不存在")
		return
	}
	doc, err := models.GetDocumentByIdentify(docIdentify)
	if err != nil {
		apiError(c, http.StatusNotFound, "文档不存在")
		return
	}
	if doc.BookID != share.TargetID {
		apiError(c, http.StatusForbidden, "无权访问")
		return
	}
	if !isRawContentType(doc.DocType) {
		apiError(c, http.StatusBadRequest, "不是可读取的原始内容")
		return
	}
	writeRawContent(c, doc.DocType, doc.Markdown)
}

func GetShareEditHTMLRawContent(c *gin.Context) {
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
	switch share.ShareType {
	case "blog":
		blog, err := models.GetBlogByID(share.TargetID)
		if err != nil {
			apiError(c, http.StatusNotFound, "文章不存在")
			return
		}
		if !isRawContentType(blog.EditorType) {
			apiError(c, http.StatusBadRequest, "不是可读取的原始内容")
			return
		}
		if blog.HasPassword() {
			apiError(c, http.StatusForbidden, "请先验证文章密码")
			return
		}
		writeRawContent(c, blog.EditorType, blog.BlogContent)
	case "document":
		doc, err := models.GetDocumentByID(share.TargetID)
		if err != nil {
			apiError(c, http.StatusNotFound, "文档不存在")
			return
		}
		if !isRawContentType(doc.DocType) {
			apiError(c, http.StatusBadRequest, "不是可读取的原始内容")
			return
		}
		writeRawContent(c, doc.DocType, doc.Markdown)
	default:
		apiError(c, http.StatusBadRequest, "该类型不支持编辑")
	}
}

func UnlockShareEditRawContent(c *gin.Context) {
	identify := c.Param("identify")
	token := c.Query("token")
	var req struct {
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入文章密码")
		return
	}
	share, err := models.GetShareByIdentifyWithToken(identify)
	if err != nil || token == "" || share.EditToken == "" || share.EditToken != token {
		apiError(c, http.StatusForbidden, "编辑令牌无效")
		return
	}
	if share.ShareType != "blog" {
		apiError(c, http.StatusBadRequest, "该分享不需要密码")
		return
	}
	blog, err := models.GetBlogByID(share.TargetID)
	if err != nil || !isSupportedDocumentType(blog.EditorType) {
		apiError(c, http.StatusBadRequest, "不支持的内容类型")
		return
	}
	if !blog.HasPassword() || !blog.VerifyPassword(req.Password) {
		apiError(c, http.StatusForbidden, "文章密码错误")
		return
	}
	content := blog.BlogContent
	if models.IsEncrypted(content) {
		content, err = models.DecryptContent(req.Password, content)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "解密内容失败")
			return
		}
	}
	writeRawContent(c, blog.EditorType, content)
}
