package controllers

import (
	"encoding/json"
	"html/template"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

// BookmarksPage 书签导航页（公开，无需登录，但按用户过滤数据）
func BookmarksPage(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	isLoggedIn := memberID > 0

	data := commonData(c, "bookmarks")
	data["IsLoggedIn"] = isLoggedIn
	data["MemberID"] = memberID
	data["PageSize"] = getPageSize(c, "page_size_bookmarks", "20")

	var labels []string
	if isLoggedIn {
		var err error
		labels, err = models.ListBookmarkLabels(memberID)
		if err != nil {
			log.Printf("BookmarksPage: ListBookmarkLabels failed: %v", err)
		}
	} else {
		var err error
		labels, err = models.ListPublicBookmarkLabels()
		if err != nil {
			log.Printf("BookmarksPage: ListPublicBookmarkLabels failed: %v", err)
		}
	}
	if labels == nil {
		labels = []string{}
	}
	labelsJSON, err := json.Marshal(labels)
	if err != nil {
		log.Printf("BookmarksPage: json.Marshal labels failed: %v", err)
		labelsJSON = []byte("[]")
	}
	safeJSON := strings.ReplaceAll(string(labelsJSON), "</script", `<\/script`)
	safeJSON = strings.ReplaceAll(safeJSON, "</Script", `<\/script`)
	safeJSON = strings.ReplaceAll(safeJSON, "</SCRIPT", `<\/script`)
	data["BookmarkLabelsJSON"] = template.JS(safeJSON)

	c.HTML(http.StatusOK, "bookmarks.html", data)
}

// ListBookmarkLabels 获取书签标签列表（支持 scope 参数）
func ListBookmarkLabels(c *gin.Context) {
	scope := c.DefaultQuery("scope", "mine")

	var labels []string
	var err error

	switch scope {
	case "public":
		labels, err = models.ListPublicBookmarkLabels()
	default:
		memberID := middleware.GetMemberID(c)
		if memberID > 0 {
			labels, err = models.ListBookmarkLabels(memberID)
		} else {
			labels = []string{}
		}
	}

	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取标签列表失败")
		return
	}
	if labels == nil {
		labels = []string{}
	}
	apiSuccess(c, labels)
}

// ListBookmarkLabelsWithCount 获取书签标签列表（含数量，用于高级搜索）
func ListBookmarkLabelsWithCount(c *gin.Context) {
	scope := c.DefaultQuery("scope", "mine")

	var labels []models.BookmarkLabelCount
	var err error

	switch scope {
	case "public":
		labels, err = models.ListPublicBookmarkLabelsWithCount()
	default:
		memberID := middleware.GetMemberID(c)
		if memberID > 0 {
			labels, err = models.ListBookmarkLabelsWithCount(memberID)
		} else {
			labels = []models.BookmarkLabelCount{}
		}
	}

	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取标签列表失败")
		return
	}
	if labels == nil {
		labels = []models.BookmarkLabelCount{}
	}
	apiSuccess(c, labels)
}

// metaClient 全局共享的 HTTP client，限制连接数和超时，防止并发请求耗尽文件描述符
var metaClient = &http.Client{
	Timeout: 8 * time.Second,
	Transport: &http.Transport{
		MaxIdleConns:        10,
		MaxConnsPerHost:     5,
		IdleConnTimeout:     30 * time.Second,
		DisableKeepAlives:   false,
		DisableCompression:  true,
	},
}

