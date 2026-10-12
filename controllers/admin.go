package controllers

import (
	"log"
	"net/http"
	"net/mail"
	"net/url"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"bookstark/conf"
	"bookstark/middleware"
	"bookstark/models"
)

func AdminSystemPage(c *gin.Context) {
	settings, err := models.GetAllSettingsDetailed()
	if err != nil {
		log.Printf("AdminSystemPage: GetAllSettingsDetailed failed: %v", err)
	}
	data := commonData(c, "admin")
	data["SMTPPasswordConfigured"] = models.GetSetting("smtp_password") != ""
	data["Settings"] = redactAdminSettings(settings)
	sections, tagsErr := models.PublicTagSections()
	if tagsErr != nil {
		log.Printf("PublicTagSections: %v", tagsErr)
	}
	data["PublicTagSections"] = sections
	c.HTML(http.StatusOK, "admin_system.html", data)
}

func redactAdminSettings(settings []models.Setting) []models.Setting {
	result := append([]models.Setting(nil), settings...)
	for i := range result {
		if result[i].Key == "smtp_password" {
			result[i].Value = ""
		}
	}
	return result
}

func ListMembers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", "20"))

	members, total, err := models.ListAllMembers(page, pageSize)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取用户列表失败")
		return
	}
	apiListSuccess(c, members, total, page, pageSize)
}

func ApproveMember(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	if err := models.UpdateMemberStatus(id, 1); err != nil {
		apiError(c, http.StatusInternalServerError, "审批失败")
		return
	}
	apiSuccessMsg(c, "已通过审批")
}

func SetMemberRole(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}
	var req struct {
		Role int `json:"role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Role != 0 && req.Role != 1 {
		apiError(c, http.StatusBadRequest, "角色值无效")
		return
	}
	// 禁止修改自己的角色，防止管理员误降权
	if id == middleware.GetMemberID(c) {
		apiError(c, http.StatusBadRequest, "不能修改自己的角色")
		return
	}
	// 禁止修改系统内置 admin 账号的角色
	member, err := models.GetMemberByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "用户不存在")
		return
	}
	if member.Account == conf.App.AdminAccount {
		apiError(c, http.StatusForbidden, "系统内置管理员账号不允许修改角色")
		return
	}
	if err := models.UpdateMemberRole(id, req.Role); err != nil {
		apiError(c, http.StatusInternalServerError, "设置失败")
		return
	}
	apiSuccessMsg(c, "角色已更新")
}

func RejectMember(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	if err := models.UpdateMemberStatus(id, 2); err != nil {
		apiError(c, http.StatusInternalServerError, "操作失败")
		return
	}
	apiSuccessMsg(c, "已拒绝")
}

func ResetMemberPassword(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	var req struct {
		NewPassword string `json:"new_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请输入新密码")
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

	member, err := models.GetMemberByID(id)
	if err != nil {
		apiError(c, http.StatusNotFound, "用户不存在")
		return
	}
	if member.Status != 1 {
		apiError(c, http.StatusBadRequest, "该用户未通过审批")
		return
	}

	if err := models.UpdateMemberPassword(id, req.NewPassword); err != nil {
		apiError(c, http.StatusInternalServerError, "重置密码失败")
		return
	}
	apiSuccessMsg(c, "密码已重置")
}

func GetSettings(c *gin.Context) {
	settings, err := models.GetAllSettingsDetailed()
	if err != nil {
		apiError(c, http.StatusInternalServerError, "获取设置失败")
		return
	}
	apiSuccess(c, redactAdminSettings(settings))
}

