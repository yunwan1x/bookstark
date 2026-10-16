package controllers

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

func GetDocTree(c *gin.Context) {
	bookID, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效书籍ID")
		return
	}

	// 所有权校验：只有书籍所有者或管理员可查看文档树
	book, err := models.GetBookByID(bookID)
	if err != nil {
		apiError(c, http.StatusNotFound, "书籍不存在")
		return
	}
	if !checkOwnership(c, book.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	tree, err := models.GetDocTree(bookID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取文档树失败")
		return
	}
	apiSuccess(c, tree)
}

func GetDocument(c *gin.Context) {
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

	prevID, nextID := models.GetDocumentNavigation(id, doc.BookID)

	var modifyTime string
	if doc.ModifyTime != nil {
		modifyTime = doc.ModifyTime.Format("2006-01-02 15:04")
	}

	result := gin.H{
		"document_id":   doc.DocumentID,
		"document_name": doc.DocumentName,
		"identify":      doc.Identify,
		"book_id":       doc.BookID,
		"parent_id":     doc.ParentID,
		"markdown":      doc.Markdown,
		"doc_type":      doc.DocType,
		"prev_id":       prevID,
		"next_id":       nextID,
		"modify_time":   modifyTime,
	}
	if doc.DocType == "html" || doc.DocType == models.RichDocumentType {
		result["markdown"] = ""
		result["content_url"] = documentHTMLContentURL(doc.DocumentID)
		result["content_encoding"] = "gzip"
		result["content_compressed"] = models.IsCompressedContent(doc.Markdown)
	}
	recordRecentContent(c, "document", doc.DocumentID, "")
	apiSuccess(c, result)
}

func CreateDocument(c *gin.Context) {
	bookID, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效书籍ID")
		return
	}

	// 所有权校验：只有书籍所有者或管理员可创建文档
	book, err := models.GetBookByID(bookID)
	if err != nil {
		apiError(c, http.StatusNotFound, "书籍不存在")
		return
	}
	if !checkOwnership(c, book.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	var req struct {
		DocumentName string `json:"document_name"`
		ParentID     int64  `json:"parent_id"`
		DocType      string `json:"doc_type"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if req.DocumentName == "" {
		req.DocumentName = "未命名文档"
	}

	if !isSupportedDocumentType(req.DocType) {
		apiError(c, http.StatusBadRequest, "不支持的文档类型")
		return
	}

	if len(req.DocumentName) > 200 {
		apiError(c, http.StatusBadRequest, "文档名称不能超过200个字符")
		return
	}

	memberID := middleware.GetMemberID(c)
	if req.DocType == "" {
		req.DocType = "markdown"
	}
	doc := &models.Document{
		DocumentName: req.DocumentName,
		Identify:     generateIdentify("doc"),
		BookID:       bookID,
		ParentID:     req.ParentID,
		OrderSort:    0,
		DocType:      req.DocType,
		Markdown:     "",
		MemberID:     memberID,
		CreateTime:   time.Now(),
	}

	if err := doc.Insert(); err != nil {
		apiError(c, http.StatusInternalServerError, "创建文档失败")
		return
	}

	apiSuccess(c, doc)
}

func UpdateDocument(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效文档ID")
		return
	}

	var req struct {
		DocumentName string `json:"document_name"`
		Markdown     string `json:"markdown"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	if req.DocumentName != "" && len(req.DocumentName) > 200 {
		apiError(c, http.StatusBadRequest, "文档名称不能超过200个字符")
		return
	}

	// Ownership check (moved before size check so we can use doc.DocType)
	doc, err := models.GetDocumentByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "文档不存在")
		return
	}
	if !checkOwnership(c, doc.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	maxContentLen := 500000
	if doc.DocType == models.PresentationType {
		maxContentLen = 20 * 1024 * 1024
	}
	if doc.DocType == "html" || doc.DocType == "spreadsheet" || doc.DocType == "drawing" || doc.DocType == "mindmap" || doc.DocType == models.RichDocumentType {
		maxContentLen = 5242880
	}
	if len(req.Markdown) > maxContentLen {
		if doc.DocType == "html" {
			apiError(c, http.StatusBadRequest, "HTML内容不能超过5MB")
		} else if doc.DocType == "spreadsheet" {
			apiError(c, http.StatusBadRequest, "电子表格内容不能超过5MB")
		} else if doc.DocType == "drawing" {
			apiError(c, http.StatusBadRequest, "画板内容不能超过5MB")
		} else if doc.DocType == "mindmap" {
			apiError(c, http.StatusBadRequest, "脑图内容不能超过5MB")
		} else if doc.DocType == models.RichDocumentType {
			apiError(c, http.StatusBadRequest, "富文档内容不能超过5MB")
		} else if doc.DocType == models.PresentationType {
			apiError(c, http.StatusBadRequest, "演示文稿内容不能超过20MB")
		} else {
			apiError(c, http.StatusBadRequest, "文档内容不能超过500KB")
		}
		return
	}
	if doc.DocType == models.RichDocumentType && (req.Markdown != "" || req.DocumentName == "") {
		if err := models.ValidateRichDocument(req.Markdown); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
	}
	if doc.DocType == models.PresentationType && (req.Markdown != "" || req.DocumentName == "") {
		if err := models.ValidatePresentation(req.Markdown); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
	}

	memberID := middleware.GetMemberID(c)

	if req.DocumentName != "" {
		if err := models.UpdateDocumentName(id, req.DocumentName); err != nil {
			apiError(c, http.StatusInternalServerError, "更新失败")
			return
		}
	}

	if req.Markdown != "" || req.DocumentName == "" {
		if err := models.UpdateDocumentContent(id, req.Markdown, memberID); err != nil {
			apiError(c, http.StatusInternalServerError, "保存失败")
			return
		}
	}

	apiSuccessMsg(c, "保存成功")
}

