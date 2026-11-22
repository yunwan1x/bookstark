# 36 系统设置范围核对（实现前）

2026-11-07，依据models/setting.go默认键名与现有admin模板/接口，只读源码核对；未读取运行设置值。74个默认键全部列在下面，不能因首批原型只展示常用表单而遗漏。数据库可能存在扩展/历史未知键；客户端保留且不擅自覆写。计数用量只读，不提供通用“任意key更新”界面。

分类入口已有原型；AI连接、SMTP连接、邮件功能已有单页原型与文档。提示词/编辑动作单页原型与文档也已补齐并开始实现。其他子页面（公共标签、WebRTC信令、终端策略和高级WebDAV）必须各自先原型后实现，不能用已有六行入口图代替它们的设计。资产终端策略可放在对应40页面内管理并从系统设置进入，但需保留跨页导航与权限回归。

## 通用设置

- `page_size_books`
- `page_size_blogs`
- `page_size_shares`
- `page_size_bookmarks`
- `page_size_labels`
- `page_size_notes`
- `label_list_limit`
- `login_session_days`
- `nav_max_items`
- `save_interval`
- `favicon_cache_days`

## 内容与上传

- `tag_recommend_strategy`
- `tag_recommend_manual_labels`
- `tag_recommend_page_size`
- `share_comments_enabled`
- `share_comment_max_length`
- `upload_max_size`
- `upload_allowed_types`
- `upload_max_width`
- `upload_thumb_width`
- `page_size_uploads`

## 访问与注册

- `invite_code_enabled`
- `invite_code`
- `webrtc_signaling_enabled`
- `webrtc_signaling_default_url`
- `webrtc_signaling_max_peers`
- `webrtc_signaling_max_message_kb`
- `webrtc_signaling_allow_local_file`
- `webrtc_signaling_allowed_origins`
- `webrtc_signaling_stun_urls`
- `webrtc_signaling_turn_url`
- `webrtc_signaling_turn_username`
- `webrtc_signaling_turn_credential`

## 资产终端设置

- `asset_terminal_idle_timeout_seconds`
- `asset_terminal_scrollback_lines`

## WebDAV服务

- `webdav_file_max_bytes`
- `webdav_user_quota_bytes`
- `webdav_public_file_max_bytes`
- `webdav_max_concurrent_transfers`
- `webdav_public_asset_separate_url_enabled`
- `webdav_public_asset_base_url`

## AI模型与提示词

- `ai_enabled`
- `ai_provider`
- `ai_base_url`
- `ai_api_key`
- `ai_model`
- `ai_temperature`
- `ai_max_tokens`
- `ai_system_prompt_md`
- `ai_system_prompt_html`
- `ai_system_prompt_drawing`
- `ai_actions_selection`
- `ai_actions_html`
- `ai_actions_book`
- `ai_actions_article`
- `ai_actions_note`
- `ai_actions_task`
- `ai_actions_empty`

## AI只读用量

- `ai_total_prompt_tokens`
- `ai_total_completion_tokens`
- `ai_total_requests`

## 邮件服务

- `mail_enabled`
- `smtp_host`
- `smtp_port`
- `smtp_encryption`
- `smtp_username`
- `smtp_password`
- `mail_from_name`
- `mail_from_address`
- `mail_public_url`
- `mail_timeout_seconds`
- `task_email_reminder_enabled`
- `password_reset_enabled`
- `password_reset_expiry_minutes`

## 模板动态公共标签

另外四个public_feed_tags_article / public_feed_tags_note / public_feed_tags_book / public_feed_tags_bookmark，不在默认map的74键里，属于内容与上传子页；必须沿用ValidatePublicTagConfig与现有PublicTagSections语义。实际系统其他未知键不会丢弃。

WebRTC下的TURN凭据、邀请码、AI Key、SMTP密码均不进入日志/公开证据；这里只枚举字段名。SMTP有特殊空值保留规则，其他字段不能类推。全量范围完成需每个可写键的真实协议、数据回读和UI路径，不能把默认值写入未知或缺失的服务器设置。
