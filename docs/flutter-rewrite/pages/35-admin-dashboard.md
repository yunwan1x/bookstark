# 35 管理统计页：实施前原型与设计

2026-11-07，原型先于实现保存。图片：`docs/prototypes/flutter-rewrite-2026-11-04/35-admin-dashboard-v1.png`。这是示例原型，数字、账号和保留测试网段IP均不来自生产数据。本页尚未实现，尚无管理API或Android验收；不属于冻结中的HTML v10应用源码。

## 视觉及交互契约

基准390×844dp，白底深蓝正文、16dp边距、12dp圆角、细灰边框。顶部返回/访问统计/刷新，下方管理员·服务器空间。范围单行24小时/7天/30天/90天，选中项蓝底白字；窄屏或大字体改为Wrap，不缩小点击区。统计两卡总访问PV、每日UV累计并排，卡片淡蓝底可使用轻微竖向渐变；不足空间时纵排。数字来自真实返回，未加载不可先填0。

趋势卡标题、两条图例、日粒度折线与可读日期刻度，底部按日汇总。图表高200dp左右，使用可访问的文字摘要/逐日读值辅助；不能只靠颜色。时间范围只影响指标和趋势，不把最近访问列表伪装成范围筛选。原型的七日点数仅示例；实际缺失日期不补造UV，空趋势有明确空态。

最近访问使用纵排摘要卡，账号/游客与时间首行，IP第二行、路径第三行，长路径换行；每页20，上一页/页码/下一页。末页禁下一页，首页禁上一页；服务端返回页数为准。列表并非每次HTTP请求记录，不能命名为全部请求。手机整体纵向滚动，无底部导航，系统返回回到原入口。

刷新和范围请求按generation丢弃过时结果。统计/趋势/最近访问独立错误与重试；401/403显示会话/权限状态并可返回。中英320dp200%文字时所有按钮和分页仍可访问。只对server role0开放入口，local不调用管理API；服务器鉴权仍为最终依据。当前不外查IP，不持久化访问记录，不提供写操作。

实现后先严格协议/权限/部分失败/旧响应/widget测试，再真实隔离Go契约、浏览器与NAS redroid ARM64页面/返回/权限恢复回归。原型图截图对照独立记录，不用自生成golden宣称逐像素证明。

## 已核对的现有协议与实施清单

## 现有系统事实

- Go 页面为 GET /admin/dashboard，路由位于 routers/router.go 的 adminPages 组，统一经过 middleware.AdminRequired()。API 是 GET /api/admin/dashboard/stats、/trend、/logs，位于 /api/admin 管理组，同样要求管理员角色。非管理员 API 返回 403；非管理员页面重定向。权限以服务器鉴权为准，不能只依赖客户端隐藏入口。
- 已登录 profile 的 role == 0 是 Flutter 当前识别管理员的方式（main.dart 打开功能时读取 /api/profile）。本地空间没有服务器管理员身份，必须隐藏/禁用入口且不可调用这些 API。切换空间或退出后清除该页面及其响应数据。
- 看板是只读访问统计，不应提供任何管理写操作，也不应请求或缓存完整访问历史之外的其他管理资源。
- 通用成功响应为 {code: 0, data: ...}；分页列表额外返回 total, page, page_size, total_pages。错误返回 HTTP 状态及 {code, message}。Flutter 使用现有 BookstarkClient.get 同源认证请求；不要自行拼接主机地址或绕过 Cookie/CSRF 会话层。GET 不需 CSRF 写入流程。

## 已有数据契约

| 请求 | 查询参数 | 成功 data | 现有约束 |
|---|---|---|---|
| /api/admin/dashboard/stats | range=24h、7d、30d、90d，默认 7d | {total_visits:int64, unique_ips:int64} | 数据来自 md_visit_daily 的区间日汇总；unique_ips 是每天 UV 的相加，不是整个区间去重 IP 数。日期条件按 YYYY-MM-DD，所以 24h 也会包含起始日的整日累计，实际不是严格滚动 24 小时。|
| /api/admin/dashboard/trend | 同上 | [{time, page_views, unique_ips}] | Go 传 24h 时请求 hour bin，但底层表只有日粒度，当前 SQL 将日期格式化为当天 00:00，不能视为小时级趋势。其它范围为按日汇总。 |
| /api/admin/dashboard/logs | page，pageSize；模板请求每页 20 | {data:[{visit_id,ip,path,member_id,visit_time,account,ip_info_url}],total,page,page_size,total_pages} | model 将 page<1 归 1；pageSize 不在 1…100 时归 50。按 visit_time DESC。account 通过 LEFT JOIN 获取，匿名记录为空；匿名身份根据 member_id == 0 判定。ip_info_url 是服务器按 https://ipinfo.io/ + IP 拼成的外链。|

