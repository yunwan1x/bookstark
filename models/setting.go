package models

import (
	"database/sql"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Setting represents a key-value system parameter
type Setting struct {
	Key         string    `json:"key"`
	Value       string    `json:"value"`
	Description string    `json:"description"`
	UpdateTime  time.Time `json:"update_time"`
}

// defaultSettings defines the default system settings
var defaultSettings = map[string]struct {
	Value       string
	Description string
}{
	"page_size_books":                          {"12", "书籍页分页大小"},
	"page_size_blogs":                          {"12", "博客页分页大小"},
	"page_size_shares":                         {"12", "分享页分页大小"},
	"page_size_bookmarks":                      {"20", "书签页分页大小"},
	"page_size_labels":                         {"20", "标签页分页大小"},
	"page_size_notes":                          {"20", "笔记页分页大小"},
	"label_list_limit":                         {"3000", "标签列表最大返回数"},
	"login_session_days":                       {"30", "登录状态有效期(天)"},
	"tag_recommend_strategy":                   {"recent", "TagInput 默认推荐策略"},
	"tag_recommend_manual_labels":              {"", "TagInput 手动精选推荐标签"},
	"tag_recommend_page_size":                  {"10", "TagInput 默认推荐数量"},
	"nav_max_items":                            {"1000", "导航页最多显示书签数"},
	"save_interval":                            {"30", "编辑器自动保存间隔(秒)"},
	"invite_code_enabled":                      {"0", "注册邀请码开关"},
	"invite_code":                              {"", "注册邀请码"},
	"share_comments_enabled":                   {"1", "分享页评论模块开关"},
	"share_comment_max_length":                 {"2000", "评论最大字符数"},
	"webrtc_signaling_enabled":                 {"1", "WebRTC 信令服务开关"},
	"webrtc_signaling_default_url":             {"", "WebRTC 默认信令地址，留空使用当前站点 /api/webrtc-signaling/ws"},
	"webrtc_signaling_max_peers":               {"16", "WebRTC 单房间最大连接数"},
	"webrtc_signaling_max_message_kb":          {"64", "WebRTC 信令单消息大小上限(KB)"},
	"webrtc_signaling_allow_local_file":        {"1", "允许本地 file/null Origin 调试 WebRTC 工具"},
	"webrtc_signaling_allowed_origins":         {"", "WebRTC 信令额外 Origin 白名单"},
	"webrtc_signaling_stun_urls":               {"stun:stun.l.google.com:19302\nstun:stun1.l.google.com:19302", "WebRTC 默认 STUN 服务器列表"},
	"webrtc_signaling_turn_url":                {"", "WebRTC 默认 TURN 服务器地址"},
	"webrtc_signaling_turn_username":           {"", "WebRTC TURN 用户名"},
	"webrtc_signaling_turn_credential":         {"", "WebRTC TURN 密码"},
	"favicon_cache_days":                       {"7", "Favicon缓存天数"},
	"asset_terminal_idle_timeout_seconds":      {"1800", "终端无操作自动断开时间(秒)"},
	"asset_terminal_scrollback_lines":          {"5000", "资产终端历史行数"},
	"webdav_file_max_bytes":                    {"52428800", "内置 WebDAV 单文件大小上限(bytes)"},
	"webdav_user_quota_bytes":                  {"1073741824", "内置 WebDAV 单用户逻辑容量(bytes)"},
	"webdav_public_file_max_bytes":             {"20971520", "WebDAV 公开静态资源单文件上限(bytes)"},
	"webdav_max_concurrent_transfers":          {"8", "内置 WebDAV 最大并发传输数"},
	"webdav_public_asset_separate_url_enabled": {"0", "WebDAV 公开静态资源使用独立基础地址"},
	"webdav_public_asset_base_url":             {"", "WebDAV 公开静态资源独立基础地址"},
	"upload_max_size":                          {"10485760", "上传文件大小上限(bytes)"},
	"upload_allowed_types":                     {"image/jpeg,image/png,image/gif,image/webp,image/svg+xml", "允许上传的MIME类型"},
	"upload_max_width":                         {"2048", "原图最大宽度(px)"},
	"upload_thumb_width":                       {"300", "缩略图宽度(px)"},
	"page_size_uploads":                        {"20", "图片管理页分页大小"},
	"ai_enabled":                               {"0", "AI 助手开关"},
	"ai_provider":                              {"openai", "AI 协议 (openai | anthropic)"},
	"ai_base_url":                              {"https://api.deepseek.com/v1", "AI 接口 base URL (OpenAI 协议) 或 https://api.anthropic.com (Anthropic)"},
	"ai_api_key":                               {"", "AI 接口 API Key"},
	"ai_model":                                 {"deepseek-chat", "AI 模型名"},
	"ai_temperature":                           {"0.7", "AI 温度"},
	"ai_max_tokens":                            {"2048", "AI 单次最大 token 数"},
	"ai_system_prompt_md":                      {"你是一个 Markdown 文档协作助手。回复使用 Markdown，简洁、信息密度高，不要寒暄。", "AI 系统提示词 (Markdown)"},
	"ai_system_prompt_html":                    {"你是一个 HTML 文档协作助手。回复直接给出可粘贴的 HTML 片段，不要包含解释。", "AI 系统提示词 (HTML)"},
	"ai_system_prompt_drawing":                 {"你是一个画板/白板协作助手。围绕当前画板内容提供结构、布局、流程图、草图和视觉表达建议。回复简洁、可直接执行；如果需要生成图形内容，优先给出可在画板中逐步绘制的元素、位置关系和标注说明。", "AI 系统提示词 (画板)"},
	"ai_actions_selection":                     {"", "AI 快捷动作 - 选中文本场景 (每行 label | prompt)"},
	"ai_actions_html":                          {"", "AI 快捷动作 - HTML 场景 (每行 label | prompt，prompt 可用 {subject} 占位)"},
	"ai_actions_book":                          {"", "AI 快捷动作 - 书籍章节场景 (每行 label | prompt)"},
	"ai_actions_article":                       {"", "AI 快捷动作 - 文章场景 (每行 label | prompt)"},
	"ai_actions_note":                          {"", "AI 快捷动作 - 笔记场景 (每行 label | prompt)"},
	"ai_actions_task":                          {"", "AI 快捷动作 - 待办场景 (每行 label | prompt)"},
	"ai_actions_empty":                         {"", "AI 快捷动作 - 空场景 (每行 label | prompt)"},
	"ai_total_prompt_tokens":                   {"0", "AI 累计输入 token"},
	"ai_total_completion_tokens":               {"0", "AI 累计输出 token"},
	"ai_total_requests":                        {"0", "AI 累计请求次数"},
	"mail_enabled":                             {"0", "邮件通知总开关"},
	"smtp_host":                                {"", "SMTP 服务器主机"},
	"smtp_port":                                {"587", "SMTP 服务器端口"},
	"smtp_encryption":                          {"starttls", "SMTP 加密方式 (starttls | tls | none)"},
	"smtp_username":                            {"", "SMTP 用户名"},
	"smtp_password":                            {"", "SMTP 密码"},
	"mail_from_name":                           {"BookStark", "邮件发件人名称"},
	"mail_from_address":                        {"", "邮件发件地址"},
	"mail_public_url":                          {"", "邮件内链接使用的公开站点地址"},
	"mail_timeout_seconds":                     {"10", "SMTP 连接与发送超时(秒)"},
	"task_email_reminder_enabled":              {"0", "待办邮件提醒总开关"},
	"password_reset_enabled":                   {"1", "邮件找回密码开关"},
	"password_reset_expiry_minutes":            {"30", "找回密码链接有效期(分钟)"},
}

const (
	DefaultLoginSessionDays = 30
	MinLoginSessionDays     = 1
	MaxLoginSessionDays     = 365
)

// GetLoginSessionDuration returns the lifetime used by newly issued login JWTs
// and their cookies. Invalid or unavailable settings fall back to 30 days.
func GetLoginSessionDuration() time.Duration {
	days := DefaultLoginSessionDays
	if DB != nil {
		if value, err := strconv.Atoi(GetSettingWithDefault("login_session_days", strconv.Itoa(days))); err == nil && value >= MinLoginSessionDays && value <= MaxLoginSessionDays {
			days = value
		}
	}
	return time.Duration(days) * 24 * time.Hour
}

type WebDAVSettings struct {
	FileMaxBytes           int64
	UserQuotaBytes         int64
	PublicFileMaxBytes     int64
	MaxConcurrentTransfers int
	SeparatePublicURL      bool
	PublicBaseURL          string
}

func GetWebDAVSettings() WebDAVSettings {
	cfg := WebDAVSettings{
		FileMaxBytes:           50 << 20,
		UserQuotaBytes:         1 << 30,
		PublicFileMaxBytes:     20 << 20,
		MaxConcurrentTransfers: 8,
	}
	if DB == nil {
		return cfg
	}
	cfg.FileMaxBytes = settingInt64InRange("webdav_file_max_bytes", cfg.FileMaxBytes, 1<<20, 2<<30)
	cfg.UserQuotaBytes = settingInt64InRange("webdav_user_quota_bytes", cfg.UserQuotaBytes, 10<<20, 1<<40)
	cfg.PublicFileMaxBytes = settingInt64InRange("webdav_public_file_max_bytes", cfg.PublicFileMaxBytes, 1<<20, 1<<30)
	cfg.MaxConcurrentTransfers = int(settingInt64InRange(
		"webdav_max_concurrent_transfers", int64(cfg.MaxConcurrentTransfers), 1, 32,
	))
	cfg.SeparatePublicURL = GetSettingWithDefault("webdav_public_asset_separate_url_enabled", "0") == "1"
	cfg.PublicBaseURL = strings.TrimRight(strings.TrimSpace(GetSetting("webdav_public_asset_base_url")), "/")
	return cfg
}

func settingInt64InRange(key string, fallback, minValue, maxValue int64) int64 {
	value, err := strconv.ParseInt(GetSettingWithDefault(key, strconv.FormatInt(fallback, 10)), 10, 64)
	if err != nil || value < minValue || value > maxValue {
		return fallback
	}
	return value
}

type MailSettings struct {
	Enabled              bool
	TaskReminderEnabled  bool
	PasswordResetEnabled bool
	PasswordResetExpiry  time.Duration
	Host                 string
	Port                 int
	Encryption           string
	Username             string
	Password             string
	FromName             string
	FromAddress          string
	PublicURL            string
	Timeout              time.Duration
}

func GetMailSettings() MailSettings {
	cfg := MailSettings{
		Port:                587,
		Encryption:          "starttls",
		FromName:            "BookStark",
		Timeout:             10 * time.Second,
		PasswordResetExpiry: 30 * time.Minute,
	}
	if DB == nil {
		return cfg
	}
	cfg.Enabled = GetSettingWithDefault("mail_enabled", "0") == "1"
	cfg.TaskReminderEnabled = GetSettingWithDefault("task_email_reminder_enabled", "0") == "1"
	cfg.PasswordResetEnabled = GetSettingWithDefault("password_reset_enabled", "1") == "1"
	cfg.Host = strings.TrimSpace(GetSetting("smtp_host"))
	if n, err := strconv.Atoi(GetSettingWithDefault("smtp_port", "587")); err == nil && n >= 1 && n <= 65535 {
		cfg.Port = n
	}
	encryption := strings.ToLower(strings.TrimSpace(GetSettingWithDefault("smtp_encryption", "starttls")))
	if encryption == "starttls" || encryption == "tls" || encryption == "none" {
		cfg.Encryption = encryption
	}
	cfg.Username = strings.TrimSpace(GetSetting("smtp_username"))
	cfg.Password = GetSetting("smtp_password")
	cfg.FromName = strings.TrimSpace(GetSettingWithDefault("mail_from_name", "BookStark"))
	cfg.FromAddress = strings.TrimSpace(GetSetting("mail_from_address"))
	cfg.PublicURL = strings.TrimRight(strings.TrimSpace(GetSetting("mail_public_url")), "/")
	if n, err := strconv.Atoi(GetSettingWithDefault("mail_timeout_seconds", "10")); err == nil && n >= 3 && n <= 60 {
		cfg.Timeout = time.Duration(n) * time.Second
	}
	if n, err := strconv.Atoi(GetSettingWithDefault("password_reset_expiry_minutes", "30")); err == nil && n >= 5 && n <= 120 {
		cfg.PasswordResetExpiry = time.Duration(n) * time.Minute
	}
	return cfg
}

func (s MailSettings) Ready() bool {
	return s.Enabled && s.Host != "" && s.Port > 0 && s.FromAddress != ""
}

func (s MailSettings) PasswordResetReady() bool {
	return s.Ready() && s.PasswordResetEnabled && s.PublicURL != "" && s.PasswordResetExpiry > 0
}

type WebRTCSignalingSettings struct {
	Enabled         bool
	DefaultURL      string
	MaxPeers        int
	MaxMessageBytes int64
	AllowLocalFile  bool
	AllowedOrigins  []string
	STUNURLs        []string
	TURNURL         string
	TURNUsername    string
	TURNCredential  string
}

func DefaultWebRTCSignalingSettings() WebRTCSignalingSettings {
	return WebRTCSignalingSettings{
		Enabled:         true,
		DefaultURL:      "",
		MaxPeers:        16,
		MaxMessageBytes: 64 << 10,
		AllowLocalFile:  true,
		AllowedOrigins:  nil,
		STUNURLs: []string{
			"stun:stun.l.google.com:19302",
			"stun:stun1.l.google.com:19302",
		},
	}
}

func GetWebRTCSignalingSettings() WebRTCSignalingSettings {
	cfg := DefaultWebRTCSignalingSettings()
	if DB == nil {
		return cfg
	}
	cfg.Enabled = GetSettingWithDefault("webrtc_signaling_enabled", "1") == "1"
	cfg.DefaultURL = strings.TrimSpace(GetSetting("webrtc_signaling_default_url"))
	if n, err := strconv.Atoi(GetSettingWithDefault("webrtc_signaling_max_peers", "16")); err == nil && n >= 2 && n <= 64 {
		cfg.MaxPeers = n
	}
	if n, err := strconv.Atoi(GetSettingWithDefault("webrtc_signaling_max_message_kb", "64")); err == nil && n >= 8 && n <= 512 {
		cfg.MaxMessageBytes = int64(n) << 10
	}
	cfg.AllowLocalFile = GetSettingWithDefault("webrtc_signaling_allow_local_file", "1") == "1"
	cfg.AllowedOrigins = splitSettingLines(GetSetting("webrtc_signaling_allowed_origins"))
	stunURLs := splitSettingLines(GetSetting("webrtc_signaling_stun_urls"))
	if len(stunURLs) > 0 {
		cfg.STUNURLs = stunURLs
	}
	cfg.TURNURL = strings.TrimSpace(GetSetting("webrtc_signaling_turn_url"))
	cfg.TURNUsername = strings.TrimSpace(GetSetting("webrtc_signaling_turn_username"))
	cfg.TURNCredential = GetSetting("webrtc_signaling_turn_credential")
	return cfg
}

func splitSettingLines(value string) []string {
	fields := strings.FieldsFunc(value, func(r rune) bool {
		return r == '\n' || r == '\r' || r == ','
	})
	result := make([]string, 0, len(fields))
	seen := make(map[string]bool, len(fields))
	for _, field := range fields {
		item := strings.TrimSpace(field)
		if item == "" || seen[item] {
			continue
		}
		seen[item] = true
		result = append(result, item)
	}
	return result
}

// IncrementSettingInt atomically adds delta to an integer-valued setting and
// returns the new value. The setting is created (with value=delta) if missing.
// Used by the AI controller to track cumulative token usage without a full
// settings round-trip.
func IncrementSettingInt(key string, delta int64) (int64, error) {
	tx, err := DB.Begin()
	if err != nil {
		return 0, err
	}
	var current int64
	row := tx.QueryRow("SELECT CAST(value AS INTEGER) FROM md_settings WHERE key = ?", key)
	if err := row.Scan(&current); err != nil {
		current = 0
	}
	newVal := current + delta
	now := time.Now()
	if _, err := tx.Exec(`
		INSERT INTO md_settings (key, value, description, update_time)
		VALUES (?, ?, '', ?)
		ON CONFLICT(key) DO UPDATE SET value = excluded.value, update_time = excluded.update_time`,
		key, strconv.FormatInt(newVal, 10), now,
	); err != nil {
		tx.Rollback()
		return 0, err
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return newVal, nil
}

// GetSetting returns the value for a given key, or empty string if not found
func GetSetting(key string) string {
	var value string
	err := DB.QueryRow("SELECT value FROM md_settings WHERE key = ?", key).Scan(&value)
	if err != nil {
		return ""
	}
	return value
}

// GetSettingValue returns the stored setting value and whether the key exists.
func GetSettingValue(key string) (string, bool) {
	var value string
	err := DB.QueryRow("SELECT value FROM md_settings WHERE key = ?", key).Scan(&value)
	if err != nil {
		return "", false
	}
	return value, true
}

// GetSettingWithDefault returns the value for a given key, or the fallback if not found
func GetSettingWithDefault(key, fallback string) string {
	val := GetSetting(key)
	if val == "" {
		return fallback
	}
	return val
}

// GetAllSettingsDetailed returns all settings with full detail
func GetAllSettingsDetailed() ([]Setting, error) {
	rows, err := DB.Query("SELECT key, value, description, update_time FROM md_settings ORDER BY key LIMIT 200")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Setting
	for rows.Next() {
		var s Setting
		var updateTime sql.NullTime
		if err := rows.Scan(&s.Key, &s.Value, &s.Description, &updateTime); err != nil {
			return nil, err
		}
		if updateTime.Valid {
			s.UpdateTime = updateTime.Time
		}
		result = append(result, s)
	}
	return result, nil
}

// BatchUpdateSettings updates multiple settings at once
func BatchUpdateSettings(settings map[string]string) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	now := time.Now()
	for k, v := range settings {
		_, err := tx.Exec(`
			INSERT INTO md_settings (key, value, description, update_time)
			VALUES (?, ?, '', ?)
			ON CONFLICT(key) DO UPDATE SET value = excluded.value, update_time = excluded.update_time`,
			k, v, now,
		)
		if err != nil {
			tx.Rollback()
			return fmt.Errorf("update setting %s: %w", k, err)
		}
	}
	return tx.Commit()
}

// InitDefaultSettings inserts default settings for keys that don't exist yet
func InitDefaultSettings() error {
	for key, def := range defaultSettings {
		var count int
		err := DB.QueryRow("SELECT COUNT(*) FROM md_settings WHERE key = ?", key).Scan(&count)
		if err != nil {
			return err
		}
		if count == 0 {
			_, err := DB.Exec(
				"INSERT INTO md_settings (key, value, description, update_time) VALUES (?, ?, ?, ?)",
				key, def.Value, def.Description, time.Now(),
			)
			if err != nil {
				return fmt.Errorf("init setting %s: %w", key, err)
			}
		}
	}
	return nil
}

// GetLabelListLimit returns the max number of labels to return in list queries
// Result is cached for 60 seconds to avoid repeated DB queries.
var (
	labelListLimitCache   int
	labelListLimitCacheAt time.Time
	labelListLimitMu      sync.RWMutex
)

func GetLabelListLimit() int {
	labelListLimitMu.RLock()
	if time.Since(labelListLimitCacheAt) < 60*time.Second {
		v := labelListLimitCache
		labelListLimitMu.RUnlock()
		return v
	}
	labelListLimitMu.RUnlock()

	labelListLimitMu.Lock()
	defer labelListLimitMu.Unlock()

	// Double-check after acquiring write lock
	if time.Since(labelListLimitCacheAt) < 60*time.Second {
		return labelListLimitCache
	}

	val := GetSetting("label_list_limit")
	n := 3000
	if val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 {
			n = parsed
		}
	}
	labelListLimitCache = n
	labelListLimitCacheAt = time.Now()
	return n
}

