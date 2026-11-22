# 22 公开广场：实现前协议与原型

2026-11-04。UI原型22-public-feed.png已生成并归档，本页已开始原生页面与只读适配实现。状态实现中，不拿已有书签公开列表或笔记visibility开关当作整组完成。

白色AppBar返回/公开广场/刷新/更多；当前关键词搜索；文章/笔记/书籍/书签类型；实际公开标签横向chips；最新分享/最近更新；原生懒加载卡片；可滚动的真实上一页/下一页；新建资源FAB。浅Slate背景、16dp边距、蓝主色、48dp触控；卡片类型/标题/允许公开的摘要、作者、实际日期、标签。加密资源只保留允许展示的标题/作者/时间与需密码提示，不能把正文、描述或标签带到UI树/语义树。没有点赞/阅读数等后端不存在的社交数据。原型示例不进入运行时生产列表。

事实来源：controllers/public_feed.go、controllers/share.go、models/share.go、models/bookmark.go、templates/public_feed.html、routers/router.go。现有GET /api/shares支持page/keyword/type（article,note,book），没有处理label/sort，也没有书签类型分支；不能传入参数后假装服务端已执行筛选或排序。Web GET /shares 则实际处理type/sort/latest|updated/label/keyword/page，带完整公开标签目录、上一页/下一页与书签分支；PublicFeedLabels(kind)来自真实服务端。ListSharesPaged带PublicFeedOptions才有标签/更新时间行为，公开blog未建share时是负share_id，身份不能强制正整数或猜造新share记录；公开笔记/文章visibility=1也进入广场。

兼容方案：优先保持现有服务可用，研究使用同源有界GET /shares作为只读数据适配，将固定语义DOM转换为typed模型并完全用Flutter原生UI渲染，绝不执行HTML/JS、打开WebView、自动点击链接或提交表单。只接受明确结构/固定路径/已校验query，不信任任意href；正文按资源类型走现有JSON详情或受限摘要，DOM中的脚本不执行。若后续提供向后兼容JSON扩展，也必须对旧服务器有明确能力识别，不能默默降成假筛选。选择适配实现前需契约证明完整标签/排序/类型/加密/分页，无效结构明确报错不当空列表。只读GET可复用BookstarkClient的同源认证下载响应与取消/redirect拒绝，新增严格text/html/UTF8/字节上限；新解析依赖必须在21 APK检查点归档后引入。

HTML只呈现页码与真实prev/next，没有全量total DOM，不猜全量数量；API basic total也不能冒充带标签排序结果。书签公共行没有保证暴露bookmark_id，URL不能单独作为身份（不同所有者可收藏同一URL）；使用响应页与实际行位置构成只读不透明行身份，不能捏造数据库ID；管理入口只有实际管理信息存在并经过原生仓库权限核对才显示。私有API cookie不发送到外链favicon、图片或外部网址；外链点击明确系统打开。

书籍打开共享目录/章节、笔记复制/原生Markdown与评论、密码资源解锁均与24/25共用原生阅读/解锁组件，不把保护字段先渲染再隐藏。未知类型不能错误当Markdown执行，HTML/表格/绘图等阅读与29—34真实编辑器衔接。分享只复制实际canonical同源公开URL，无edit_token/密码/会话。广场是远程服务公共内容，本地空间不伪造公共服务；登录状态变化隔离代次、取消旧请求、保存过滤状态与滚动。

测试要求：HTTP映射/语义DOM结构变化报错/编码与恶意href/有界字节与取消；旧真实Go fixture四种类型、精确标签（含逗号&Unicode）、两种排序、搜索、页边界、负share_id、加密字段不可读；原生控件/旧请求竞态/错误与重试/导航与返回/中英320dp200%；原型逐项截图、真实Android回归。仅fixture可用不证明生产/迁移/真机完成。


2026-11-05 实现记录：新增 PublicFeedQuery.fromNavigation 固定路由/同源/重复参数检查，BookstarkClient.publicFeedHtml 同源固定GET、禁止redirect、4MiB有界读取、严格UTF8与媒体校验；html 0.15.7只做不可执行的语义DOM读取。RemotePublicFeedRepository核对表单实际筛选、类型/排序活动链接、全局分类和真实相邻分页，结构变化明确错误。笔记标题从固定脚本赋值边界间的JSON字面量读取，绝不eval；加密笔记无正文/标签进入模型，未公开标题时显示“加密内容”。管理按钮的真实ID只作元数据保留，本页尚未接管理写入。

PublicFeedPage首版已实现搜索、四种类型、实际标签、排序、原生卡片、分页和取消/代次隔离；ResourceCreatePage首版仅返回四选一类型，没有仓库或写入请求。14项模型/传输/适配/页面测试已通过，包含过期结果隔离和错误重试。尚未接主导航与真实资源阅读/创建协调器，不将fixture空回调当生产功能。首轮浏览器截图发现初始化滚动复位异常，已改为布局后回调并检查尺寸，复查中。真实Go契约正在补充，旧笔记标签接口不支持逗号（既有仓库明确拒绝），精确逗号标签仅用真实支持数组的书签接口造数据；可见范围必须走PATCH visibility而非被旧PUT忽略的字段。
