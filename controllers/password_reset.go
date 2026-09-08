package controllers

import (
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"html/template"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/i18n"
	"bookstark/middleware"
	"bookstark/models"
)

const passwordResetGenericMessage = "如果账号存在，重置密码邮件将发送到注册邮箱"

var passwordResetIPLimiter = &rateLimiter{attempts: make(map[string]*attemptInfo), maxIPs: 5000}
var passwordResetIdentityLimiter = &rateLimiter{attempts: make(map[string]*attemptInfo), maxIPs: 5000}
var passwordResetCompleteLimiter = &rateLimiter{attempts: make(map[string]*attemptInfo), maxIPs: 5000}

func ForgotPasswordPage(c *gin.Context) {
	renderPasswordPage(c, "forgot_password.html")
}

func ResetPasswordPage(c *gin.Context) {
	renderPasswordPage(c, "reset_password.html")
}

func renderPasswordPage(c *gin.Context, name string) {
	lang := middleware.GetLang(c)
	bundleJSON, _ := json.Marshal(i18n.JSBundle(lang))
	c.Header("Referrer-Policy", "no-referrer")
	c.HTML(http.StatusOK, name, gin.H{
		"Lang":      lang,
		"T":         i18n.MakeT(lang),
		"JSBundle":  template.JS(bundleJSON),
		"Available": models.GetMailSettings().PasswordResetReady(),
	})
}

func RequestPasswordReset(c *gin.Context) {
	started := time.Now()
	defer func() {
		if remaining := 250*time.Millisecond - time.Since(started); remaining > 0 {
			time.Sleep(remaining)
		}
	}()

	cfg := models.GetMailSettings()
	if !cfg.PasswordResetReady() {
		apiError(c, http.StatusServiceUnavailable, "找回密码服务暂不可用，请联系管理员")
		return
	}
	var req struct {
		Identity string `json:"identity" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入账号或注册邮箱")
		return
	}
	identity := strings.TrimSpace(req.Identity)
	if identity == "" || len(identity) > 200 {
		apiError(c, http.StatusBadRequest, "请输入有效的账号或注册邮箱")
		return
	}
	if !passwordResetIPLimiter.check("ip:"+c.ClientIP(), 5, 15*time.Minute) ||
		!passwordResetIdentityLimiter.check("identity:"+strings.ToLower(identity), 3, 15*time.Minute) {
		apiError(c, http.StatusTooManyRequests, "请求过于频繁，请稍后再试")
		return
	}

	member, err := models.GetActiveMemberByAccountOrEmail(identity)
	if err != nil {
		apiSuccessMsg(c, passwordResetGenericMessage)
		return
	}
	rawToken, expiresAt, err := models.CreatePasswordResetToken(member.MemberID, c.ClientIP(), cfg.PasswordResetExpiry)
	if err != nil {
		log.Printf("create password reset token for member %d: %v", member.MemberID, err)
		apiSuccessMsg(c, passwordResetGenericMessage)
		return
	}
	resetURL := cfg.PublicURL + "/reset-password#token=" + rawToken
	minutes := int(cfg.PasswordResetExpiry / time.Minute)
	textBody := fmt.Sprintf("BookStark 密码重置\n\n有人申请重置账号 %s 的密码。\n请在 %d 分钟内打开以下链接：\n%s\n\n如果不是你本人操作，请忽略此邮件。", member.Account, minutes, resetURL)
	htmlBody := fmt.Sprintf(`<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:560px;margin:auto;color:#172033"><h2 style="margin:0 0 16px">重置 BookStark 密码</h2><p>有人申请重置账号 <strong>%s</strong> 的密码。</p><p>该链接将在 %d 分钟后失效，且只能使用一次。</p><p style="margin:24px 0"><a href="%s" style="display:inline-block;background:#2563eb;color:#fff;text-decoration:none;padding:10px 16px;border-radius:6px;font-size:14px">重置密码</a></p><p style="font-size:12px;color:#6b7280">如果不是你本人操作，请忽略此邮件。链接有效期至 %s。</p></div>`, html.EscapeString(member.Account), minutes, html.EscapeString(resetURL), expiresAt.Format("2006-01-02 15:04"))
	created, queueErr := models.CreateMailOutbox(&models.MailOutbox{
		Kind:      "password_reset",
		MemberID:  member.MemberID,
		ToEmail:   member.Email,
		Subject:   "[BookStark] 重置密码",
		TextBody:  textBody,
		HTMLBody:  htmlBody,
		DedupeKey: fmt.Sprintf("password_reset:%d:%d", member.MemberID, time.Now().UnixNano()),
	})
	if queueErr != nil || !created {
		log.Printf("queue password reset mail for member %d: created=%v err=%v", member.MemberID, created, queueErr)
	}
	apiSuccessMsg(c, passwordResetGenericMessage)
}

func CompletePasswordReset(c *gin.Context) {
	cfg := models.GetMailSettings()
	if !cfg.PasswordResetReady() {
		apiError(c, http.StatusServiceUnavailable, "找回密码服务暂不可用，请联系管理员")
		return
	}
	var req struct {
		Token           string `json:"token" binding:"required"`
		NewPassword     string `json:"new_password" binding:"required"`
		ConfirmPassword string `json:"confirm_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请填写完整信息")
		return
	}
	req.Token = strings.TrimSpace(req.Token)
	if len(req.Token) < 40 || len(req.Token) > 100 {
		apiError(c, http.StatusBadRequest, "重置链接无效或已过期")
		return
	}
	if req.NewPassword != req.ConfirmPassword {
		apiError(c, http.StatusBadRequest, "两次密码不一致")
		return
	}
	if len(req.NewPassword) < 6 {
		apiError(c, http.StatusBadRequest, "密码长度不能少于6位")
		return
	}
	if len(req.NewPassword) > 72 {
		apiError(c, http.StatusBadRequest, "密码长度不能超过72位")
		return
	}
	if !passwordResetCompleteLimiter.check("ip:"+c.ClientIP(), 10, 15*time.Minute) {
		apiError(c, http.StatusTooManyRequests, "重置尝试过于频繁，请稍后再试")
		return
	}
	if err := models.ResetPasswordWithToken(req.Token, req.NewPassword); err != nil {
		if errors.Is(err, models.ErrPasswordResetTokenInvalid) {
			apiError(c, http.StatusBadRequest, "重置链接无效或已过期")
			return
		}
		log.Printf("complete password reset: %v", err)
		apiError(c, http.StatusInternalServerError, "重置密码失败，请稍后再试")
		return
	}
	c.SetCookie("token", "", -1, "/", "", false, true)
	apiSuccessMsg(c, "密码已重置，请使用新密码登录")
}