// FetchBookmarkMeta 抓取 URL 的标题和描述
func FetchBookmarkMeta(c *gin.Context) {
	var req struct {
		URL string `json:"url" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入URL")
		return
	}

	if r := isSafeURL(req.URL); !r.Safe {
		apiError(c, http.StatusBadRequest, r.Reason)
		return
	}

	httpReq, err := http.NewRequest("GET", req.URL, nil)
	if err != nil {
		apiError(c, http.StatusBadRequest, "URL格式错误")
		return
	}
	httpReq.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	httpReq.Header.Set("Accept", "text/html,application/xhtml+xml")
	resp, err := metaClient.Do(httpReq)
	if err != nil {
		apiSuccess(c, gin.H{"title": "", "description": "", "error": "无法访问该URL"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		apiSuccess(c, gin.H{"title": "", "description": "", "error": "HTTP " + strconv.Itoa(resp.StatusCode)})
		return
	}

	// 只读前 32KB
	body := io.LimitReader(resp.Body, 32*1024)
	data, readErr := io.ReadAll(body)
	if readErr != nil {
		log.Printf("FetchBookmarkMeta: io.ReadAll failed: %v", readErr)
		apiSuccess(c, gin.H{"title": "", "description": ""})
		return
	}
	html := string(data)

	title := extractMeta(html, "title")
	desc := extractMeta(html, "description")
	favicon := extractFaviconURL(html, req.URL)

	apiSuccess(c, gin.H{"title": title, "description": desc, "favicon": favicon})
}

// extractMeta 从 HTML 中提取 title 或 meta description
func extractMeta(html, field string) string {
	// 只在 <head> 范围内查找，缩小搜索范围
	headEnd := strings.Index(strings.ToLower(html), "</head>")
	searchHTML := html
	if headEnd > 0 {
		searchHTML = html[:headEnd]
	}

	if field == "title" {
		lower := strings.ToLower(searchHTML)
		start := strings.Index(lower, "<title")
		if start == -1 {
			return ""
		}
		// 跳过 <title ...>
		tagContent := searchHTML[start:]
		gt := strings.Index(tagContent, ">")
		if gt == -1 {
			return ""
		}
		content := tagContent[gt+1:]
		end := strings.Index(strings.ToLower(content), "</title>")
		if end == -1 {
			// title 标签被截断，取到末尾
			content = strings.TrimSpace(content)
			if len(content) > 200 {
				content = content[:200]
			}
			return decodeHTMLEntities(content)
		}
		return strings.TrimSpace(decodeHTMLEntities(content[:end]))
	}

	// meta description
	lower := strings.ToLower(searchHTML)
	idx := strings.Index(lower, `name="description"`)
	if idx == -1 {
		idx = strings.Index(lower, `name='description'`)
	}
	if idx == -1 {
		return ""
	}

	sub := searchHTML[idx:]
	ci := strings.Index(sub, `content="`)
	if ci == -1 {
		ci = strings.Index(sub, `content='`)
		if ci == -1 {
			return ""
		}
		val := sub[ci+9:]
		end := strings.Index(val, "'")
		if end == -1 {
			return ""
		}
		return strings.TrimSpace(decodeHTMLEntities(val[:end]))
	}
	val := sub[ci+9:]
	end := strings.Index(val, `"`)
	if end == -1 {
		return ""
	}
	return strings.TrimSpace(decodeHTMLEntities(val[:end]))
}

// extractFaviconURL 从 HTML <head> 中提取 favicon URL
// 优先级：link[rel="icon" type="svg"] > link[rel="apple-touch-icon"] > link[rel="icon"] > link[rel="shortcut icon"]
// 返回空字符串表示未找到
func extractFaviconURL(html, baseURL string) string {
	headEnd := strings.Index(strings.ToLower(html), "</head>")
	searchHTML := html
	if headEnd > 0 {
		searchHTML = html[:headEnd]
	}

	type linkMatch struct {
		href string
		typ  string
		rel  string
		sizes string
	}

	var matches []linkMatch
	lower := strings.ToLower(searchHTML)
	i := 0
	for {
		idx := strings.Index(lower[i:], "<link ")
		if idx == -1 {
			break
		}
		pos := i + idx
		// Find end of tag
		end := strings.Index(searchHTML[pos:], ">")
		if end == -1 {
			break
		}
		tag := searchHTML[pos : pos+end+1]
		i = pos + end + 1

		tagLower := strings.ToLower(tag)

		// Check if it's a favicon link
		isFavicon := false
		if strings.Contains(tagLower, `rel="icon"`) ||
			strings.Contains(tagLower, `rel='icon'`) ||
			strings.Contains(tagLower, `rel="shortcut icon"`) ||
			strings.Contains(tagLower, `rel='shortcut icon'`) ||
			strings.Contains(tagLower, `rel="apple-touch-icon"`) ||
			strings.Contains(tagLower, `rel='apple-touch-icon'`) ||
			strings.Contains(tagLower, `rel="apple-touch-icon-precomposed"`) ||
			strings.Contains(tagLower, `rel='apple-touch-icon-precomposed'`) {
			isFavicon = true
		}
		if !isFavicon {
			continue
		}

		href := extractAttr(tag, "href")
		if href == "" {
			continue
		}

		m := linkMatch{
			href:  decodeHTMLEntities(href),
			typ:   strings.ToLower(extractAttr(tag, "type")),
			rel:   strings.ToLower(extractAttr(tag, "rel")),
			sizes: extractAttr(tag, "sizes"),
		}
		matches = append(matches, m)
	}

	if len(matches) == 0 {
		return ""
	}

	// Priority: SVG > apple-touch-icon (largest) > icon with highest sizes > shortcut icon
	best := -1
	bestPriority := 0
	for idx, m := range matches {
		priority := 0
		if strings.Contains(m.typ, "svg") {
			priority = 100
		} else if strings.Contains(m.rel, "apple-touch-icon") {
			priority = 50
			// Prefer larger sizes
			if strings.Contains(m.sizes, "180x180") {
				priority = 55
			} else if strings.Contains(m.sizes, "152x152") {
				priority = 53
			}
		} else if m.rel == "icon" {
			priority = 30
			if strings.Contains(m.sizes, "32x32") {
				priority = 35
			}
		} else if strings.Contains(m.rel, "shortcut icon") {
			priority = 10
		}
		if priority > bestPriority {
			bestPriority = priority
			best = idx
		}
	}

	if best == -1 {
		best = 0
	}

	href := matches[best].href

	// Resolve relative URL
	if strings.HasPrefix(href, "//") {
		base, err := url.Parse(baseURL)
		if err != nil {
			return ""
		}
		return base.Scheme + ":" + href
	}
	if strings.HasPrefix(href, "http://") || strings.HasPrefix(href, "https://") {
		return href
	}
	// Relative path
	base, err := url.Parse(baseURL)
	if err != nil {
		return ""
	}
	resolved, err := base.Parse(href)
	if err != nil {
		return ""
	}
	return resolved.String()
}

// extractAttr 从 HTML 标签中提取属性值
func extractAttr(tag, attr string) string {
	lower := strings.ToLower(tag)

	// Search for attr="value" or attr='value'
	for _, q := range []byte{'"', '\''} {
		searchStr := attr + "=" + string(q)
		idx := strings.Index(lower, searchStr)
		if idx == -1 {
			continue
		}
		valStart := idx + len(searchStr)
		end := strings.IndexByte(tag[valStart:], q)
		if end == -1 {
			continue
		}
		return tag[valStart : valStart+end]
	}
	return ""
}

// decodeHTMLEntities 解码常见 HTML 实体
func decodeHTMLEntities(s string) string {
	s = strings.ReplaceAll(s, "&amp;", "&")
	s = strings.ReplaceAll(s, "&lt;", "<")
	s = strings.ReplaceAll(s, "&gt;", ">")
	s = strings.ReplaceAll(s, "&quot;", "\"")
	s = strings.ReplaceAll(s, "&#39;", "'")
	s = strings.ReplaceAll(s, "&nbsp;", " ")
	return s
}

// isValidURL 校验 URL 格式是否合法
func isValidURL(rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return false
	}
	if u.Host == "" {
		return false
	}
	return true
}

