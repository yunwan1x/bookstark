# 36 协作信令：实现前设计
2026-11-07，内置imagegen单页原型与完整提示词已保存，示例端点不是真实连接；无连接测试API，不放假测试按钮。白底、浅蓝卡片、16dp边距、12dp圆角、48dp目标，底部固定保存；320dp/200%字体连接数与消息上限单列，长地址/多行来源与STUN可滚动，键盘下保存可达。

本页全部十项 webrtc_signaling_enabled/default_url/max_peers/max_message_kb/allow_local_file/allowed_origins/stun_urls/turn_url/turn_username/turn_credential。前四项在主卡，来源与STUN为多行，TURN展开区包含地址/账号/默认隐藏的凭据及眼睛，本地文件调试独立开关。无输入时不伪造样例或静默填默认。原值只放内存、未修改不提交或规范化。

真实GET/PUT admin/settings。Go validateWebRTCSignalingSetting检查开关0/1，连接数2–64整数、消息8–512KB整数，default_url允许空否则trim后ws/wss+host；来源按换行/CR/逗号分割trim，非空项http/https+host；STUN每项stun:前缀；TURN空或turn:/turns:前缀，用户名/凭据原始UTF8长度<=256。客户端遵循相同边界，不把其简略前缀检查宣传为实际可连。存储保留原始合法字符串，未修改历史值保留。

TURN凭据无SMTP空值保留规则，用户主动清空会清除；非空改空需绑定当前revision确认。其他字段/场景不跟随清空或切换开关。保存fresh核权/会话冻结，未知结果只读核对（凭据默认隐藏，可显式核对），不自动重发。离开保存/放弃/继续，退出/换会话销毁所有敏感控制器。

需fakeHTTP十key白名单/字节范围/分隔符保留/清空确认、异步权限/未知回执、窄屏widget，真实Go隔离保存逐键SQL核验与NAS redroid真实入口。此页仅配置信令策略，运行协作连接另属相关文档页回归，不能宣称保存即协作已通。

实施中：原型后已写入受限字段数据层、Flutter表单与控制器，并接入系统设置内部导航。子页专项检查已通过（具体日志在next-stage/admin36-app-integration）；完整视觉/后端/ARM64 redroid验收待完成，不作为整组验收。确认框绑定当前设置内部Navigator，会话退出清空所有owned控制器并移除内部确认框。
