# 29 · HTML 分享阅读：实施前设计

状态：原型和文档先行，未实现，不属于 ae7ba3a4/824 项本地交互检查点。全部45组目标不变。

原型：`../../prototypes/flutter-rewrite-2026-11-04/29-html-v6-public-reading.png`。使用 imagegen 技能、内置 image_gen 默认模式生成，原始文件 `/root/.codex/generated_images/01a1a01d-fa4f-7bb0-9828-fa0c61e29065/exec-59905413-da01-4dc5-986a-8e180375c846.png`；本地交付副本 `/vol1/1000/wy/output/bookstark-flutter/round3/design/29-html-v6-public-reading.png`，已发送图片。图中阅读实验仅为原型内容，不能注入生产资料。

## 入口和布局契约

沿用分享列表/分享链接、书籍目录和公开内容真实入口。公开 HTML 笔记/文章、独立文档、书籍内 HTML 章节分别核对服务器、分享标识和章节归属，不制造私有 owner ID。Flutter 负责页头、状态、模式、解锁、评论入口、外链确认和重试；正文才使用 HTML 渲染。

背景 #f1f5ff、主色 #3d5bd9、白色圆角卡片，16dp侧距、12dp卡片间距、至少48dp触摸区域。页头返回/“分享阅读”/刷新。已读状态显示真实标题、公开/密码标识、作者时间及 HTML 类型；不显示不存在的作者、时间、评论数。默认轻量模式不执行脚本。Android 明确选择交互模式后才运行作者脚本；其他平台不能显示失效的模式按钮。正文提供独立滚动，模式和系统导航保持 Flutter 控件。评论动作遵守原分享权限，不能按原型凭空启用。

密码未解锁：只显示公开元数据和锁定卡片，解锁框之外不能存在正文、标签、描述、图片或运行时。密码保留首尾空格、支持隐藏/显示、取消、错误重试；提交中防重复。密码和解密正文只留当前阅读会话，不写数据库、草稿、WebView参数中的认证字段或日志。刷新/离开清理已解锁正文；失败后不显示旧正文。

分享失效/刷新失败：立即退出旧运行时并隐藏旧标题、作者、正文、评论，显示“分享暂不可用”“链接可能已撤回，或暂时无法连接。”，提供重试/返回；不把网络失败认定为已经撤回，不保留可交互的旧 DOM。

320dp/200%文字允许标题/元数据换行和模式控件上下排列，解锁框/软键盘下可滚动，无横向溢出。加载、失败、取消、空 HTML 均需明确而不捏造正文。

## 已核对的现有协议与缺口

Go `prepareShareHTMLPayload` 对普通 HTML 分享清空 JSON content 并提供严格的 content_url；不能把空 content 当作空白 HTML。只接受已核对分享/章节的同服务器、无查询/片段 raw 路径。公开 GET `/api/shares/:identify/content/raw`；书籍章节 GET `/api/shares/:identify/docs/:docIdentify/content/raw`；密码 HTML 使用 POST `/api/shares/:identify/verify-password/raw`，成功是原始 HTML，可带 gzip，并非 JSON。Go 验证后解密及解压；密码正文上限 HTML 5MiB，应核对解压后 UTF-8 字节，拒绝重定向/异常媒体类型/超限/错误编码，支持截止时间与取消。保留原 Markdown 4MiB 协议，不粗暴放大所有公共 JSON。

现有 PublicShareDetail 与仓库只实现 Markdown 解锁，HTML rawAvailable 仅记录布尔值；ShareReaderPage 和 ShareChapterPage 仍是非 Markdown 占位。实施应新增独立格式能力与受限 raw 请求，不借用私有 blogs/docs API，不把 HTML 经 Markdown 显示。

交互浏览器必须与本地/认证预览共享单活跃租约，接入前退出旧实例，公开页面不继承账号 token/CSRF Cookie、localStorage、JS桥或私有文件权限。解析公开资源时同样限定实际来源与权限，不能将账号认证交给作者脚本；具体资源策略需在实现前补充并通过真实服务验证。不能把本地只读字节白名单直接伪称完整服务器资源支持。外链确认后先 await 关闭运行时再启动系统浏览器；后台/返回/刷新不能静默恢复脚本。来源切换后旧请求/回调不写新页面。

## 验证门槛

真实 Go 覆盖普通/密码 HTML、带服务器路径前缀、gzip/5MiB边界、密码首尾空格、章节越权和撤回。仓库/控件覆盖刷新竞态、取消、旧正文清除、模式切换和窄屏大字；NAS redroid 安装明确哈希的 ARM64 包验证 JS/CSS/图像、无障碍正文、服务器 Cookie 不泄漏、外链快速返回与后台关闭。冻结 source/APK/Web 分开归档；当前原型不代表功能或29全部完成。