// ListBookmarks 获取书签列表（分页+筛选）
func ListBookmarks(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, "page_size_bookmarks", "20")
	keyword := c.Query("keyword")
	startTime := parseTimeQuery(c.Query("start_time"))
	endTime := parseTimeQuery(c.Query("end_time"))
	timeField := c.DefaultQuery("time_field", "create")

	// 支持多标签：labels=AI,对话 或 label=AI&label=对话
	var labels []string
	if labelsParam := c.Query("labels"); labelsParam != "" {
		for _, l := range splitByComma(labelsParam) {
			if l != "" {
				labels = append(labels, l)
			}
		}
	}
	for _, l := range c.QueryArray("label") {
		if l != "" {
			labels = append(labels, l)
		}
	}

	// OR 逻辑标签：labels_or=AI,对话
	var labelsOr []string
	if labelsOrParam := c.Query("labels_or"); labelsOrParam != "" {
		for _, l := range splitByComma(labelsOrParam) {
			if l != "" {
				labelsOr = append(labelsOr, l)
			}
		}
	}

	// scope 参数：mine（默认）或 public
	scope := c.DefaultQuery("scope", "mine")

	var isPublic *bool
	var memberID int64
	var withAccount bool

	switch scope {
	case "public":
		pub := true
		isPublic = &pub
		memberID = 0
		withAccount = true
	default: // mine
		memberID = middleware.GetMemberID(c)
		if memberID == 0 {
			apiListSuccess(c, []interface{}{}, 0, 1, pageSize)
			return
		}
	}

	// 高级搜索：is_public 和 no_label 筛选
	if isPublicFilter := c.Query("is_public"); isPublicFilter != "" && isPublic == nil {
		v := isPublicFilter == "1" || isPublicFilter == "true"
		isPublic = &v
	}
	var isPinned *bool
	if isPinnedFilter := c.Query("is_pinned"); isPinnedFilter != "" {
		v := isPinnedFilter == "1" || isPinnedFilter == "true"
		isPinned = &v
	}
	var navVisible *bool
	if navVisibleFilter := c.Query("nav_visible"); navVisibleFilter != "" {
		v := navVisibleFilter == "1" || navVisibleFilter == "true"
		navVisible = &v
	}
	noLabel := c.Query("no_label") == "1" || c.Query("no_label") == "true"

	if page < 1 {
		page = 1
	}

	result, err := models.QueryBookmarks(models.BookmarkQuery{
		IsPublic:    isPublic,
		IsPinned:    isPinned,
		NavVisible:  navVisible,
		Labels:      labels,
		LabelsOr:    labelsOr,
		Keyword:     keyword,
		Site:        c.Query("site"),
		MemberID:    memberID,
		NoLabel:     noLabel,
		WithAccount: withAccount,
		StartTime:   startTime,
		EndTime:     endTime,
		TimeField:   timeField,
		Page:        page,
		PageSize:    pageSize,
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取书签列表失败")
		return
	}

	apiListSuccess(c, result.Data, int64(result.Total), result.Page, pageSize)
}

// splitByComma 按逗号分割字符串
func splitByComma(s string) []string {
	if s == "" {
		return nil
	}
	var result []string
	for _, part := range strings.Split(s, ",") {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}

// parseTimeQuery 解析时间查询参数（格式：2006-01-02 或 2006-01-02T15:04:05）
func parseTimeQuery(s string) *time.Time {
	if s == "" {
		return nil
	}
	for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02"} {
		if t, err := time.Parse(layout, s); err == nil {
			return &t
		}
	}
	return nil
}

