# 回收站编辑格式兼容补丁的隔离验证

补丁仍仅位于html-trash-editor-type.patch，未应用到生产Go源码或服务。模型测试在photos-apk-test/bookstark-flutter/html-trash-compat/source隔离副本中执行，Go SDK为已缓存golang1.25-alpine（实际go1.25.14）。没有读取运行中数据库/认证配置，没有监听服务端口。

先运行未打补丁源码，确认快照缺失editor_type并还原成markdown；再仅向副本应用补丁，同一测试通过。9个用例覆盖普通/受保护HTML、Markdown、表格、画板、脑图、富文档、演示与未来未知类型，另有旧快照未含类型的兼容用例。核对原ID、储存正文、保护哈希、解锁后的全部HTML和标签ID。摘要日志和源码hash见validation/2026-11-06-html-trash-compat-model-proof.json；测试源以.txt保存，避免进入生产Go包。

这是模型层验证，不声称完整HTTP或已部署。最初隔离容器/tmp默认noexec导致测试二进制不能启动，调整该临时容器的tmpfs exec后，才执行有效的未补丁失败/补丁成功对照。原生产models/trash.go的SHA256保持0c63abbfabc64fd0d214b66bc9b0d0192f4390fb362263fc51a8bee8cae35773。

旧HTML快照若原本就没有editor_type，不能安全地从正文猜格式；补丁保持旧默认markdown，不声称自动修复历史缺失元数据。部署前还需隔离HTTP回归及具体部署审阅。