// GetNavMaxItems 返回导航页最多展示的书签数。结果缓存 60 秒。
var (
	navMaxItemsCache   int
	navMaxItemsCacheAt time.Time
	navMaxItemsMu      sync.RWMutex
)

func GetNavMaxItems() int {
	navMaxItemsMu.RLock()
	if time.Since(navMaxItemsCacheAt) < 60*time.Second {
		v := navMaxItemsCache
		navMaxItemsMu.RUnlock()
		return v
	}
	navMaxItemsMu.RUnlock()

	navMaxItemsMu.Lock()
	defer navMaxItemsMu.Unlock()

	if time.Since(navMaxItemsCacheAt) < 60*time.Second {
		return navMaxItemsCache
	}

	val := GetSetting("nav_max_items")
	n := 1000
	if val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed >= 1 && parsed <= 100000 {
			n = parsed
		}
	}
	navMaxItemsCache = n
	navMaxItemsCacheAt = time.Now()
	return n
}

// GetFaviconCacheDays returns the number of days to cache favicon files.
// Result is cached for 60 seconds to avoid repeated DB queries.
var (
	faviconCacheDaysCache   int
	faviconCacheDaysCacheAt time.Time
	faviconCacheDaysMu      sync.RWMutex
)

func GetFaviconCacheDays() int {
	faviconCacheDaysMu.RLock()
	if time.Since(faviconCacheDaysCacheAt) < 60*time.Second {
		v := faviconCacheDaysCache
		faviconCacheDaysMu.RUnlock()
		return v
	}
	faviconCacheDaysMu.RUnlock()

	faviconCacheDaysMu.Lock()
	defer faviconCacheDaysMu.Unlock()

	if time.Since(faviconCacheDaysCacheAt) < 60*time.Second {
		return faviconCacheDaysCache
	}

	val := GetSetting("favicon_cache_days")
	n := 7
	if val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed >= 1 && parsed <= 365 {
			n = parsed
		}
	}
	faviconCacheDaysCache = n
	faviconCacheDaysCacheAt = time.Now()
	return n
}