// CreateBookmark 创建书签
func CreateBookmark(c *gin.Context) {
	var req struct {
		Title       string `json:"title" binding:"required"`
		URL         string `json:"url" binding:"required"`
		Description string `json:"description"`
		Favicon     string `json:"favicon"`
		IsPublic    bool   `json:"is_public"`
		Labels      string `json:"labels"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入标题和URL")
		return
	}

	if len(req.Title) > 500 {
		apiError(c, http.StatusBadRequest, "标题不能超过500个字符")
		return
	}
	if len(req.URL) > 2048 {
		apiError(c, http.StatusBadRequest, "URL不能超过2048个字符")
		return
	}
	if !isValidURL(req.URL) {
		apiError(c, http.StatusBadRequest, "URL格式不正确")
		return
	}
	if len(req.Description) > 2000 {
		apiError(c, http.StatusBadRequest, "描述不能超过2000个字符")
		return
	}

	memberID := middleware.GetMemberID(c)

	// 以 url + member_id 查重，有则更新，无则新建
	existing, _ := models.GetBookmarkByURLAndMember(req.URL, memberID)

	var bookmark *models.Bookmark
	var isUpdate bool

	if existing != nil {
		// 更新已有书签
		isUpdate = true
		bookmark = &models.Bookmark{
			BookmarkID:  existing.BookmarkID,
			Title:       req.Title,
			URL:         req.URL,
			Description: req.Description,
			IsPublic:    req.IsPublic,
			OrderSort:   existing.OrderSort,
			Label:       req.Labels,
			MemberID:    memberID,
		}
		if err := bookmark.Update(); err != nil {
			apiError(c, http.StatusInternalServerError, "更新书签失败")
			return
		}
	} else {
		// 新建书签
		bookmark = &models.Bookmark{
			Title:       req.Title,
			URL:         req.URL,
			Description: req.Description,
			Favicon:     req.Favicon,
			IsPublic:    req.IsPublic,
			OrderSort:   0,
			Label:       req.Labels,
			MemberID:    memberID,
		}
		if err := bookmark.Insert(); err != nil {
			apiError(c, http.StatusBadRequest, "创建书签失败")
			return
		}
	}

	// 重新绑定标签
	models.RebindLabels(bookmark.BookmarkID, "bookmark", req.Labels)

	// 同步 label 字段（以 md_label_relation 为准）
	if err := models.SyncResourceLabelField(bookmark.BookmarkID, "bookmark"); err != nil {
		log.Printf("CreateBookmark: SyncResourceLabelField failed for bookmark %d: %v", bookmark.BookmarkID, err)
	}

	if isUpdate {
		c.JSON(http.StatusOK, APIResponse{Code: 0, Message: "书签已更新", Data: bookmark})
	} else {
		apiSuccess(c, bookmark)
	}
}

// UpdateBookmark 更新书签
func UpdateBookmark(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	var req struct {
		Title       string `json:"title"`
		URL         string `json:"url"`
		Description string `json:"description"`
		IsPublic    *bool  `json:"is_public"`
		Labels      string `json:"labels"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	if req.Title != "" && len(req.Title) > 500 {
		apiError(c, http.StatusBadRequest, "标题不能超过500个字符")
		return
	}
	if req.URL != "" {
		if len(req.URL) > 2048 {
			apiError(c, http.StatusBadRequest, "URL不能超过2048个字符")
			return
		}
		if !isValidURL(req.URL) {
			apiError(c, http.StatusBadRequest, "URL格式不正确")
			return
		}
	}
	if len(req.Description) > 2000 {
		apiError(c, http.StatusBadRequest, "描述不能超过2000个字符")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}

	if !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if req.Title != "" {
		bookmark.Title = req.Title
	}
	if req.URL != "" {
		bookmark.URL = req.URL
		bookmark.Favicon = ""
	}
	bookmark.Description = req.Description
	if req.IsPublic != nil {
		bookmark.IsPublic = *req.IsPublic
	}
	bookmark.Label = req.Labels

	if err := bookmark.Update(); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}

	models.RebindLabels(id, "bookmark", req.Labels)

	// 同步 label 字段（以 md_label_relation 为准）
	if err := models.SyncResourceLabelField(id, "bookmark"); err != nil {
		log.Printf("UpdateBookmark: SyncResourceLabelField failed for bookmark %d: %v", id, err)
	}

	apiSuccessMsg(c, "更新成功")
}

