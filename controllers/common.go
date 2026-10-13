package controllers

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/i18n"
	"bookstark/middleware"
	"bookstark/models"
)

// commonData returns template data common to all pages
func commonData(c *gin.Context, nav string) gin.H {
	account := middleware.GetAccount(c)
	memberID := middleware.GetMemberID(c)
	role, _ := c.Get("role")
	isAdmin := false
	if r, ok := role.(int); ok && r == middleware.RoleAdmin {
		isAdmin = true
	}
	friendLinks, err := models.ListEnabledFriendLinks()
	if err != nil {
		friendLinks = []models.FriendLink{}
	}
	csrfToken := middleware.GetCSRFToken(c)

	lang := middleware.GetLang(c)
	t := i18n.MakeT(lang)
	bundleJSON, _ := json.Marshal(i18n.JSBundle(lang))
	var background *models.BackgroundPreference
	if memberID > 0 {
		p, e := models.GetBackgroundPreference(memberID)
		if e == nil {
			background = &p
		}
	}

	return gin.H{
		"Account":     account,
		"Background":  background,
		"MemberID":    memberID,
		"IsAdmin":     isAdmin,
		"Nav":         nav,
		"FriendLinks": friendLinks,
		"CSRFToken":   csrfToken,
		"Lang":        lang,
		"T":           t,
		"JSBundle":    template.JS(bundleJSON),
		"AIEnabled":   models.GetSettingWithDefault("ai_enabled", "0") == "1",
	}
}

// getPageSize returns page size from query param, falling back to system setting, then default
func getPageSize(c *gin.Context, settingKey, defaultVal string) int {
	ps := c.DefaultQuery("page_size", "")
	if ps != "" {
		n, err := strconv.Atoi(ps)
		if err == nil && n > 0 && n <= 200 {
			return n
		}
	}
	// Fall back to system setting
	val := models.GetSetting(settingKey)
	if val != "" {
		n, err := strconv.Atoi(val)
		if err == nil && n > 0 && n <= 200 {
			return n
		}
	}
	// Final fallback
	n, _ := strconv.Atoi(defaultVal)
	return n
}

// isAdmin checks if the current user is an admin
func isAdmin(c *gin.Context) bool {
	role, _ := c.Get("role")
	r, ok := role.(int)
	return ok && r == middleware.RoleAdmin
}

// checkOwnership checks if the current user owns the resource (or is admin).
// Returns true if the user is the owner or admin, false otherwise.
func checkOwnership(c *gin.Context, ownerMemberID int64) bool {
	if isAdmin(c) {
		return true
	}
	return middleware.GetMemberID(c) == ownerMemberID
}

// forbidden responds with 403 for API or redirects for pages
func forbidden(c *gin.Context) {
	if strings.HasPrefix(c.Request.URL.Path, "/api/") {
		apiError(c, http.StatusForbidden, "无权操作")
		return
	}
	c.Redirect(302, "/")
}

// urlCheckResult 记录 URL 安全检查结果
type urlCheckResult struct {
	Safe   bool
	Reason string // 不安全的详细原因
}

// safeReason 预定义不安全原因常量
const (
	safeReasonOK       = ""
	safeReasonInvalid  = "URL格式错误"
	safeReasonScheme   = "仅支持http和https协议"
	safeReasonNoHost   = "URL缺少域名"
	safeReasonResolve  = "域名解析失败，请检查网址是否正确"
	safeReasonInternal = "不允许访问内网地址"
)

// isSafeURL checks if a URL is safe to fetch server-side (SSRF protection).
// Blocks private IPs, link-local, loopback, and cloud metadata endpoints.
// Returns the check result with reason.
func isSafeURL(rawURL string) urlCheckResult {
	u, err := url.Parse(rawURL)
	if err != nil {
		return urlCheckResult{false, safeReasonInvalid}
	}
	// Only allow http and https
	if u.Scheme != "http" && u.Scheme != "https" {
		return urlCheckResult{false, safeReasonScheme}
	}
	// Must have a host
	if u.Host == "" {
		return urlCheckResult{false, safeReasonNoHost}
	}
	// Resolve hostname to IP with timeout (3s) to avoid blocking goroutines
	host := u.Hostname()
	resolver := &net.Resolver{}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	ips, err := resolver.LookupIPAddr(ctx, host)
	if err != nil {
		return urlCheckResult{false, safeReasonResolve}
	}
	for _, ipAddr := range ips {
		if !isPublicIP(ipAddr.IP) {
			return urlCheckResult{false, safeReasonInternal}
		}
	}
	return urlCheckResult{true, ""}
}

// isPublicIP returns true if the IP is a public (non-private) address
func isPublicIP(ip net.IP) bool {
	privateRanges := []struct {
		network *net.IPNet
	}{
		{mustParseCIDR("10.0.0.0/8")},
		{mustParseCIDR("172.16.0.0/12")},
		{mustParseCIDR("192.168.0.0/16")},
		{mustParseCIDR("127.0.0.0/8")},
		{mustParseCIDR("169.254.0.0/16")},
		{mustParseCIDR("::1/128")},
		{mustParseCIDR("fc00::/7")},
		{mustParseCIDR("fe80::/10")},
	}
	for _, r := range privateRanges {
		if r.network.Contains(ip) {
			return false
		}
	}
	return true
}

func mustParseCIDR(s string) *net.IPNet {
	_, network, err := net.ParseCIDR(s)
	if err != nil {
		panic(err)
	}
	return network
}

// calcTotalPages 计算总页数
func calcTotalPages(total int64, pageSize int) int {
	pages := int(total) / pageSize
	if int(total)%pageSize > 0 {
		pages++
	}
	if pages == 0 {
		pages = 1
	}
	return pages
}

// APIResponse 统一 API 响应结构
type APIResponse struct {
	Code    int         `json:"code"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
}

// APIListResponse 统一列表 API 响应结构
type APIListResponse struct {
	Code       int         `json:"code"`
	Message    string      `json:"message,omitempty"`
	Data       interface{} `json:"data"`
	Total      int64       `json:"total"`
	Page       int         `json:"page"`
	PageSize   int         `json:"page_size"`
	TotalPages int         `json:"total_pages"`
}

// apiSuccess 返回成功响应（含数据）
func apiSuccess(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, APIResponse{Code: 0, Data: data})
}

// apiSuccessMsg 返回成功响应（仅消息）
func apiSuccessMsg(c *gin.Context, msg string) {
	c.JSON(http.StatusOK, APIResponse{Code: 0, Message: msg})
}

// apiListSuccess 返回分页列表成功响应
func apiListSuccess(c *gin.Context, data interface{}, total int64, page int, pageSize int) {
	totalPages := calcTotalPages(total, pageSize)
	c.JSON(http.StatusOK, APIListResponse{
		Code:       0,
		Data:       data,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	})
}

// apiError 返回错误响应
func apiError(c *gin.Context, status int, msg string) {
	c.JSON(status, APIResponse{Code: status, Message: msg})
}

// generateIdentify 生成唯一标识符
func generateIdentify(prefix string) string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		log.Printf("generateIdentify: rand.Read failed: %v", err)
		// Fallback to timestamp-based identifier if crypto/rand fails
		return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
	}
	return fmt.Sprintf("%s-%x", prefix, b)
}