func UpdateSettings(c *gin.Context) {
	var req map[string]string
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}

	// Validate numeric settings
	for k, v := range req {
		if strings.HasPrefix(k, "public_feed_tags_") {
			kind := strings.TrimPrefix(k, "public_feed_tags_")
			if (kind != "article" && kind != "note" && kind != "book" && kind != "bookmark") || models.ValidatePublicTagConfig(v) != nil {
				apiError(c, http.StatusBadRequest, "Invalid share-page tag configuration")
				return
			}
		}
		if strings.HasPrefix(k, "page_size_") {
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 || n > 200 {
				apiError(c, http.StatusBadRequest, "参数值无效: "+k)
				return
			}
		}
		if k == "label_list_limit" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 || n > 10000 {
				apiError(c, http.StatusBadRequest, "标签列表上限应在1-10000之间")
				return
			}
		}
		if k == "nav_max_items" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 || n > 100000 {
				apiError(c, http.StatusBadRequest, "导航页最多展示书签数应在1-100000之间")
				return
			}
		}
		if k == "save_interval" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 5 || n > 300 {
				apiError(c, http.StatusBadRequest, "自动保存间隔应在5-300秒之间")
				return
			}
		}
		if k == "favicon_cache_days" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 || n > 365 {
				apiError(c, http.StatusBadRequest, "Favicon缓存天数应在1-365之间")
				return
			}
		}
		if k == "login_session_days" {
			n, err := strconv.Atoi(v)
			if err != nil || n < models.MinLoginSessionDays || n > models.MaxLoginSessionDays {
				apiError(c, http.StatusBadRequest, "登录状态有效期应在1-365天之间")
				return
			}
		}
		if k == "share_comments_enabled" && v != "0" && v != "1" {
			apiError(c, http.StatusBadRequest, "评论模块开关参数无效")
			return
		}
		if k == "share_comment_max_length" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 100 || n > 5000 {
				apiError(c, http.StatusBadRequest, "评论最大字符数应在100-5000之间")
				return
			}
		}
		if err := validateWebRTCSignalingSetting(k, v); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
		if err := validateMailSetting(k, v); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
		if err := validateWebDAVSetting(k, v); err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
	}
	if req["smtp_password"] == "" {
		delete(req, "smtp_password")
	}
	mailEnabled := models.GetSettingWithDefault("mail_enabled", "0")
	if value, ok := req["mail_enabled"]; ok {
		mailEnabled = value
	}
	taskReminderEnabled := models.GetSettingWithDefault("task_email_reminder_enabled", "0")
	if value, ok := req["task_email_reminder_enabled"]; ok {
		taskReminderEnabled = value
	}
	passwordResetEnabled := models.GetSettingWithDefault("password_reset_enabled", "1")
	if value, ok := req["password_reset_enabled"]; ok {
		passwordResetEnabled = value
	}
	smtpHost := models.GetSetting("smtp_host")
	if value, ok := req["smtp_host"]; ok {
		smtpHost = value
	}
	fromAddress := models.GetSetting("mail_from_address")
	if value, ok := req["mail_from_address"]; ok {
		fromAddress = value
	}
	publicURL := models.GetSetting("mail_public_url")
	if value, ok := req["mail_public_url"]; ok {
		publicURL = value
	}
	if mailEnabled == "1" {
		if strings.TrimSpace(smtpHost) == "" || strings.TrimSpace(fromAddress) == "" {
			apiError(c, http.StatusBadRequest, "启用邮件前请填写 SMTP 主机和发件邮箱")
			return
		}
	}
	if taskReminderEnabled == "1" && mailEnabled != "1" {
		apiError(c, http.StatusBadRequest, "启用待办提醒前请先启用邮件模块")
		return
	}
	if taskReminderEnabled == "1" && strings.TrimSpace(publicURL) == "" {
		apiError(c, http.StatusBadRequest, "启用待办提醒前请填写站点公开地址")
		return
	}
	if passwordResetEnabled == "1" && mailEnabled == "1" && strings.TrimSpace(publicURL) == "" {
		apiError(c, http.StatusBadRequest, "启用邮件找回密码前请填写站点公开地址")
		return
	}
	webDAVSeparateURL := models.GetSettingWithDefault("webdav_public_asset_separate_url_enabled", "0")
	if value, ok := req["webdav_public_asset_separate_url_enabled"]; ok {
		webDAVSeparateURL = value
	}
	webDAVBaseURL := models.GetSetting("webdav_public_asset_base_url")
	if value, ok := req["webdav_public_asset_base_url"]; ok {
		webDAVBaseURL = value
	}
	if webDAVSeparateURL == "1" && strings.TrimSpace(webDAVBaseURL) == "" {
		apiError(c, http.StatusBadRequest, "启用 WebDAV 独立静态资源地址前请填写基础地址")
		return
	}
	if value, ok := req["webdav_public_asset_base_url"]; ok {
		req["webdav_public_asset_base_url"] = strings.TrimRight(strings.TrimSpace(value), "/")
	}

	if err := models.BatchUpdateSettings(req); err != nil {
		apiError(c, http.StatusInternalServerError, "保存失败")
		return
	}
	apiSuccessMsg(c, "设置已保存")
}

