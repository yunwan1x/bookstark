# 36 内容与上传：实现前设计
2026-11-07，imagegen内置工具原型36-admin-content-upload-v1.png与完整提示词已保存；示例值不是当前设置，未实现或验收。

白底、浅蓝卡片、16dp边距、12dp圆角、底部固定保存；上传限制卡含 upload_max_size（字节）、upload_allowed_types（逗号分隔MIME原文）、upload_max_width、upload_thumb_width、page_size_uploads；评论卡含 share_comments_enabled 与 share_comment_max_length；标签推荐与公开页面标签分别进入独立先设计的子页。320dp200%文字上下布局、长MIME可换行、键盘下字段和保存可达。

真实GET/PUT admin/settings，只提交本页dirty键，不擅自更新标签子页。Go对page_size_uploads验证1–200（网页min5不代表API下限）、评论字符100–5000和开关0/1。上传大小1024–1073741824、宽100–16384、缩略图50–2000来自现有网页表单限制，Go此接口并未同样检查；在Flutter提供相同输入限制并明确属于客户端校验，不声称服务器已强化。未修改历史值不提交或强制规范化，缺失不填默认。MIME保持原文，不因展示换行重写；不要假定浏览器accept等于安全校验。

保存fresh核权、会话绑定、冻结、已知回执回读/未知只读核对、不重发和离开屏障沿用36。空MIME清空语义以服务端实际代码为准，不凭示例推断；不做真实生产上传来验证。需隔离Go保存SQL逐键核对、范围/未知字段fakeHTTP、窄屏大字、NAS redroid真实入口；原表/附件保留。未完成36与45组。

源码补充：models/upload.go 的 GetUploadAllowedTypes 在保存空字符串时会回退默认图片 MIME 列表，并有约60秒缓存。UI要说明“留空使用服务器默认图片类型”，不能说空值禁止所有上传。

实施进度：原型后已写入Flutter表单/控制器与有界白名单更新类型，仍在组合回归。通用/分页共5项测试通过，原始数字拼写仅在明确修改时提交；未配置字段不伪造默认。完整管理入口、隔离Go与NAS redroid验证尚待完成，不作为本组验收。
