package controllers

import (
	"encoding/json"
	"html/template"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/i18n"
	"bookstark/middleware"
	"bookstark/models"
)

// loginLimiter 简单的登录频率限制器
var loginLimiter = &rateLimiter{
	attempts: make(map[string]*attemptInfo),
	maxIPs:   5000,
}

type attemptInfo struct {
	count    int
	expireAt time.Time
}

type rateLimiter struct {
	mu       sync.Mutex
	attempts map[string]*attemptInfo
	maxIPs   int // 最大 IP 记录数，防止内存泄漏
}

// check 返回 true 表示允许，false 表示被限频
func (r *rateLimiter) check(key string, maxAttempts int, window time.Duration) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()

	// 每次都清理过期的条目，防止内存泄漏
	for k, v := range r.attempts {
		if now.After(v.expireAt) {
			delete(r.attempts, k)
		}
	}

	// 如果 map 超过最大限制，清理最旧的条目
	if len(r.attempts) > r.maxIPs {
		var oldestKey string
		var oldestTime time.Time
		first := true
		for k, v := range r.attempts {
			if first || v.expireAt.Before(oldestTime) {
				oldestKey = k
				oldestTime = v.expireAt
				first = false
			}
		}
		if oldestKey != "" {
			delete(r.attempts, oldestKey)
		}
	}

	info, exists := r.attempts[key]
	if !exists {
		r.attempts[key] = &attemptInfo{
			count:    1,
			expireAt: now.Add(window),
		}
		return true
	}

	if now.After(info.expireAt) {
		info.count = 1
		info.expireAt = now.Add(window)
		return true
	}

	info.count++
	return info.count <= maxAttempts
}

// reset 清除指定 key 的限频记录（登录成功时调用）
func (r *rateLimiter) reset(key string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.attempts, key)
}

func LoginPage(c *gin.Context) {
	loginReturn := "/"
	if next, err := url.Parse(c.Query("next")); err == nil && next.Scheme == "" && next.Host == "" && !strings.ContainsAny(next.Path, "\\\r\n") && (next.Path == "/shares" || strings.HasPrefix(next.Path, "/shares/")) {
		loginReturn = next.String()
	}
	lang := middleware.GetLang(c)
	t := i18n.MakeT(lang)
	bundleJSON, _ := json.Marshal(i18n.JSBundle(lang))
	c.HTML(http.StatusOK, "login.html", gin.H{
		"Lang":                   lang,
		"T":                      t,
		"JSBundle":               template.JS(bundleJSON),
		"PasswordResetAvailable": models.GetMailSettings().PasswordResetReady(),
		"LoginReturn":            loginReturn,
	})
}

func RegisterConfig(c *gin.Context) {
	inviteEnabled := models.GetSettingWithDefault("invite_code_enabled", "0")
	apiSuccess(c, gin.H{"invite_code_enabled": inviteEnabled == "1"})
}

func RegisterPage(c *gin.Context) {
	lang := middleware.GetLang(c)
	t := i18n.MakeT(lang)
	bundleJSON, _ := json.Marshal(i18n.JSBundle(lang))
	c.HTML(http.StatusOK, "register.html", gin.H{
		"Lang":     lang,
		"T":        t,
		"JSBundle": template.JS(bundleJSON),
	})
}

func Login(c *gin.Context) {
	var req struct {
		Account  string `json:"account" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入账号和密码")
		return
	}

	if len(req.Password) > 72 {
		apiError(c, http.StatusBadRequest, "密码长度不能超过72个字符")
		return
	}

	// Rate limit check
	clientIP := c.ClientIP()
	rateKey := clientIP
	if !loginLimiter.check(rateKey, 10, 5*time.Minute) {
		apiError(c, http.StatusTooManyRequests, "登录尝试过于频繁，请5分钟后再试")
		return
	}

	member, err := models.GetMemberByAccount(req.Account)
	if err != nil {
		apiError(c, http.StatusUnauthorized, "账号或密码错误")
		return
	}

	if member.Status != 1 {
		apiError(c, http.StatusForbidden, "账号未通过审批")
		return
	}

	if !member.VerifyPassword(req.Password) {
		apiError(c, http.StatusUnauthorized, "账号或密码错误")
		return
	}

	token, err := middleware.GenerateToken(member.MemberID, member.Account, member.Role)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "生成令牌失败")
		return
	}

	middleware.SetTokenCookie(c, token)
	models.UpdateMemberLoginTime(member.MemberID)

	// Login success - reset rate limit for this IP
	loginLimiter.reset(clientIP)

	apiSuccess(c, gin.H{
		"member": gin.H{
			"member_id": member.MemberID,
			"account":   member.Account,
			"role":      member.Role,
		},
	})
}

func Register(c *gin.Context) {
	var req struct {
		Account         string `json:"account" binding:"required"`
		Email           string `json:"email" binding:"required,email"`
		Password        string `json:"password" binding:"required,min=6"`
		ConfirmPassword string `json:"confirm_password" binding:"required"`
		InviteCode      string `json:"invite_code"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请填写完整信息")
		return
	}

	// 输入长度校验
	if len(req.Account) > 50 {
		apiError(c, http.StatusBadRequest, "账号长度不能超过50个字符")
		return
	}
	if len(req.Email) > 200 {
		apiError(c, http.StatusBadRequest, "邮箱长度不能超过200个字符")
		return
	}
	if len(req.Password) > 72 {
		apiError(c, http.StatusBadRequest, "密码长度不能超过72个字符")
		return
	}
	if strings.Contains(req.Account, " ") {
		apiError(c, http.StatusBadRequest, "账号不能包含空格")
		return
	}

	if req.Password != req.ConfirmPassword {
		apiError(c, http.StatusBadRequest, "两次密码不一致")
		return
	}

	// Check invite code if enabled
	inviteEnabled := models.GetSettingWithDefault("invite_code_enabled", "0")
	if inviteEnabled == "1" {
		inviteCode := models.GetSettingWithDefault("invite_code", "")
		if req.InviteCode == "" {
			apiError(c, http.StatusBadRequest, "请输入邀请码")
			return
		}
		if inviteCode == "" || req.InviteCode != inviteCode {
			apiError(c, http.StatusBadRequest, "邀请码错误")
			return
		}
	}

	// If invite code enabled and matched, auto-approve; otherwise need approval
	status := 0
	if inviteEnabled == "1" {
		status = 1
	}

	member := &models.Member{
		Account:    req.Account,
		Password:   req.Password,
		Email:      req.Email,
		Role:       1,
		Status:     status,
		CreateTime: time.Now(),
	}

	if err := member.Insert(); err != nil {
		apiError(c, http.StatusBadRequest, "注册失败，账号或邮箱可能已存在")
		return
	}

	if status == 1 {
		apiSuccessMsg(c, "注册成功，请登录")
	} else {
		apiSuccessMsg(c, "注册成功，请等待管理员审批")
	}
}