func validateWebDAVSetting(key, value string) error {
	value = strings.TrimSpace(value)
	switch key {
	case "webdav_public_asset_separate_url_enabled":
		if value != "0" && value != "1" {
			return errBadAdminSetting("WebDAV 独立静态资源地址开关无效")
		}
	case "webdav_file_max_bytes":
		n, err := strconv.ParseInt(value, 10, 64)
		if err != nil || n < 1<<20 || n > 2<<30 {
			return errBadAdminSetting("WebDAV 单文件上限应在 1 MiB-2 GiB 之间")
		}
	case "webdav_user_quota_bytes":
		n, err := strconv.ParseInt(value, 10, 64)
		if err != nil || n < 10<<20 || n > 1<<40 {
			return errBadAdminSetting("WebDAV 用户容量应在 10 MiB-1 TiB 之间")
		}
	case "webdav_public_file_max_bytes":
		n, err := strconv.ParseInt(value, 10, 64)
		if err != nil || n < 1<<20 || n > 1<<30 {
			return errBadAdminSetting("WebDAV 公开资源上限应在 1 MiB-1 GiB 之间")
		}
	case "webdav_max_concurrent_transfers":
		n, err := strconv.Atoi(value)
		if err != nil || n < 1 || n > 32 {
			return errBadAdminSetting("WebDAV 最大并发传输数应在 1-32 之间")
		}
	case "webdav_public_asset_base_url":
		if value != "" {
			parsed, err := url.ParseRequestURI(value)
			if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" ||
				parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
				return errBadAdminSetting("WebDAV 静态资源基础地址必须是有效的 HTTP(S) 地址")
			}
		}
	}
	return nil
}

func validateMailSetting(key, value string) error {
	value = strings.TrimSpace(value)
	switch key {
	case "mail_enabled", "task_email_reminder_enabled", "password_reset_enabled":
		if value != "0" && value != "1" {
			return errBadAdminSetting("邮件开关参数无效")
		}
	case "smtp_host":
		if len(value) > 255 || strings.Contains(value, "://") {
			return errBadAdminSetting("SMTP 主机应填写域名或 IP，不包含协议")
		}
	case "smtp_port":
		n, err := strconv.Atoi(value)
		if err != nil || n < 1 || n > 65535 {
			return errBadAdminSetting("SMTP 端口应在1-65535之间")
		}
	case "smtp_encryption":
		if value != "starttls" && value != "tls" && value != "none" {
			return errBadAdminSetting("SMTP 加密方式无效")
		}
	case "smtp_username", "smtp_password":
		if len(value) > 500 {
			return errBadAdminSetting("SMTP 账号参数过长")
		}
	case "mail_from_name":
		if value == "" || len(value) > 100 || strings.ContainsAny(value, "\r\n") {
			return errBadAdminSetting("发件人名称无效")
		}
	case "mail_from_address":
		if value != "" {
			address, err := mail.ParseAddress(value)
			if err != nil || address.Address != value {
				return errBadAdminSetting("发件邮箱格式无效")
			}
		}
	case "mail_public_url":
		if value != "" {
			u, err := url.Parse(value)
			if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
				return errBadAdminSetting("公开站点地址必须是 http(s):// 地址")
			}
		}
	case "mail_timeout_seconds":
		n, err := strconv.Atoi(value)
		if err != nil || n < 3 || n > 60 {
			return errBadAdminSetting("邮件连接超时应在3-60秒之间")
		}
	case "password_reset_expiry_minutes":
		n, err := strconv.Atoi(value)
		if err != nil || n < 5 || n > 120 {
			return errBadAdminSetting("重置链接有效期应在5-120分钟之间")
		}
	}
	return nil
}

