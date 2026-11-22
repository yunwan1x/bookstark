# 40 远程终端 V1：实施前原型与协议
日期：2026-11-07。状态：实施与回归中，尚未验收。39已完成独立ARM64原生验收，全部45组未完成。

## 原型
内置 image_gen / imagegen 技能生成并先保存：
- ../../prototypes/flutter-rewrite-2026-11-04/40-admin-terminal-v1.png
- 同名 .prompt.txt 保留完整提示词。
三屏依次为连接前核对、正在连接的终端、已断开后明确重连。生成图是布局/色彩依据，不是运行证据。原型中的示例主机/凭据ID仅用于设计，产品读取真实ID；没有凭据原文。终端示例内容仅无害 printf 输出。

## 布局契约
390×844基准，白底、56dp顶部栏、16dp页边距、12dp圆角。连接核对页用浅蓝主机卡，显示主机ID、用户名@地址:端口、Shell和凭据名称#ID。底部为“连接终端”，进入核对页不产生SSH或WebSocket。
连接页顶部显示主机名称、实时会话状态和用户/真实主机ID。深色终端 #080b10，前景 #d8e4f0，等宽13sp/1.2行高；只为终端设独立字体缩放，Flutter外围遵守系统字体缩放。终端布局变化用真实可用像素计算列/行，再发resize。
下方单行横向滚动快捷键 Esc、Tab、Ctrl+C、↑↓←→；底部键盘/粘贴/断开。IME出现时缩小终端视口并发送resize，不遮住输入行。200%文字时状态条换行、工具条可横向滚动；可点击区域至少48dp。
断开保留当前页内的末尾输出和明确状态，显示“重新连接”。重连创建全新会话，不恢复已发送输入。后台/离开时关闭传输并销毁终端正文，返回需重新连接，不恢复秘密输出。
操作补充原型40-admin-terminal-actions-v1.png及同名设计文档已先保存，覆盖IME、明确粘贴、断开与失效；中英小屏/200%及横屏仍需实际实现回归，不把原型当作运行证据。

## 现有真实协议（源码核对，后续仍须隔离Go实测）
来源 controllers/assets.go:AssetSSHTerminal/checkAssetWSOrigin、services/asset_terminal.go、routers/router.go、static/js/assets.js:createTerminal/openSession/closeSession。
管理员GET /api/admin/assets/ssh-hosts/:id/terminal升级WebSocket；主机不存在404、无会话401、非管理员403。Origin允许空或host相同；移动传输使用配置服务器的同源Origin，不把中继/随机WebView源当成服务器Origin。
JSON文本消息：客户端 input{data}、resize{cols,rows}、close；服务端 ready{data:'connected'}、output{data}、error{data}、closed{data}。连接成功必须等待ready，HTTP101不是SSH就绪。服务端输出stdout和stderr；25秒ping、60秒pong读期限、10秒写期限，SSH30秒keepalive/10秒超时；空闲策略从资产设置读取。Dart原生WebSocket负责pong，不发伪造JSON ping。
现有Go为SSH PTY xterm(初始120列32行)，启动配置Shell/工作目录；远程命令只在owned测试SSH运行。旧39 handshake-only SSH拒绝session，不能拿其握手成功证明40命令或PTY工作。需新建仅隔离容器内允许的受控PTY fixture。
Go目前使用InsecureIgnoreHostKey；本阶段不修改生产Go，不把UI“已连接”描述为已完成主机密钥指纹验证。
协议没有命令回执、持久会话ID或会话恢复；输入发送后丢线无法判断远端是否执行。客户端不得自动重发、缓存待执行命令或自动重连。

## 实现边界
Flutter负责管理员拥有的Scope、连接核对/状态、快捷键、明确重连/断开及生命周期。正文复用项目已有xterm.js/addon-fit及原许可证，使用单独内存WebView入口；不装载整个旧管理页面，不向JS暴露服务器Cookie、密码或私钥。
由Dart IO WebSocket负责认证、Origin和网络，WebView只通过有界消息桥传入输入/resize并接收输出；所有消息绑定随机运行租约及本次连接generation，旧页面、旧连接和晚到回调不能写入新终端。Web版本以独立合成传输预览，不冒充真实移动认证。
已核对本机Dart3.13.7的WebSocket.connect实现：内部openUrl后没有禁用HTTP重定向，不能直接假定其拒绝重定向。实现须使用本次连接专属HttpClient，明确关闭请求followRedirects并限定目标，关闭/取消时同时退休握手及已升级socket；错误只读结构化HTTP状态，不把异常原文交给UI。必须用隔离302/307测试证明未向第二目标发送Cookie。
URL只含固定路由和真实安全整数ID；配置路径前缀保留，http/https映射ws/wss，禁止userinfo/重定向/认证token查询参数。凭据只由既有Go取用，Flutter不会读取凭据列表中的secret来自己SSH连接。
每次连接/重连前重新核对管理员身份与目标主机ID；后台、退出、切换账号、owner失效必须关闭socket/bridge/WebView并清空内存输出。连接窗口默认FLAG_SECURE，沿用独立租约机制；不写磁盘scrollback、IndexedDB、localStorage、日志或恢复草稿。
复用现有终端队列思路：应用端明确字节上限1MiB、每帧最多64KiB，溢出用固定截断标记；单条输入、消息大小及resize范围有界，不能无限积压。显示输出不执行HTML/URL，不接受远程OSC触发剪贴板写入、链接外跳、下载或权限请求。
Ctrl+C只发送控制字符\x03，表示“向会话发送中断”，不宣称远程进程一定已停止；断开独立close+关闭WebSocket。粘贴须明确操作，多行/回车预览后发送；没有自动复制选中文本或后台读取剪贴板。

## 回归契约
先测试模型/URI前缀/JSON与UTF8边界、有界队列、代际/owner/lifecycle、不可重发、真实目标变更及input/resize/close状态机；WebView桥需实际JS/ANSI/IME键盘操作验证，不能用假平台视图代替。
真实Go+owned SSH证明：PTY/window-change/实际无害命令回显、Ctrl+C字节、明确定义的关闭、断线不重放、重新连接新SSH会话、权限拒绝、空闲超时及连接前无SSH。测试服务不暴露宿主端口，不执行宿主/NAS命令。
NAS redroid只运行ARM64 APK（原生桥译码，如实标注非ARM硬件），核对实际安装hash、引擎映射、键盘/缩放/旋转/生命周期/关闭、实际WebView正文、FLAG_SECURE及请求隔离。每轮原18表/2文档/5附件/原偏好和会话须精确恢复。浏览器/fixture证据不能替代原生。