## 最终生成提示词

Use case: ui-mockup. Create one high fidelity landscape UI prototype board for BookStark Flutter Android page29 v6 public HTML share reader, THREE large complete Android phones side by side. Chinese text crisp readable. White canvas outside phones; pale periwinkle #f1f5ff app background; white rounded cards; primary blue #3d5bd9; restrained Material icons. Real implementable mobile app UI, no marketing gradients. Title outside phones: '29 · HTML 分享阅读'. Phone1 public reading: app bar back arrow '分享阅读', refresh icon. Heading '我的阅读小实验', blue public chip '公开分享', author '林间 · 11月06日', small 'HTML' chip. Segmented controls '轻量预览' selected, '交互预览' unselected. A short info row '轻量模式不运行脚本'. Main rounded white HTML card with heading '今天的阅读', small flat book illustration, '阅读打卡', blue button '已读 0 次', progress bar labeled '阅读进度 60%'. Footer native button with comment icon '查看评论'. Phone2 password locked: same share-reader app bar, title '加密的阅读笔记', lock badge '需要密码', centered lock card '输入密码后阅读', full width primary '解锁阅读'. NO protected content or body behind the modal. Overlay rounded native dialog '解锁分享', helper '输入作者设置的密码', obscured password field with eye icon, secondary '取消', primary '解锁'. No real password text. Phone3 unavailable after refresh: same app bar '分享阅读', centered simple broken-link icon, heading '分享暂不可用', helper '链接可能已撤回，或暂时无法连接。', primary button '重试', secondary '返回'. No stale title, author, HTML, comments or old body shown on unavailable screen. Small captions beneath phones '公开 HTML', '密码解锁', '刷新后失效'. Consistent spacing, realistic touch targets, fully visible phones and bottom safe areas. Do not show editor controls, account credentials, code, implementation jargon, developer labels, watermarks, QR codes or extra screens. Keep the content sample clearly a reading-page example, not a claimed live user resource.

## 交互资源策略（实现前补充）

公开交互正文使用独立随机内存来源，不继承账号 Cookie 或私有附件。仅加载当前服务器及其配置路径前缀下的 `/static/` 和 `/upload-files/` 资源；不能把原型中的交互模式称为任意互联网浏览器。静态资源允许有界版本参数，上传文件不带查询；拒绝私有API、跨来源、路径穿越、用户信息、重定向、错误媒体类型。作者脚本可以操作当前DOM，但 connect-src 禁止任意API/fetch/WS/Beacon，表单、子框架、下载和权限请求关闭。外部链接只能经Flutter确认后启动系统浏览器，并先关闭预览。

资源通过原生请求拦截转给当前Flutter会话的独立无认证HTTP读取器，不传入账号客户端、token、Cookie、密码、私有文件路径或JS接口。资源按唯一URL缓存当前会话内存，串行有界读取，最多32项、单项5MiB、总20MiB，超时/退后台/离开/刷新取消；每个回调再次核对租约。原始HTML不改写，预览副本仅插入服务器base以正确解析相对资源，原生响应头强制CSP/no-store/nosniff/no-referrer。CSS/字体/JS/图像按媒体类型放行，不把HTML/JSON/错误页当作资源。局限与被阻止的资源需要有实际状态，不伪造加载成功。

此时底层19项与既有页面10项、HTML页面4项针对测试通过。真实Go已通过匿名压缩5MiB、BOM/Unicode/CRLF、密码首尾空格/错误密码、刷新重新锁定、撤回、HTML章节和跨书籍raw403。首次Go脚本误用不存在的树接口导致非JSON错误，清理后修正脚本通过；并非绕开正文上限。原文BOM保留修正还影响owner HTML读取，后续构建必须另归档，不能归入ae7旧APK。


根服务器检查点63f36567（573输入/854项/7组冻结浏览器）已实际验证公开/密码HTML的JS、CSS、SVG、按钮、无障碍节点、资源无Cookie/Authorization、作者脚本不能请求账号API、后台/外链快速返回、取消/空格错误密码/正确密码/刷新重新锁定、撤回404移除旧正文、退出冷启动和原14表/2文档/5附件保持。Native会话Cookie未强制落盘；私有认证通过真实浏览器请求证明，不要求CookieDB在写盘之前已有token。当前补充资源路径前缀：Go保存的根相对static/upload-files链接映射到所选服务器mount，别名与带前缀URL共用规范缓存，不发往主机根部其他服务；新增19项相关回归通过，后续855项构建另归档。保护内容解锁后标记已解锁。全部29/45组不据此完成。
