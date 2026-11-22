# 04 重设密码

原型 `04-reset.png`。标准返回栏、标题和说明、服务器、重置链接/令牌双行框、新密码、确认密码、保存按钮和一次性链接说明。

接受原始token或现有邮件 `/reset-password#token=...` 链接。完整链接必须和表单中服务器同源，且路径匹配部署前缀，防止将token送到错误服务器。POST `/api/password/reset` 使用 `token/new_password/confirm_password`。不记录或持久化重置令牌。短密码、不匹配、过期和已使用令牌分别处理；成功后清空密码/token并提示回登录。服务端校验不由前端替代。当前：设计已完成，待实现和回归。