func validateWebRTCSignalingSetting(key, value string) error {
	switch key {
	case "webrtc_signaling_enabled":
		if value != "0" && value != "1" {
			return errBadAdminSetting("WebRTC 信令开关参数无效")
		}
	case "webrtc_signaling_allow_local_file":
		if value != "0" && value != "1" {
			return errBadAdminSetting("WebRTC 本地调试开关参数无效")
		}
	case "webrtc_signaling_max_peers":
		n, err := strconv.Atoi(value)
		if err != nil || n < 2 || n > 64 {
			return errBadAdminSetting("WebRTC 单房间连接数应在2-64之间")
		}
	case "webrtc_signaling_max_message_kb":
		n, err := strconv.Atoi(value)
		if err != nil || n < 8 || n > 512 {
			return errBadAdminSetting("WebRTC 信令消息大小应在8-512KB之间")
		}
	case "webrtc_signaling_default_url":
		if strings.TrimSpace(value) != "" && !validWebSocketURL(value) {
			return errBadAdminSetting("WebRTC 默认信令地址必须是 ws:// 或 wss://")
		}
	case "webrtc_signaling_allowed_origins":
		for _, origin := range splitAdminSettingList(value) {
			u, err := url.Parse(origin)
			if err != nil || u.Scheme == "" || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
				return errBadAdminSetting("WebRTC Origin 白名单必须是 http(s):// 域名")
			}
		}
	case "webrtc_signaling_stun_urls":
		for _, stunURL := range splitAdminSettingList(value) {
			if !strings.HasPrefix(stunURL, "stun:") {
				return errBadAdminSetting("WebRTC STUN 地址必须以 stun: 开头")
			}
		}
	case "webrtc_signaling_turn_url":
		turnURL := strings.TrimSpace(value)
		if turnURL != "" && !strings.HasPrefix(turnURL, "turn:") && !strings.HasPrefix(turnURL, "turns:") {
			return errBadAdminSetting("WebRTC TURN 地址必须以 turn: 或 turns: 开头")
		}
	case "webrtc_signaling_turn_username", "webrtc_signaling_turn_credential":
		if len(value) > 256 {
			return errBadAdminSetting("WebRTC TURN 账号参数过长")
		}
	}
	return nil
}

func validWebSocketURL(value string) bool {
	u, err := url.Parse(strings.TrimSpace(value))
	if err != nil || u.Host == "" {
		return false
	}
	return u.Scheme == "ws" || u.Scheme == "wss"
}

func splitAdminSettingList(value string) []string {
	fields := strings.FieldsFunc(value, func(r rune) bool {
		return r == '\n' || r == '\r' || r == ','
	})
	result := make([]string, 0, len(fields))
	for _, field := range fields {
		item := strings.TrimSpace(field)
		if item != "" {
			result = append(result, item)
		}
	}
	return result
}

type errBadAdminSetting string

func (e errBadAdminSetting) Error() string {
	return string(e)
}

// ResetAISetting 把指定 AI 设置项恢复为内置默认值。仅允许 AIDefaults() 白名单中的 key。
// 返回更新后的值，前端可直接回填 textarea。
func ResetAISetting(c *gin.Context) {
	var req struct {
		Key string `json:"key"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Key) == "" {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}
	if err := models.ResetAISettingToDefault(req.Key); err != nil {
		if err == models.ErrSettingNotResettable {
			apiError(c, http.StatusBadRequest, "该设置不在可重置列表中")
			return
		}
		apiError(c, http.StatusInternalServerError, "重置失败")
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "已恢复默认",
		"data":    gin.H{"key": req.Key, "value": models.GetSetting(req.Key)},
	})
}
