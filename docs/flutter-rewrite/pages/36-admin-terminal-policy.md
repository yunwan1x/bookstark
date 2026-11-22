# 36 终端策略（40资产页共享入口）：实现前设计
2026-11-07，内置imagegen单页原型和完整提示词已保存，数值设计示例，无真实终端操作。会话策略/终端显示两浅蓝卡，白底深蓝、16dp边距12dp圆角48dp目标、底部保存；320dp200%字体可滚动/键盘避让。页内提示只改终端策略，不改变登录凭据/资产加密密钥；实际连接生效时机由服务器决定。

仅asset_terminal_idle_timeout_seconds整数1–86400、asset_terminal_scrollback_lines整数500–50000。范围来自models/asset.go实际运行parse与UpdateAssetSettings校验；admin/settings接口本身无同等校验，不声称服务器已强化。通过管理员GET/PUT admin/settings只保存dirty的这两key，绝不调用含asset_credential_secret与重加密副作用的PUT /api/assets/settings。未知扩展密钥等保留，不显示/日志记录。

旧系统若缺少秒key仍可能使用asset_terminal_idle_timeout_minutes，UI显示未配置秒值而不伪造默认或自动转换；只有用户明确输入新秒值才建立新key，保留旧分钟key和其他资产配置。数值原样仅更改后提交，不截断/clamp。此页同时供36与后续40进入同一真实策略页面，40其他资产/终端功能仍需独立原型与回归。

保存fresh管理员/会话检查、冻结、已知回执回读/未知只读核对、不重发与离开屏障同36。需fakeHTTP只两key无secret/无资产endpoint、上下界与缺失旧key、窄屏widget、隔离Go SQL及NAS redroid真实入口。不启动真实用户SSH会话或改变生产策略来验证。原数据保留。

实施中：原型后已写入受限字段数据层、Flutter表单与控制器，并接入系统设置内部导航。子页专项检查已通过（具体日志在next-stage/admin36-app-integration）；完整视觉/后端/ARM64 redroid验收待完成，不作为整组验收。确认框绑定当前设置内部Navigator，会话退出清空所有owned控制器并移除内部确认框。
