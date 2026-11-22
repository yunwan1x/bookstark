# 36 WebDAV服务策略：实现前设计
2026-11-07，内置imagegen原型与完整提示词已保存，图中容量与URL均示例，没有探测网络。白底浅蓝12dp卡片、16dp边距48dp控件；容量/传输四字段、公开静态资源开关与基础地址、底部固定保存。320dp200%字体保持完整字节输入不裁数字，长地址可横向编辑、键盘下可滚动。无删除/清理文件操作。

六个键webdav_file_max_bytes/user_quota_bytes/public_file_max_bytes/max_concurrent_transfers/public_asset_separate_url_enabled/public_asset_base_url。真实GET/PUT admin/settings仅dirty字段。Go trim后的整数范围：单文件1048576–2147483648，用户容量10485760–1099511627776，公开文件1048576–1073741824，并发1–32；开关0/1。容量以字节编辑，不能为了MiB显示舍入或改写未改原值；Web编译也须支持1TiB边界。

非空基础地址要求HTTP(S)+host、无userInfo/查询参数/片段，客户端可拒绝空问号片段标记等更严格输入；服务端url.ParseRequestURI权威。启用独立地址要求非空基础地址，不静默关闭开关或填例子。服务端保存会TrimSpace并去除尾部所有/，已知回执回读显示实际规范结果；原始未修改URL不发送。降低限额只保存策略，不删除已有文件，不声称资源地址可达。

fresh管理员/session、保存冻结、known回执只读重试、unknown显式核对采用、不自动重发、离开屏障同36。需上下界/超大整数/URL凭据查询与前缀/dirty隔离fakeHTTP与控制器、320dp200%widget、真实Go隔离SQL、NAS redroid入口保存，原数据保留。独立资产地址运行效果另结合资产公共页回归，非本页保存即证明。

实施中：原型后已写入受限字段数据层、Flutter表单与控制器，并接入系统设置内部导航。子页专项检查已通过（具体日志在next-stage/admin36-app-integration）；完整视觉/后端/ARM64 redroid验收待完成，不作为整组验收。确认框绑定当前设置内部Navigator，会话退出清空所有owned控制器并移除内部确认框。