现有 parseTimeRange 对未知 range 回落到 7d（不会返回错误），因此客户端只发送上述允许值；如需严格范围错误，应另做 Go 协议改动和 Go API 测试，不在 Flutter 客户端猜测。

## Flutter 最小接入形态

新增 features/admin_dashboard/，建议分为只读 repository/model 与页面 widget：

- Repository 接收当前 BookstarkClient，封装 stats、trend、logs 三条 GET。将 code、JSON 字段类型、分页元数据做严格解析；畸形响应显示可重试错误，不要把解析失败转为 0 或空列表。
- 页面只在服务器空间进入。管理员入口由 profile role 0 控制；页面启动时仍调用同源 admin endpoint，处理 401/403（会话失效/权限已撤销），不得把本地缓存当成授权依据。返回普通首页/切空间时取消未完成请求或丢弃旧 generation 的响应，避免旧账号数据串屏。
- 可从管理员用户的首页快捷入口或个人/管理菜单进入。现有首页传入 onNavigate(route)，功能装配在 main.dart；新增 route 名称应只对 server profile role 0 暴露。普通用户不出现入口，本地空间不出现入口。不要在未确认入口承载区前增加整套管理员侧边栏。
- 三个区域共享一个范围选择器（24 小时、7 天、30 天、90 天）。变更范围只重新请求 stats 和 trend，不应重置 logs 分页；日志分页独立请求并呈现已有 total_pages。首次载入有骨架/进度，空数据明确显示“暂无访问记录/暂无趋势”，失败区域单独可重试，不能静默吞错。
- 窄屏优先纵向单列：范围选择器 → 两张统计卡片 → 趋势图（可横向压缩/保留可读标签）→ 最近访问分页列表。宽屏可将统计卡片并排；表格字段在手机端改成逐条卡片或可读两行布局，不能横向溢出。中文/英文与系统大字体都要测试。

## 页面文案草图（根据现有 i18n 语义）

- 标题：“访问统计” / “Dashboard”
- 时间范围：“时间范围” / “Time range”；选项“24小时、7天、30天、90天” / “24 hours, 7 days, 30 days, 90 days”
- 指标：“总访问” / “Total visits”；“独立 IP（每日 UV 累计）” / “Unique IPs (daily UV summed)”（现有模板写“独立 IP”，Flutter 应通过注释/信息提示讲清口径，除非 Go 端先改成真正区间去重）
- 图表：“访问趋势” / “Visit trend”；系列使用“访问量（PV）”与“独立 IP（日 UV）”。24h 不能标成“每小时”，应注明当前数据粒度为日；更理想的是等待 Go 提供真正小时聚合后再启用逐小时展示。
- 日志：“最近访问” / “Recent visits”；字段时间、路径、IP、用户；匿名显示“游客” / “Guest”。访问时间按本地时区格式化，但保留服务器时区语义并测试 ISO 时间解析，不截字符串取时间。
- 空态：“暂无访问记录” / “No visit records”；错误：“加载失败，重试” / “Load failed, retry”。刷新成功时间可以只显示本地刷新时间，不将它冒充服务器数据更新时间（当前接口未提供该字段）。

## 隐私与外链边界

访问日志含 IP、路径、账号和时间，按敏感管理数据处理：不写 debug log、不进 Crashlytics/analytics、不保存长期本地 cache、不把响应或 URL 放进页面路由参数。请求生命周期与当前登录空间绑定，切换/登出清空状态。

旧 Web 点击 IP 会打开 ipinfo.io。Flutter 第一版可以将 IP 作为纯文本，不提供外链；若产品要求外查，必须由用户显式点击，校验 ip_info_url 为 HTTPS 且 host 精确为 ipinfo.io、path 只含单个合法 IP，并用系统外部浏览器打开，不在认证 WebView 打开，不转发 BookStark Cookie。未经确认不自动访问第三方，也不把 IP 查询结果混入统计。

