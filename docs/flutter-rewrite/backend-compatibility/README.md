# 服务端兼容性待办

## HTML 回收站丢失编辑格式（真实服务已复现）

独立测试实例创建 HTML → 删除 → 还原后，原 blog_id 保留，但 `editor_type` 由 `html` 变为 `markdown`，原始正文 GET 返回400。证据 `html-trash-current-server-proof.json`，可复核测试脚本位于 NAS APK 测试目录 `redroid-arm64/audit_html_trash.py`。脚本仅访问自有 disposable fixture，测试资源及回收站记录已清理。

原因：`models/trash.go` 的 BlogSnap 未记录 EditorType，restoreBlog 的 INSERT 也未写入 editor_type，数据库回落到默认 markdown。HTML 内容可能仍以压缩格式存储，因此客户端不得猜类型再走 Markdown 保存。

`html-trash-editor-type.patch` 是待验证补丁：新增快照字段、采集现有类型，并在还原时写回；字段缺失的旧快照按历史 markdown 默认处理。该补丁尚未应用到项目 Go 源码，未修改、重建或部署现有 Go 服务。

后续必须在隔离源码副本中验证：HTML/Markdown 及其他编辑格式的原ID/正文/类型/保护状态、标签/分享保留；旧无字段 Markdown 快照兼容；错误回滚。完成后再做实际 HTTP 契约，不能以 patch 存在宣称已修复。旧的 HTML 快照本身已丢失类型，补丁不能凭空恢复，需要另外设计可核对的历史恢复策略。位置等其他元数据保留仍需审计。