func DeleteDocument(c *gin.Context) {
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

	if err := models.DeleteDocument(id); err != nil {
		if strings.Contains(err.Error(), "不存在") {
			apiError(c, http.StatusNotFound, err.Error())
		} else {
			apiError(c, http.StatusBadRequest, err.Error())
		}
		return
	}

	apiSuccessMsg(c, "删除成功")
}

func SortDocument(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效文档ID")
		return
	}

	var req struct {
		OrderSort int `json:"order_sort" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请提供排序值")
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

	if err := models.SortDocument(id, req.OrderSort); err != nil {
		apiError(c, http.StatusInternalServerError, "排序失败")
		return
	}

	apiSuccessMsg(c, "排序成功")
}

func ReorderDocument(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效文档ID")
		return
	}

	var req struct {
		Direction string `json:"direction" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请提供排序方向")
		return
	}

	if req.Direction != "up" && req.Direction != "down" && req.Direction != "indent" && req.Direction != "outdent" {
		apiError(c, http.StatusBadRequest, "无效的排序方向")
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

	if err := models.ReorderDocument(id, req.Direction); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}

	apiSuccessMsg(c, "排序成功")
}

func MoveDocument(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效文档ID")
		return
	}

	var req struct {
		ParentID  int64 `json:"parent_id"`
		OrderSort int   `json:"order_sort"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
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

	// 校验父文档属于同一书籍
	if req.ParentID > 0 {
		parentDoc, err := models.GetDocumentByID(req.ParentID)
		if err != nil {
			apiError(c, http.StatusBadRequest, "父文档不存在")
			return
		}
		if parentDoc.BookID != doc.BookID {
			apiError(c, http.StatusBadRequest, "父文档不属于同一书籍")
			return
		}
	}

	if err := models.MoveDocument(id, req.ParentID, req.OrderSort); err != nil {
		apiError(c, http.StatusInternalServerError, "移动失败")
		return
	}

	apiSuccessMsg(c, "移动成功")
}
