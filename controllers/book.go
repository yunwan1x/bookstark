package controllers

import (
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

func IndexPage(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	pageSize := getPageSize(c, "page_size_books", "12")
	books, total, err := models.ListBooksPaged(memberID, 1, pageSize, "")
	if err != nil {
		log.Printf("IndexPage: ListBooksPaged failed: %v", err)
	}
	data := commonData(c, "books")
	data["Books"] = books
	data["Total"] = total
	data["Page"] = 1
	data["PageSize"] = pageSize
	c.HTML(http.StatusOK, "index.html", data)
}

func GetBook(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	book, err := models.GetBookByID(id)
	if err != nil || book.BookID == 0 {
		apiError(c, http.StatusNotFound, "书籍不存在")
		return
	}
	if book.MemberID != memberID {
		apiError(c, http.StatusForbidden, "无权访问")
		return
	}
	labels, _ := models.GetLabelsByResource(book.BookID, "book")
	type bookDetail struct {
		models.Book
		Labels []string `json:"labels"`
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "data": bookDetail{Book: *book, Labels: labels}})
}

func ListBooks(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, "page_size_books", "12")
	keyword := c.Query("keyword")
	if page < 1 {
		page = 1
	}
	books, total, err := models.ListBooksPaged(memberID, page, pageSize, keyword)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取书籍列表失败")
		return
	}
	apiListSuccess(c, books, total, page, pageSize)
}

func CreateBook(c *gin.Context) {
	var req struct {
		BookName    string `json:"book_name" binding:"required"`
		Identify    string `json:"identify"`
		Description string `json:"description"`
		Labels      string `json:"labels"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入书籍名称")
		return
	}

	if len(req.BookName) > 200 {
		apiError(c, http.StatusBadRequest, "书籍名称不能超过200个字符")
		return
	}
	if len(req.Description) > 2000 {
		apiError(c, http.StatusBadRequest, "描述不能超过2000个字符")
		return
	}

	if req.Identify == "" {
		req.Identify = generateIdentify("book")
	}

	memberID := middleware.GetMemberID(c)

	exists, err := models.BookNameExists(req.BookName, memberID, 0)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "检查书籍名称失败")
		return
	}
	if exists {
		apiError(c, http.StatusConflict, "已存在同名书籍")
		return
	}

	book := &models.Book{
		BookName:    req.BookName,
		Identify:    req.Identify,
		Description: req.Description,
		Label:       req.Labels,
		MemberID:    memberID,
		CreateTime:  time.Now(),
	}

	if err := book.Insert(); err != nil {
		apiError(c, http.StatusBadRequest, "创建失败，标识可能已存在")
		return
	}

	if req.Labels != "" {
		models.BindLabelsFromNames(book.BookID, "book", req.Labels)
	}

	// 同步 label 字段（以 md_label_relation 为准）
	if err := models.SyncResourceLabelField(book.BookID, "book"); err != nil {
		log.Printf("CreateBook: SyncResourceLabelField failed for book %d: %v", book.BookID, err)
	}

	apiSuccess(c, book)
}

func UpdateBook(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	var req struct {
		BookName    string `json:"book_name" binding:"required"`
		Description string `json:"description"`
		Labels      string `json:"labels"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入书籍名称")
		return
	}

	if len(req.BookName) > 200 {
		apiError(c, http.StatusBadRequest, "书籍名称不能超过200个字符")
		return
	}
	if len(req.Description) > 2000 {
		apiError(c, http.StatusBadRequest, "描述不能超过2000个字符")
		return
	}

	book, err := models.GetBookByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书籍不存在")
		return
	}

	if !checkOwnership(c, book.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	// 检查重名（排除自身）
	nameExists, _ := models.BookNameExists(req.BookName, book.MemberID, id)
	if nameExists {
		apiError(c, http.StatusConflict, "已存在同名书籍")
		return
	}

	book.BookName = req.BookName
	book.Description = req.Description
	book.Label = req.Labels

	if err := book.Update(); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}

	// 始终同步标签关联（空标签时清除旧关联）
	models.RebindLabels(id, "book", req.Labels)

	// 同步 label 字段（以 md_label_relation 为准）
	if err := models.SyncResourceLabelField(id, "book"); err != nil {
		log.Printf("UpdateBook: SyncResourceLabelField failed for book %d: %v", id, err)
	}

	apiSuccessMsg(c, "更新成功")
}

func DeleteBook(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	book, err := models.GetBookByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书籍不存在")
		return
	}
	if !checkOwnership(c, book.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if err := models.DeleteBook(id); err != nil {
		if strings.Contains(err.Error(), "不存在") {
			apiError(c, http.StatusNotFound, err.Error())
		} else {
			apiError(c, http.StatusInternalServerError, "删除失败")
		}
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func EditorPage(c *gin.Context) {
	identify := c.Param("identify")
	book, err := models.GetBookByIdentify(identify)
	if err != nil {
		c.String(http.StatusNotFound, "书籍不存在")
		return
	}

	if !checkOwnership(c, book.MemberID) {
		forbidden(c)
		return
	}

	data := commonData(c, "books")
	data["EditorType"] = "book"
	data["Book"] = book
	data["Labels"] = "" // 标签在文档加载后由前端动态获取
	data["SaveInterval"] = models.GetSettingWithDefault("save_interval", "30")
	data["AISystemPromptMD"] = models.GetSetting("ai_system_prompt_md")
	data["AISystemPromptHTML"] = models.GetSetting("ai_system_prompt_html")
	data["AISystemPromptDrawing"] = models.GetSetting("ai_system_prompt_drawing")
	data["AIActionsSelection"] = models.GetSetting("ai_actions_selection")
	data["AIActionsHTML"] = models.GetSetting("ai_actions_html")
	data["AIActionsBook"] = models.GetSetting("ai_actions_book")
	data["AIActionsArticle"] = models.GetSetting("ai_actions_article")
	data["AIActionsEmpty"] = models.GetSetting("ai_actions_empty")
	c.HTML(http.StatusOK, "editor.html", data)
}