func Logout(c *gin.Context) {
	c.SetCookie("token", "", -1, "/", "", false, true)
	apiSuccessMsg(c, "已登出")
}

func GetProfile(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	member, err := models.GetMemberByID(memberID)
	if err != nil {
		apiError(c, http.StatusNotFound, "用户不存在")
		return
	}
	apiSuccess(c, gin.H{
		"member_id":    member.MemberID,
		"account":      member.Account,
		"email":        member.Email,
		"role":         member.Role,
		"default_home": member.DefaultHome,
	})
}

func UpdateProfile(c *gin.Context) {
	var req struct {
		Email       string `json:"email" binding:"required,email"`
		Bio         string `json:"bio"`
		DefaultHome string `json:"default_home"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入有效邮箱")
		return
	}

	if len(req.Email) > 200 {
		apiError(c, http.StatusBadRequest, "邮箱长度不能超过200个字符")
		return
	}
	if len(req.Bio) > 500 {
		apiError(c, http.StatusBadRequest, "个人简介不能超过500个字符")
		return
	}
	if req.DefaultHome != "" && !models.IsValidDefaultHome(req.DefaultHome) {
		apiError(c, http.StatusBadRequest, "默认打开模块无效")
		return
	}
	req.DefaultHome = models.NormalizeDefaultHome(req.DefaultHome)

	memberID := middleware.GetMemberID(c)
	if err := models.UpdateMemberProfile(memberID, req.Email, req.DefaultHome); err != nil {
		apiError(c, http.StatusInternalServerError, "更新失败")
		return
	}
	apiSuccessMsg(c, "更新成功")
}

func ChangePassword(c *gin.Context) {
	var req struct {
		OldPassword string `json:"old_password" binding:"required"`
		NewPassword string `json:"new_password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请填写完整信息")
		return
	}

	if len(req.NewPassword) > 72 {
		apiError(c, http.StatusBadRequest, "密码长度不能超过72个字符")
		return
	}

	memberID := middleware.GetMemberID(c)
	member, err := models.GetMemberByID(memberID)
	if err != nil {
		apiError(c, http.StatusNotFound, "用户不存在")
		return
	}

	if !member.VerifyPassword(req.OldPassword) {
		apiError(c, http.StatusBadRequest, "当前密码错误")
		return
	}

	if err := models.UpdateMemberPassword(memberID, req.NewPassword); err != nil {
		apiError(c, http.StatusInternalServerError, "修改密码失败")
		return
	}
	newToken, err := middleware.GenerateToken(member.MemberID, member.Account, member.Role)
	if err != nil {
		c.SetCookie("token", "", -1, "/", "", false, true)
		apiSuccessMsg(c, "密码修改成功，请重新登录")
		return
	}
	middleware.SetTokenCookie(c, newToken)

	apiSuccessMsg(c, "密码修改成功")
}

func ProfilePage(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	member, err := models.GetMemberByID(memberID)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}
	data := commonData(c, "")
	data["User"] = member
	data["DefaultHome"] = member.DefaultHome
	c.HTML(http.StatusOK, "profile.html", data)
}

func HomePage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	memberID := middleware.GetMemberID(c)
	if memberID <= 0 {
		PublicFeedPage(c)
		return
	}

	member, err := models.GetMemberByID(memberID)
	if err != nil {
		NavPage(c)
		return
	}
	target := models.DefaultHomeRoute(member.DefaultHome)
	if target == "/home" {
		PersonalHomePage(c)
		return
	}
	if target == "/" {
		NavPage(c)
		return
	}
	c.Redirect(http.StatusFound, target)
}
