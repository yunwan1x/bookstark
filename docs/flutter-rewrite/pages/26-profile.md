# 26 我的与个人资料总览：实现前原型与协议

2026-11-05。先生成并发送26-profile.png再实现。原型是已连接服务器账户：浅蓝背景，真实账号/角色/当前服务器卡、邮箱与默认打开模块卡、账户安全/邮件提醒/外观背景/后续27令牌与28回收站入口、应用语言、退出服务器空间。底部延续现有五栏。账号头像仅由首字母生成，不假装服务支持头像上传/昵称。所有子页面各自先补原型和文档；未接入的入口不能放一个空回调假装完成。

GET /api/profile 返回member_id/account/email/role/default_home，不返回昵称、简介或头像。PUT /api/profile 实际只保存email/default_home；bio虽接受校验但没有落库，不提供伪简介表单。email必须有效且Go按UTF8字节≤200。default_home实际枚举home/notes/tasks/articles/books/bookmarks/nav/search，未知值不静默覆盖。编辑资料需保留未改字段并回读准确值，断线未知只读核对，不自动再次PUT。刷新失败不得显示为已保存或空账号；服务器/成员必须与当前登录上下文匹配。

账户安全实际PUT /api/password；body old_password/new_password，旧密码必填，新密码Go validator min=6加len≤72 UTF8字节。服务回写新的token Cookie，客户端必须同步安全持久化实际新会话；不能把旧cookie留作重启恢复。密码不写草稿/日志/普通磁盘，Web需覆盖所有挂载输入的清除，不能仅检查controller。未知结果不能自动再次修改或无提示重复登录；新的候选验证及重新登录流程另设计明确操作。

邮件提醒GET/PUT /api/profile/task-reminder：enabled/send_time HH:MM/remind_before_days0—30/include_overdue/email/available/last_processed_date。available来自真实管理员邮件配置及全局待办提醒开关；不可用时不能伪造启用成功。测试邮件是显式用户操作，自动回归只用自有loopback模拟SMTP，不向真实地址发信。个人密码、提醒、外观背景分别做独立页面原型/回归。

背景GET/PUT /api/profile/background、私有image下载有真实协议，native需替代DOM/CSS效果和文件权限；继续核对上传格式/体积/动画/淡化/背景音乐等旧profile功能。Web PWA安装等仅浏览器概念要映射到原生离线/缓存/更新能力，分别保留到44/45验证，不默默删除功能。管理员友情链接留38；API/WebDAV应用密码留27。

语言改动应更新整个App及持久偏好，不只切当前页面标签；退出清除当前服务器会话并停止播放/流请求，保留本地数据库和附件，需按当前草稿/未知请求做清楚确认。当前首页根导航profile仍未接新实现；此文仅设计，25的499检查点已先归档，之后继续实现26。