服务端目前向所有有权限页面管理员提供完整分页日志，没有脱敏、字段投影或权限细分。Flutter 不自行承诺更细粒度的访问控制；若需要管理员分级、账号/IP 脱敏或日志保留期限，应先加 Go 权限/脱敏/保留策略及对应测试。

## 协议改进建议（单独排期，避免 UI 虚构精度）

1. stats 增加明确时间边界和统计口径（period unique IP vs sum daily UV），支持严格滚动 24 小时，返回 range_start, range_end, bucket 等元数据。
2. trend 为 24h 提供真实小时桶；现有 md_visit_daily 无法恢复小时数。需新增小时数据存储/写入并考虑旧记录历史数据只能保持日粒度，或将界面限制为日粒度并明确标注。不能从日数据均摊伪造小时曲线。
3. logs 建议服务端固定/上限 pageSize（当前最大100，异常值默认50），允许按时间过滤；响应可提供 IP 隐私策略。Flutter 第一版仍使用已有简单分页，不新增查询筛选假象。
4. 补 Go 集成/API 测试覆盖非管理员 403、四种 range、未知 range 行为、分页上下界、空日志、字段序列化与时间口径。测试必须用隔离库/身份，不读写生产访问记录。

## 原型与验收回归清单（实施前）

- 第35组单页原型v1已先行保存；实施须按上方尺寸/状态契约适配中英文与窄屏。
- Flutter repository 单测：各三条 API 成功解码、null/类型错误、401/403、服务失败；连续切范围或空间切换时旧响应不覆盖新状态；分页边界与空列表。
- Widget：管理员入口仅 role 0 且仅 server space；普通账号和 local space 不出现/不可达；加载、部分失败、全空、重试、时间范围切换、分页、匿名/登录用户、长路径、较长账号、窄屏英文与大字体无溢出。
- 不做写库/写接口。通过 HTTP mock 证明只发 GET 到三条既有 API，无写请求；日志/IP 不进入持久化。
- 浏览器/设备：使用测试管理员和隔离访问记录；确认 403 可读恢复、切账号数据清空；真实 Go 权限契约通过。所有日志 fixture 和账号/IP 均为测试身份。

## 已读源文件

controllers/dashboard.go、models/visit_log.go、routers/router.go、middleware/auth.go、controllers/common.go、templates/admin_dashboard.html、i18n/en.go、i18n/zh.go、flutter_app/lib/main.dart、flutter_app/lib/core/api_client.dart、flutter_app/lib/features/home_page.dart、docs/flutter-rewrite/README.md。


## 访问日志语义补充

visit_log.go 的写入会对组合键 ip 与 member_id 做 upsert，更新 path 与 visit_time；因此日志分页并非每一次 HTTP 访问的逐条明细，而是每个 IP/成员组合最近一次访问的摘要。与 md_visit_daily.page_views 计数口径不同。UI 应沿用“最近访问”摘要定位，不能叫“全部请求记录”，也不能拿日志行数解释总访问。时间写入时使用服务器进程本地时区格式化；Flutter 应按实际 RFC3339/数据库序列化值解析并谨慎处理无偏移时间字符串，不应通过截取固定字符模拟时区转换。


2026-11-07源码接入：新增管理员访问统计页面、数据解析及分段加载控制器，通过真实Profile入口fresh profile核对member_id/role/session；仓库绑定打开时会话，换账号前后拒绝请求与迟到数据。整体分析和26项针对性测试通过。初次11处条件分支花括号规范问题已修复，实际仅4个新增/改动文件变化，未动HTML源码。完整候选构建、隔离Go合同重跑和redroid原型/权限/分页/失败回归尚未完成，35仍实现中。


V2原型还原修订设计（实施前约束）：保持原型35白底、页头标题下副标题、蓝色选中范围、390dp两张等高浅蓝统计卡；320dp/200%文字改满宽竖排而不缩字。PV/UV共用同一数值轴及易读刻度，图例蓝色/青色；服务端范围/每日UV累计说明保留在提示与按日汇总区。精确逐日数值读取折叠在“按日汇总”控制，展开后仍有日期选择及可访问数值。最近访问标题在列表边框外，行内账号粗体、时间紧凑靠右；窄屏大字可换行，保留完整可选路径/IP。只还原呈现，不改变真实20条分页、权限及请求回执语义。V1真实功能回归虽通过，因独立Y缩放及布局差异不验收；V2须截图对照、30项针对回归、完整构建与redroid复验。