// ToggleBookmarkPublic 切换书签公开状态
func ToggleBookmarkPublic(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	var req struct {
		IsPublic bool `json:"is_public"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}
	if !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if err := models.ToggleBookmarkPublic(id, req.IsPublic); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}
	apiSuccessMsg(c, "更新成功")
}

// RefreshBookmarkFavicon 刷新书签的 favicon（从 HTML 中提取真实 favicon URL）
func RefreshBookmarkFavicon(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}
	if !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if r := isSafeURL(bookmark.URL); !r.Safe {
		apiSuccess(c, gin.H{"favicon": bookmark.Favicon, "updated": false})
		return
	}

	httpReq, err := http.NewRequest("GET", bookmark.URL, nil)
	if err != nil {
		apiSuccess(c, gin.H{"favicon": bookmark.Favicon, "updated": false})
		return
	}
	httpReq.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	httpReq.Header.Set("Accept", "text/html,application/xhtml+xml")

	resp, err := metaClient.Do(httpReq)
	if err != nil {
		apiSuccess(c, gin.H{"favicon": bookmark.Favicon, "updated": false})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		apiSuccess(c, gin.H{"favicon": bookmark.Favicon, "updated": false})
		return
	}

	body := io.LimitReader(resp.Body, 32*1024)
	data, _ := io.ReadAll(body)
	favicon := extractFaviconURL(string(data), bookmark.URL)

	if favicon == "" {
		apiSuccess(c, gin.H{"favicon": bookmark.Favicon, "updated": false})
		return
	}

	if err := models.UpdateBookmarkFavicon(id, favicon); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}

	apiSuccess(c, gin.H{"favicon": favicon, "updated": true})
}

// DeleteBookmark 删除书签
func DeleteBookmark(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}
	if !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if err := models.DeleteBookmark(id); err != nil {
		if strings.Contains(err.Error(), "不存在") {
			apiError(c, http.StatusNotFound, err.Error())
		} else {
			apiError(c, http.StatusInternalServerError, "删除失败")
		}
		return
	}
	apiSuccessMsg(c, "删除成功")
}

// BookmarkFilter 批量操作的筛选条件
type BookmarkFilter struct {
	Scope      string `json:"scope"`
	Labels     string `json:"labels"`
	LabelsOr   string `json:"labels_or"`
	Keyword    string `json:"keyword"`
	Site       string `json:"site"`
	IsPublic   string `json:"is_public"`
	IsPinned   string `json:"is_pinned"`
	NavVisible string `json:"nav_visible"`
	NoLabel    string `json:"no_label"`
	StartTime  string `json:"start_time"`
	EndTime    string `json:"end_time"`
	TimeField  string `json:"time_field"`
}

// resolveBookmarkIDs 根据 filter 筛选条件解析出书签ID列表
func resolveBookmarkIDs(c *gin.Context, filter *BookmarkFilter) ([]int64, error) {
	if filter == nil {
		return nil, nil
	}

	memberID := middleware.GetMemberID(c)
	var isPublic *bool
	var qMemberID int64

	switch filter.Scope {
	case "public":
		pub := true
		isPublic = &pub
		qMemberID = 0
	default: // mine
		qMemberID = memberID
	}

	if filter.IsPublic != "" && isPublic == nil {
		v := filter.IsPublic == "1" || filter.IsPublic == "true"
		isPublic = &v
	}
	var isPinned *bool
	if filter.IsPinned != "" {
		v := filter.IsPinned == "1" || filter.IsPinned == "true"
		isPinned = &v
	}
	var navVisible *bool
	if filter.NavVisible != "" {
		v := filter.NavVisible == "1" || filter.NavVisible == "true"
		navVisible = &v
	}

	var labels []string
	if filter.Labels != "" {
		for _, l := range splitByComma(filter.Labels) {
			if l != "" {
				labels = append(labels, l)
			}
		}
	}
	var labelsOr []string
	if filter.LabelsOr != "" {
		for _, l := range splitByComma(filter.LabelsOr) {
			if l != "" {
				labelsOr = append(labelsOr, l)
			}
		}
	}

	var startTime, endTime *time.Time
	if filter.StartTime != "" {
		if t, err := time.Parse("2006-01-02T15:04:05", filter.StartTime); err == nil {
			startTime = &t
		}
	}
	if filter.EndTime != "" {
		if t, err := time.Parse("2006-01-02T15:04:05", filter.EndTime); err == nil {
			endTime = &t
		}
	}
	noLabel := filter.NoLabel == "1" || filter.NoLabel == "true"

	ids, err := models.QueryBookmarkIDsByFilter(models.BookmarkQuery{
		MemberID:   qMemberID,
		IsPublic:   isPublic,
		IsPinned:   isPinned,
		NavVisible: navVisible,
		Labels:     labels,
		LabelsOr:   labelsOr,
		Keyword:    filter.Keyword,
		Site:       filter.Site,
		NoLabel:    noLabel,
		StartTime:  startTime,
		EndTime:    endTime,
		TimeField:  filter.TimeField,
	})
	return ids, err
}

// BatchDeleteBookmarks 批量删除书签

// resolveBatchIDs 从请求的 IDs 或 Filter 中解析出书签ID列表
func resolveBatchIDs(c *gin.Context, ids []int64, filter *BookmarkFilter) (resolvedIDs []int64, isFilterMode bool, err error) {
	if len(ids) > 0 {
		return ids, false, nil
	}
	if filter == nil {
		return nil, false, nil
	}
	resolvedIDs, err = resolveBookmarkIDs(c, filter)
	if err != nil {
		return nil, true, err
	}
	return resolvedIDs, true, nil
}

// checkBatchPermission 校验批量操作权限
func checkBatchPermission(c *gin.Context, ids []int64) bool {
	if isAdmin(c) {
		return true
	}
	count, err := models.CountBookmarksByMember(ids, middleware.GetMemberID(c))
	if err != nil {
		apiError(c, http.StatusInternalServerError, "权限校验失败")
		return false
	}
	if count != len(ids) {
		apiError(c, http.StatusForbidden, "无权操作")
		return false
	}
	return true
}

// BatchDeleteBookmarks 批量删除书签
func BatchDeleteBookmarks(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要删除的书签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchDeleteBookmarks(ids); err != nil {
		apiError(c, http.StatusInternalServerError, "批量删除失败")
		return
	}
	apiSuccess(c, gin.H{"message": "删除成功", "count": len(ids)})
}

// BatchShareBookmarks 批量设置书签为公开
func BatchShareBookmarks(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要分享的书签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchSetPublic(ids, true); err != nil {
		apiError(c, http.StatusInternalServerError, "批量分享失败")
		return
	}
	apiSuccess(c, gin.H{"message": "分享成功", "count": len(ids)})
}

// BatchUnshareBookmarks 批量取消书签公开
func BatchUnshareBookmarks(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要取消分享的书签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchSetPublic(ids, false); err != nil {
		apiError(c, http.StatusInternalServerError, "批量取消分享失败")
		return
	}
	apiSuccess(c, gin.H{"message": "取消分享成功", "count": len(ids)})
}

// BatchAddBookmarkLabels 批量为书签添加标签
func BatchAddBookmarkLabels(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Tags   []string        `json:"tags"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 || len(req.Tags) == 0 {
		apiError(c, http.StatusBadRequest, "请选择书签和标签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if len(req.Tags) > 50 {
		apiError(c, http.StatusBadRequest, "标签数量最多50个")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchAddLabels(ids, req.Tags); err != nil {
		apiError(c, http.StatusInternalServerError, "批量添加标签失败")
		return
	}
	apiSuccess(c, gin.H{"message": "添加标签成功", "count": len(ids)})
}

// BatchRemoveBookmarkLabels 批量为书签移除标签
func BatchRemoveBookmarkLabels(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Tags   []string        `json:"tags"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 || len(req.Tags) == 0 {
		apiError(c, http.StatusBadRequest, "请选择书签和标签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if len(req.Tags) > 50 {
		apiError(c, http.StatusBadRequest, "标签数量最多50个")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchRemoveLabels(ids, req.Tags); err != nil {
		apiError(c, http.StatusInternalServerError, "批量移除标签失败")
		return
	}
	apiSuccess(c, gin.H{"message": "移除标签成功", "count": len(ids)})
}

// BatchPinBookmarks 批量设置书签为置顶
func BatchPinBookmarks(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要置顶的书签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchSetPinned(ids, true); err != nil {
		apiError(c, http.StatusInternalServerError, "批量置顶失败")
		return
	}
	apiSuccess(c, gin.H{"message": "置顶成功", "count": len(ids)})
}

// BatchUnpinBookmarks 批量取消书签置顶
func BatchUnpinBookmarks(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要取消置顶的书签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchSetPinned(ids, false); err != nil {
		apiError(c, http.StatusInternalServerError, "批量取消置顶失败")
		return
	}
	apiSuccess(c, gin.H{"message": "取消置顶成功", "count": len(ids)})
}

// BatchShowNavBookmarks 批量设置书签导航页可见
func BatchShowNavBookmarks(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要设置导航页可见的书签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchSetNavVisible(ids, true); err != nil {
		apiError(c, http.StatusInternalServerError, "批量设置导航页可见失败")
		return
	}
	apiSuccess(c, gin.H{"message": "设置导航页可见成功", "count": len(ids)})
}

// BatchHideNavBookmarks 批量设置书签导航页隐藏
func BatchHideNavBookmarks(c *gin.Context) {
	var req struct {
		IDs    []int64         `json:"ids"`
		Filter *BookmarkFilter `json:"filter"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数错误")
		return
	}
	ids, isFilter, err := resolveBatchIDs(c, req.IDs, req.Filter)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询书签失败")
		return
	}
	if len(ids) == 0 {
		apiError(c, http.StatusBadRequest, "请选择要设置导航页隐藏的书签")
		return
	}
	if !isFilter && len(ids) > 200 {
		apiError(c, http.StatusBadRequest, "批量操作最多200条")
		return
	}
	if !checkBatchPermission(c, ids) {
		return
	}
	if err := models.BatchSetNavVisible(ids, false); err != nil {
		apiError(c, http.StatusInternalServerError, "批量设置导航页隐藏失败")
		return
	}
	apiSuccess(c, gin.H{"message": "设置导航页隐藏成功", "count": len(ids)})
}

// SortBookmarks 批量更新书签排序
func SortBookmarks(c *gin.Context) {
	var req struct {
		Items []models.SortItem `json:"items" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}
	if len(req.Items) > 200 {
		apiError(c, http.StatusBadRequest, "排序项最多200条")
		return
	}

	// 所有权校验：验证所有待排序的书签都属于当前用户
	if !isAdmin(c) {
		ids := make([]int64, len(req.Items))
		for i, item := range req.Items {
			ids[i] = item.ID
		}
		memberID := middleware.GetMemberID(c)
		count, err := models.CountBookmarksByMember(ids, memberID)
		if err != nil {
			apiError(c, http.StatusInternalServerError, "校验书签所有权失败")
			return
		}
		if count != len(ids) {
			apiError(c, http.StatusForbidden, "无权操作")
			return
		}
	}

	if err := models.SortBookmarks(req.Items); err != nil {
		apiError(c, http.StatusInternalServerError, "排序失败")
		return
	}
	apiSuccessMsg(c, "排序成功")
}

// ToggleBookmarkPin 切换书签置顶状态（仅管理员）
func ToggleBookmarkPin(c *gin.Context) {
	if !isAdmin(c) {
		apiError(c, http.StatusForbidden, "无权限")
		return
	}
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	pinned, err := models.ToggleBookmarkPin(id)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "操作失败")
		return
	}
	apiSuccess(c, gin.H{"is_pinned": pinned})
}

// NavPage 导航主页
func NavPage(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	isLoggedIn := memberID > 0

	data := commonData(c, "nav")
	data["IsLoggedIn"] = isLoggedIn
	data["MemberID"] = memberID

	c.HTML(http.StatusOK, "nav.html", data)
}

// ListBookmarksGrouped 获取分组聚合的书签（导航主页API）
func ListBookmarksGrouped(c *gin.Context) {
	scope := c.DefaultQuery("scope", "mine")
	keyword := c.Query("keyword")
	groupFilter := c.Query("group")
	var labels []string
	if labelsParam := c.Query("labels"); labelsParam != "" {
		for _, l := range splitByComma(labelsParam) {
			if l != "" {
				labels = append(labels, l)
			}
		}
	}

	var memberID int64
	var isPublic bool
	switch scope {
	case "public":
		isPublic = true
	default:
		memberID = middleware.GetMemberID(c)
		if memberID == 0 {
			apiSuccess(c, &models.BookmarksGroupedResult{})
			return
		}
	}

	result, err := models.QueryBookmarksGrouped(memberID, isPublic, keyword, groupFilter, labels)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取书签失败")
		return
	}
	apiSuccess(c, result)
}

// ToggleBookmarkNavVisible 切换书签导航可见性
func ToggleBookmarkNavVisible(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	var req struct {
		NavVisible bool `json:"nav_visible"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求格式错误")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}
	if !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if err := models.ToggleBookmarkNavVisible(id, req.NavVisible); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}
	apiSuccessMsg(c, "更新成功")
}

// CreateBookmarkCompat linkding 兼容的书签创建接口
// POST /api/bookmarks/ （注意尾部斜杠，兼容 linkding 插件）
// Authorization: Token <api_token>
func CreateBookmarkCompat(c *gin.Context) {
	var req struct {
		URL         string   `json:"url" binding:"required"`
		Title       string   `json:"title"`
		Description string   `json:"description"`
		TagNames    []string `json:"tag_names"`
		Unread      *bool    `json:"unread"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入URL")
		return
	}

	if len(req.URL) > 2048 {
		apiError(c, http.StatusBadRequest, "URL不能超过2048个字符")
		return
	}
	if !isValidURL(req.URL) {
		apiError(c, http.StatusBadRequest, "URL格式不正确")
		return
	}
	if len(req.Title) > 500 {
		apiError(c, http.StatusBadRequest, "标题不能超过500个字符")
		return
	}
	if len(req.Description) > 2000 {
		apiError(c, http.StatusBadRequest, "描述不能超过2000个字符")
		return
	}

	memberID := middleware.GetMemberID(c)

	// 以 url + member_id 查重，有则更新，无则新建
	existing, _ := models.GetBookmarkByURLAndMember(req.URL, memberID)

	// Auto-fetch title if empty
	title := req.Title
	desc := req.Description
	var metaFavicon string
	if r := isSafeURL(req.URL); r.Safe {
		httpReq, err := http.NewRequest("GET", req.URL, nil)
		if err != nil {
			apiError(c, http.StatusBadRequest, "URL格式错误")
			return
		}
		httpReq.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
		httpReq.Header.Set("Accept", "text/html,application/xhtml+xml")
		if resp, err := metaClient.Do(httpReq); err == nil {
			defer resp.Body.Close()
			if resp.StatusCode == 200 {
				body := io.LimitReader(resp.Body, 32*1024)
				data, _ := io.ReadAll(body)
				html := string(data)
				if title == "" {
					title = extractMeta(html, "title")
				}
				if desc == "" {
					desc = extractMeta(html, "description")
				}
				metaFavicon = extractFaviconURL(html, req.URL)
			}
		}
	}

	labels := ""
	if len(req.TagNames) > 0 {
		labels = strings.Join(req.TagNames, ",")
	}

	isPublic := req.Unread == nil || !*req.Unread // unread=true → 不公开, unread=false/nil → 公开

	var bookmark *models.Bookmark

	if existing != nil {
		// 更新已有书签
		bookmark = &models.Bookmark{
			BookmarkID:  existing.BookmarkID,
			Title:       title,
			URL:         req.URL,
			Description: desc,
			Favicon:     existing.Favicon,
			OrderSort:   existing.OrderSort,
			Label:       labels,
			MemberID:    memberID,
			IsPublic:    isPublic,
			NavVisible:  existing.NavVisible,
		}
		if err := bookmark.Update(); err != nil {
			apiError(c, http.StatusInternalServerError, "更新书签失败")
			return
		}
	} else {
		// 新建书签
		bookmark = &models.Bookmark{
			Title:       title,
			URL:         req.URL,
			Description: desc,
			Favicon:     metaFavicon,
			OrderSort:   0, // Insert 方法会在事务内原子计算
			Label:       labels,
			MemberID:    memberID,
			IsPublic:    isPublic,
			NavVisible:  false,
		}
		if err := bookmark.Insert(); err != nil {
			apiError(c, http.StatusBadRequest, "创建书签失败")
			return
		}
	}

	// 重新绑定标签（以 md_label_relation 为准）
	models.RebindLabels(bookmark.BookmarkID, "bookmark", labels)

	// 同步 label 字段
	if err := models.SyncResourceLabelField(bookmark.BookmarkID, "bookmark"); err != nil {
		log.Printf("CreateBookmarkCompat: SyncResourceLabelField failed for bookmark %d: %v", bookmark.BookmarkID, err)
	}

	// 从 md_label_relation 读取实际存储的标签
	savedLabels, _ := models.GetLabelsByResource(bookmark.BookmarkID, "bookmark")
	if savedLabels == nil {
		savedLabels = []string{}
	}

	// Linkding 插件要求 POST 始终返回 201，否则视为失败
	c.JSON(http.StatusCreated, gin.H{
		"id":          bookmark.BookmarkID,
		"url":         bookmark.URL,
		"title":       bookmark.Title,
		"description": bookmark.Description,
		"tag_names":   savedLabels,
		"is_archived": false,
		"unread":      !bookmark.IsPublic,
		"shared":      bookmark.IsPublic,
		"date_added":  bookmark.CreateTime.Format(time.RFC3339),
	})
}

// CheckBookmarkCompat linkding 兼容：检查 URL 是否已收藏
// GET /api/bookmarks/check/?url=xxx
func CheckBookmarkCompat(c *gin.Context) {
	url := c.Query("url")
	if url == "" {
		apiError(c, http.StatusBadRequest, "请输入URL")
		return
	}

	memberID := middleware.GetMemberID(c)

	// Check if bookmark exists
	bookmark, _ := models.GetBookmarkByURLAndMember(url, memberID)

	// Fetch page metadata
	metadata := gin.H{"url": url, "title": nil, "description": nil}
	if r := isSafeURL(url); r.Safe {
		httpReq, err := http.NewRequest("GET", url, nil)
		if err != nil {
			apiError(c, http.StatusBadRequest, "URL格式错误")
			return
		}
		httpReq.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
		httpReq.Header.Set("Accept", "text/html,application/xhtml+xml")
		if resp, err := metaClient.Do(httpReq); err == nil {
			defer resp.Body.Close()
			if resp.StatusCode == 200 {
				body := io.LimitReader(resp.Body, 32*1024)
				data, _ := io.ReadAll(body)
				html := string(data)
				if t := extractMeta(html, "title"); t != "" {
					metadata["title"] = t
				}
				if d := extractMeta(html, "description"); d != "" {
					metadata["description"] = d
				}
			}
		}
	}

	var bookmarkData interface{} = nil
	if bookmark != nil {
		bookmarkData = gin.H{
			"id":          bookmark.BookmarkID,
			"url":         bookmark.URL,
			"title":       bookmark.Title,
			"description": bookmark.Description,
			"tag_names":   bookmark.Labels,
			"is_archived": false,
			"unread":      !bookmark.IsPublic,
			"shared":      bookmark.IsPublic,
			"date_added":  bookmark.CreateTime.Format(time.RFC3339),
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"bookmark":  bookmarkData,
		"metadata":  metadata,
		"auto_tags": []string{},
	})
}

// ListTagsCompat linkding 兼容：获取标签列表
// GET /api/tags/
func ListTagsCompat(c *gin.Context) {
	memberID := middleware.GetMemberID(c)

	names, err := models.ListBookmarkTagNames(memberID)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"count": 0, "results": []interface{}{}})
		return
	}

	type tagItem struct {
		ID   int64  `json:"id"`
		Name string `json:"name"`
	}
	var results []tagItem
	for i, name := range names {
		results = append(results, tagItem{ID: int64(i + 1), Name: name})
	}
	if results == nil {
		results = []tagItem{}
	}

	c.JSON(http.StatusOK, gin.H{
		"count":    len(results),
		"next":     nil,
		"previous": nil,
		"results":  results,
	})
}

// ListBookmarksCompat linkding 兼容：书签列表（插件 testConnection 和搜索用）
// GET /api/bookmarks/?limit=1&q=xxx
func ListBookmarksCompat(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "100"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))
	q := c.Query("q")

	if limit <= 0 || limit > 5000 {
		limit = 100
	}

	query := models.BookmarkQuery{
		Keyword:  q,
		MemberID: memberID,
		Page:     offset/limit + 1,
		PageSize: limit,
	}

	result, err := models.QueryBookmarks(query)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"count": 0, "results": []interface{}{}})
		return
	}

	// Convert to linkding format
	type bookmarkItem struct {
		ID          int64    `json:"id"`
		URL         string   `json:"url"`
		Title       string   `json:"title"`
		Description string   `json:"description"`
		TagNames    []string `json:"tag_names"`
		IsArchived  bool     `json:"is_archived"`
		Unread      bool     `json:"unread"`
		Shared      bool     `json:"shared"`
		DateAdded   string   `json:"date_added"`
	}

	var results []bookmarkItem
	for _, b := range result.Data {
		if b.Labels == nil {
			b.Labels = []string{}
		}
		results = append(results, bookmarkItem{
			ID:          b.BookmarkID,
			URL:         b.URL,
			Title:       b.Title,
			Description: b.Description,
			TagNames:    b.Labels,
			Unread:      !b.IsPublic,
			Shared:      b.IsPublic,
			DateAdded:   b.CreateTime.Format(time.RFC3339),
		})
	}
	if results == nil {
		results = []bookmarkItem{}
	}

	c.JSON(http.StatusOK, gin.H{
		"count":    result.Total,
		"next":     nil,
		"previous": nil,
		"results":  results,
	})
}

// DeleteBookmarkCompat 删除书签（linkding 兼容，返回 204）
func DeleteBookmarkCompat(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}
	if !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	if err := models.DeleteBookmark(id); err != nil {
		if strings.Contains(err.Error(), "不存在") {
			apiError(c, http.StatusNotFound, err.Error())
		} else {
			apiError(c, http.StatusInternalServerError, "删除失败")
		}
		return
	}
	c.Status(http.StatusNoContent)
}

// UpdateBookmarkCompat linkding 兼容的书签更新接口
// PATCH /api/bookmarks/:id/
func UpdateBookmarkCompat(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}
	if !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	var req struct {
		URL         string   `json:"url"`
		Title       string   `json:"title"`
		Description string   `json:"description"`
		TagNames    []string `json:"tag_names"`
		Unread      *bool    `json:"unread"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求数据格式错误")
		return
	}

	// 更新字段：仅更新请求中提供的字段
	if req.URL != "" {
		if len(req.URL) > 2048 || !isValidURL(req.URL) {
			apiError(c, http.StatusBadRequest, "URL格式不正确")
			return
		}
		bookmark.URL = req.URL
	}
	if req.Title != "" {
		if len(req.Title) > 500 {
			apiError(c, http.StatusBadRequest, "标题不能超过500个字符")
			return
		}
		bookmark.Title = req.Title
	}
	if req.Description != "" {
		if len(req.Description) > 2000 {
			apiError(c, http.StatusBadRequest, "描述不能超过2000个字符")
			return
		}
		bookmark.Description = req.Description
	}
	if req.Unread != nil {
		bookmark.IsPublic = !*req.Unread
	}

	// 处理标签
	labels := ""
	if req.TagNames != nil {
		labels = strings.Join(req.TagNames, ",")
		bookmark.Label = labels
	}

	if err := bookmark.Update(); err != nil {
		apiError(c, http.StatusInternalServerError, "更新书签失败")
		return
	}

	// 重新绑定标签
	if req.TagNames != nil {
		models.RebindLabels(bookmark.BookmarkID, "bookmark", labels)
		if err := models.SyncResourceLabelField(bookmark.BookmarkID, "bookmark"); err != nil {
			log.Printf("UpdateBookmarkCompat: SyncResourceLabelField failed for bookmark %d: %v", bookmark.BookmarkID, err)
		}
	}

	// 从 md_label_relation 读取实际存储的标签
	savedLabels, _ := models.GetLabelsByResource(bookmark.BookmarkID, "bookmark")
	if savedLabels == nil {
		savedLabels = []string{}
	}

	c.JSON(http.StatusOK, gin.H{
		"id":          bookmark.BookmarkID,
		"url":         bookmark.URL,
		"title":       bookmark.Title,
		"description": bookmark.Description,
		"tag_names":   savedLabels,
		"is_archived": false,
		"unread":      !bookmark.IsPublic,
		"shared":      bookmark.IsPublic,
		"date_added":  bookmark.CreateTime.Format(time.RFC3339),
	})
}

// GetBookmarkCompat 获取单个书签（linkding 兼容）
func GetBookmarkCompat(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	bookmark, err := models.GetBookmarkByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "书签不存在")
		return
	}

	// 所有权校验：非公开书签只有所有者或管理员可访问
	if !bookmark.IsPublic && !checkOwnership(c, bookmark.MemberID) {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}

	labels, _ := models.GetLabelsByResource(bookmark.BookmarkID, "bookmark")
	if labels == nil {
		labels = []string{}
	}

	c.JSON(http.StatusOK, gin.H{
		"id":          bookmark.BookmarkID,
		"url":         bookmark.URL,
		"title":       bookmark.Title,
		"description": bookmark.Description,
		"tag_names":   labels,
		"is_archived": false,
		"unread":      !bookmark.IsPublic,
		"shared":      bookmark.IsPublic,
		"date_added":  bookmark.CreateTime.Format(time.RFC3339),
	})
}
