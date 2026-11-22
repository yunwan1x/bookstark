# 15 书签列表、筛选与批量操作（实施前设计）

参考15-bookmarks.png、15-bookmark-editor.png。列表：白色标题栏返回/书签/批量选择；关键词搜索；我的/公开原生分段控件；标签和筛选；真实总数；书签卡片含标题、站点、说明、标签、公开/导航/置顶状态、操作菜单；圆形新建按钮。仅设计示例使用文档站点，不是推荐或生产数据。复用Slate主题、8dp圆角、48dp触控、共享标签选择器、HTTP客户端、附件图片和现有错误/确认交互。

中文/英文，小屏320dp和200%字体/键盘可滚动。卡片打开HTTP(S)网址前明确确认并调用系统浏览器，不传Bookstark登录Cookie。其他人的公开书签可阅读；编辑/删除等按真实owner或admin权限，不能仅因公开或已登录就显示可写。用户role取/api/profile.role，不猜member_id=1。加载错误与空列表区分；分页使用服务total/page/page_size，查询generation隔离旧结果，操作后刷新所有已加载页，失败保留选择项。

接口GET /api/bookmarks（scope=mine/public、keyword、重复label参数AND、labels_or CSV、is_public/is_pinned/nav_visible三态、no_label、site、start_time/end_time/time_field、page）。列表返回完整BookmarkWithLabels；labels数组为真实标签，不从label CSV反推。GET /api/bookmark-labels(-with-count)?scope=...。公开scope强制仅公开数据并带账号，不能将公开列表误作为“我的”。

创建POST /api/bookmarks字段title/url/description/favicon/is_public/labels。标题500、URL2048、说明2000，均为UTF-8字节，保留既有名称空白和URL。URL须HTTP(S)、真实host且不含账号，拒绝javascript/data/控制字符。新建默认为私密，不凭空开启导航显示；导航显示通过独立PATCH设置。

进一步核对模型：书签专有batch-add-labels的tags数组逐个精确绑定名称，支持含逗号和首尾空格的已有标签（与通用CSV接口不同）。书签保存对这类标签使用明确的两阶段替代：主保存labels空字符串清空关系，然后按≤50个精确名称分批绑定并GET实际数组核对。任何部分失败保留真实ID和完整草稿，明确提示标签待恢复，不重复POST或静默拆分/改名；安全CSV名称仍走原专用替换接口。上文通用“拒绝旧逗号标签”规则对书签以此精确数组支持修订，笔记/书籍的保护仍保留。实际Go集成必须覆盖逗号标签，不能只凭模型阅读宣布可用。

关键兼容行为：POST按当前用户+完全相同URL更新已有书签，而非总是新建。保存前用scope=mine列表关键字查询并按完全相同URL核对，发现已有记录需明确打开已有/确认更新，保留实际ID和用户未确认的标志；不能盲POST把已有书签隐私/标签覆盖。/api/bookmarks/check/会自动抓取网页，不能当无副作用查重接口。网络异常重试须保留已知ID；完全原子“仅新建”仍受旧服务upsert能力限制，实测与说明不可省略。

PUT /api/bookmarks/:id可改title/url/description/is_public/labels，不编辑内部排序/置顶/导航字段；URL无变化时省略url，避免Go把原favicon清空。标签预先走共享安全CSV编码（含逗号的单个旧标签不先写其他字段），再专用PUT /api/labels/resource/bookmark/:id并回读核对，失败保留实际ID。公共/导航用PATCH /public {is_public}、/nav-visible {nav_visible}；单条/pin为管理员且是非幂等toggle，失败后先回读，不盲目重试。

批量模式明确显示选择范围与数量，初版只对真实选择ID操作，不能用全过滤器扩张范围。API支持batch-delete/share/unshare/add-labels/remove-labels/pin/unpin/show-nav/hide-nav，{ids:[...]}最多200条；批量标签字段按实际控制器核对。所有ID服务器再次校验owner/admin；需要明确区分单条pin管理员限制与旧批量pin的owner权限差异，按原界面/实际权限验收，不能通过替代接口规避限制。公开/删除均确认具体选择。删除前回收站快照与事务由真实模型核对，不承诺未保证的撤销。

排序PATCH /api/bookmarks/sort {items:[{id,order_sort}]}最多200，自己scope才能调序；不能仅重排已加载页就覆盖所有未加载条目的排序。高级筛选包括AND/OR标签、公开/置顶/导航、无标签、站点、创建/修改日期。旧site查询只匹配http(s)://站点/%，无斜线的根URL可能漏掉；须明确回归/兼容限制，不用伪造总数掩盖。OR CSV同样不能无损表示逗号旧标签。

本地SQLite需新增书签表并保留v1—v6数据，标签用JSON无损存储、URL查重策略与服务语义一致，事务回收站快照、分页/筛选/排序可重开。公开网络广场在本地空间按真实联网适配能力处理，不用假公开数据。实际旧Android导入仍是44项。

回归：真实Go与本地CRUD/查重/upsert提示、URL不变不丢图标、标签清空/旧名/部分ID、metadata输入竞态、owner/公开只读/admin权限、批量200与全选边界/失败保留、分页错位和旧查询、筛选日期/站点根URL、调序不覆盖未加载项、320dp中英/200%字体/键盘、原型截图和真机。当前仅设计，尚未实现15。

实施记录：2026-11-04已实现原生列表/编辑、远端/本地仓库、SQLite7升级、批量操作、草稿、metadata竞态保护和真实Go回归。159项完整测试、9组浏览器及ARM64APK构建通过，见validation/2026-11-04-bookmarks-validation.md。仍保留实现中；原型精细差异、真实Android、favicon呈现、认证URL兼容和全过滤器批量范围未完成，不按完整页验收。
