package controllers

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
	"bookstark/services"
)

var reminderTimePattern = regexp.MustCompile(`^(?:[01]\d|2[0-3]):[0-5]\d$`)
var mailTestLimiter = &rateLimiter{attempts: make(map[string]*attemptInfo), maxIPs: 5000}

func GetTaskReminderPreference(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	pref, err := models.GetTaskReminderPreference(memberID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取邮件提醒设置失败")
		return
	}
	cfg := models.GetMailSettings()
	apiSuccess(c, gin.H{
		"enabled":             pref.Enabled,
		"send_time":           pref.SendTime,
		"remind_before_days":  pref.RemindBeforeDays,
		"include_overdue":     pref.IncludeOverdue,
		"email":               pref.Email,
		"available":           cfg.Ready() && cfg.TaskReminderEnabled,
		"last_processed_date": pref.LastProcessedDate,
	})
}

func UpdateTaskReminderPreference(c *gin.Context) {
	var req struct {
		Enabled          bool   `json:"enabled"`
		SendTime         string `json:"send_time"`
		RemindBeforeDays int    `json:"remind_before_days"`
		IncludeOverdue   bool   `json:"include_overdue"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "邮件提醒设置无效")
		return
	}
	req.SendTime = strings.TrimSpace(req.SendTime)
	if !reminderTimePattern.MatchString(req.SendTime) {
		apiError(c, http.StatusBadRequest, "提醒时间格式应为 HH:MM")
		return
	}
	if req.RemindBeforeDays < 0 || req.RemindBeforeDays > 30 {
		apiError(c, http.StatusBadRequest, "提前提醒天数应在0-30之间")
		return
	}
	memberID := middleware.GetMemberID(c)
	member, err := models.GetMemberByID(memberID)
	if err != nil {
		apiError(c, http.StatusNotFound, "用户不存在")
		return
	}
	if req.Enabled {
		cfg := models.GetMailSettings()
		if !cfg.Ready() || !cfg.TaskReminderEnabled {
			apiError(c, http.StatusConflict, "管理员尚未启用待办邮件提醒")
			return
		}
		if strings.TrimSpace(member.Email) == "" {
			apiError(c, http.StatusBadRequest, "请先在个人资料中设置邮箱")
			return
		}
	}
	err = models.UpsertTaskReminderPreference(models.TaskReminderPreference{
		MemberID: memberID, Enabled: req.Enabled, SendTime: req.SendTime,
		RemindBeforeDays: req.RemindBeforeDays, IncludeOverdue: req.IncludeOverdue,
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "保存邮件提醒设置失败")
		return
	}
	apiSuccessMsg(c, "邮件提醒设置已保存")
}

func TestProfileMail(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	if !mailTestLimiter.check(fmt.Sprintf("profile:%d", memberID), 3, 10*time.Minute) {
		apiError(c, http.StatusTooManyRequests, "测试邮件发送过于频繁，请稍后再试")
		return
	}
	member, err := models.GetMemberByID(memberID)
	if err != nil || strings.TrimSpace(member.Email) == "" {
		apiError(c, http.StatusBadRequest, "请先设置有效邮箱")
		return
	}
	sendTestMail(c, member.Email)
}

func TestAdminMail(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	if !mailTestLimiter.check(fmt.Sprintf("admin:%d", memberID), 5, 10*time.Minute) {
		apiError(c, http.StatusTooManyRequests, "测试邮件发送过于频繁，请稍后再试")
		return
	}
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入有效的测试收件邮箱")
		return
	}
	sendTestMail(c, strings.TrimSpace(req.Email))
}

func sendTestMail(c *gin.Context, email string) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()
	err := services.SendConfiguredMail(ctx, services.MailMessage{
		To:       email,
		Subject:  "[BookStark] 邮件服务测试成功",
		TextBody: "这是一封来自 BookStark 的测试邮件。收到此邮件表示 SMTP 配置可用。",
		HTMLBody: `<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#172033"><h2>BookStark 邮件服务测试成功</h2><p>收到此邮件表示 SMTP 配置可用。</p></div>`,
	})
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	apiSuccessMsg(c, "测试邮件已发送")
}

func GetAdminMailStatus(c *gin.Context) {
	summary, err := models.GetMailStatusSummary()
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取邮件发送状态失败")
		return
	}
	cfg := models.GetMailSettings()
	apiSuccess(c, gin.H{
		"configured":             cfg.Ready(),
		"enabled":                cfg.Enabled,
		"task_reminder_enabled":  cfg.TaskReminderEnabled,
		"password_reset_enabled": cfg.PasswordResetEnabled,
		"password_reset_ready":   cfg.PasswordResetReady(),
		"summary":                summary,
	})
}
