# 09 公开文章 Markdown WebView v5

2026-11-09：先保存两张内置 imagegen 原型及本文档，再写页面。主图 public-article-v5.png 展示明确文章、密码弹窗、旧分享兼容、暂停；补图 public-article-errors-v5.png 展示部分图片失败及分享不可用。示例标题/作者/正文仅用于原型，运行时全部取真实数据。

界面沿用09紫色#6530ad、白字56dp顶栏、白底深色正文、淡紫标签、16dp外边距和10dp细边圆角。正文/源码只读切换，外围保留复制链接、听文章和查看评论。大字体/320dp允许外围滚动，操作48dp可点；元数据变化不得重挂载活跃正文。图片失败保留已加载文字并提供重新加载。暂停界面不显示旧正文，显式重新加载后重新检查分享。

路由依据PublicShareDetail的真实kind、format与blogType。blog+markdown+article必须用既有Go CM6/Cherry只读WebView；明确note仍用普通笔记的原生Markdown。旧服务未提供blogType时采用“分享阅读 · 兼容”的只读WebView，不伪造文章/笔记分类或资源ID。书籍、章节与HTML保持各自类型化路径。保留现有公开文本4MiB上限，超限报错，不截断或把Markdown冒充HTML。

复用typed Markdown传输与不透明预览，而非创建另一个编辑器或把大文本拼进HTML脚本。增加独立public Markdown用途：只接收Markdown和readOnly=true，匿名会话从HtmlBrowserSession的公共队列取得，绝不接收账户客户端、Cookie、密码或令牌。普通local complex editor的权限保持原用途。资源沿用PublicHtmlResources：配置服务器static/upload-files路径与部署前缀、GET、不带凭据、不跟随重定向、5MiB单资源/20MiB总量/32条和取消期限；根别名也映射回部署前缀。内置Go引擎继续从应用资产加载。

主宿主只运行已打包的可信引擎；Markdown/原始HTML呈现在sandbox=allow-scripts的不透明子frame，拿不到父级Native桥或账户。只读源码不能输入或保存。公开资源的base/CSP和Native拦截由用途及配置服务器共同约束；不开放任意源、API、file/content、表单、下载或权限。链接只提出Flutter确认，先退休精确当前租约再外部交接。资源/链接/ready回调须绑定租约、代际与当前分享，晚到结果不得污染新页面。

密码仍由原生表单调用既有分享解锁接口，掩码、错误/取消状态按原型。密码不交给WebView，不放URL，不落盘；解锁正文仅在当前阅读内存中，标注“已解锁”。分享替换、退出、后台或外链先关闭运行时及待处理资源；返回只显示暂停。重新加载必须重新请求分享元数据，已撤销或新锁定不能重开旧正文；加载/失败时清除旧正文和元数据。公开阅读不创建本机编辑草稿，不修改SQLite。

验证：类型分流、旧字段缺失、锁定/解锁/取消、过期响应、后台后fresh-read、外链close-before-launch、普通笔记回归；真实Go浏览器只读/源码/Unicode-BOM-CRLF/资源前缀/恶意内容与桥隔离；用途边界、撤销及资源取消。冻结源码后仅ARM64构建，在NAS redroid用真实Go隔离服务检查公开/密码文章、资源、Cookie及API拒绝、锁屏/返回、撤销和原数据精确恢复。所有45组仍未完成；本地附件/保护与44激活、45等继续。

## V5 r2：公式初始化屏障
界面继续采用既有原型。公开预览加载 APK 内 MathJax 后，还必须等待 startup.promise 完成，再让既有 Cherry 初始化。仅脚本 load 事件不足以保证引擎就绪；慢初始化会使首轮公式被渲染为普通文字且不再恢复。新增真实浏览器慢启动场景（700 ms），旧冻结 r1 子脚本复现 SVG 超时，修复后通过。源码与正文快照保持原样，普通本地文章继续沿用原路径。Android 须使用新冻结 APK 再验证，r1 Native 失败记录保留。

## V5 r3：隔离内的外链意图
外链保持预览文档与既有 frame/connect/form CSP。可信子脚本只处理真实 click（含键盘激活），阻止 iframe 自行导航，向当前父级发送带 nonce/epoch 的链接意图。父级校验当前不透明 frame 与 URL 后，经已有主宿主 Native 桥转交。Native 再查询可信主窗口 navigator.userActivation.isActive，校验活跃公共租约和 HTTP(S) URI；查询有3秒期限与序列号，退休或晚到结果丢弃。随后由既有 Flutter 确认框决定是否打开；确认后先关闭精确租约，再调用系统浏览器。
程序点击不产生意图，伪造 Native 意图且没有用户激活时不得弹框。真实浏览器覆盖鼠标、键盘、合成点击拒绝及文档不导航；Android 再覆盖无激活伪造拒绝、实际触摸取消/确认和快速返回。旧 r2 真实点击出现 ERR_BLOCKED_BY_CSP 的失败证据保留，不能通过放开 iframe 网络导航规避。
