<!-- /autoplan restore point: new plan file created for topic module design -->

# 专题模块设计方案

Captured: 2026-06-16T02:00:14Z \| Branch: master \| Commit: ecaf02e

## Plan Summary

专题模块用于把现有笔记、文章、书籍文档、书签、任务、图片/文件和外部链接组织成一个可推进的问题空间。它不是新的内容孤岛，而是 BookStark 现有内容之上的组织层：一个专题回答一个问题，资料沉淀证据，结论沉淀判断，行动项推动后续执行。

旧专题实现曾经提供 `专题 = 问题 + 资料 + 结论`，但后来被移除。新方案保留这个产品核心，删除孤立实现思路，改为复用当前系统已经成熟的全局搜索、分享、回收站、移动端弹窗、分页、多语言和现有测试模式。

## What Already Exists

| 能力 | 当前位置 | 新专题如何复用 |
|------------------------|------------------------|------------------------|
| 认证与权限 | `middleware.AuthRequired`, `middleware.GetMemberID`, `checkOwnership` | 所有专题 API 必须按 `member_id` 隔离，管理员可查看但默认仍以个人内容为主 |
| 书籍和文档树 | `models.Book`, `models.Document`, `/api/books/:id/docs/tree` | 专题资料可引用 `document`，打开时跳到 `/books/:identify/edit?doc=<id>` 或文档定位参数 |
| 笔记/文章 | `md_blogs`, `controllers/blog.go`, `templates/notes.html` | 资料可引用 `note` / `article`，保留标题、摘录和当前可见性 |
| 书签 | `models.Bookmark`, `QueryBookmarks`, `static/js/bookmarks.js` | 资料可引用 `bookmark`，使用 favicon/URL/description 做证据卡 |
| 待办 | `models/action.go`, `/api/tasks` | 专题可挂行动项，既能显示也能跳转到 Notes 的 tasks tab |
| 搜索 | `models.GlobalSearch`, `/api/search` | 搜索结果新增 topics，专题详情搜索资料标题、摘录、结论 |
| 分享 | `md_shares`, `PublishShare` | 第二阶段支持分享专题，只读查看专题问题、资料和结论 |
| 回收站 | `models.TrashSnapshot`, `CreateTrash`, `RestoreFromTrash` | 删除专题进入回收站，恢复专题和资料 |
| UI 基础组件 | `components.css`, `bs-dialog.js`, `pagination.js`, `asset-modal` | 专题页面只新增业务布局，不重新造按钮、弹窗、分页、toast |
| 多语言 | `i18n/zh.go`, `i18n/en.go`, `window.__()` | 所有新增文案必须中英文同步 |

## NOT In Scope

| 暂不做 | 原因 |
|------------------------------------|------------------------------------|
| 实时协作编辑 | 当前系统没有协作基础设施，专题先保持个人知识管理模型 |
| AI 自动生成专题图谱 | AI 能力已有，但专题 MVP 应先把手工组织闭环跑通 |
| 独立全文索引引擎 | 当前 SQLite LIKE 搜索已覆盖系统，先接入 `GlobalSearch` |
| 公开专题评论 | 分享系统没有评论模型，引入会扩大权限和审核复杂度 |
| 文件二进制复制进专题 | 文件/图片保持引用和快照摘要，避免重复存储 |

## Product Definition

### 核心对象

专题回答四个问题：

1.  我正在研究/推进什么？
2.  哪些现有内容能支撑这个判断？
3.  现在的阶段性结论是什么？
4.  下一步要做什么？

### 用户心智

专题不是文件夹。文件夹按存放位置组织，专题按问题组织。同一篇文章、同一个书签、同一条笔记可以出现在多个专题里。

### 主要场景

| 场景 | 用户动作 | 系统响应 |
|------------------------|------------------------|------------------------|
| 研究一个问题 | 创建专题，写核心问题 | 出现资料区、结论区、行动区 |
| 收集证据 | 从搜索结果/笔记/书签/文章加入专题 | 保留引用和摘录，专题时间更新 |
| 沉淀结论 | 在结论编辑区写判断 | 结论进入搜索，列表显示“已结论”状态 |
| 推进行动 | 从专题生成/关联待办 | 待办仍归 `md_tasks`，专题只保存关联 |
| 回看专题 | 按标签、状态、关键词筛选 | 列表按置顶、更新时间排序 |

## Data Model

### `md_topics`

``` sql
CREATE TABLE IF NOT EXISTS md_topics (
  topic_id INTEGER PRIMARY KEY AUTOINCREMENT,
  title VARCHAR(200) NOT NULL DEFAULT '',
  question TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  conclusion TEXT NOT NULL DEFAULT '',
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  member_id INTEGER NOT NULL DEFAULT 0,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  create_time DATETIME NOT NULL,
  modify_time DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_topics_member ON md_topics(member_id);
CREATE INDEX IF NOT EXISTS idx_topics_member_status ON md_topics(member_id, status);
CREATE INDEX IF NOT EXISTS idx_topics_modify ON md_topics(modify_time);
```

Status values:

| status     | 含义                         |
|------------|------------------------------|
| `active`   | 正在推进                     |
| `paused`   | 暂停，不在默认活跃列表里强调 |
| `resolved` | 已形成结论                   |
| `archived` | 归档，仍可搜索               |

### `md_topic_items`

``` sql
CREATE TABLE IF NOT EXISTS md_topic_items (
  item_id INTEGER PRIMARY KEY AUTOINCREMENT,
  topic_id INTEGER NOT NULL DEFAULT 0,
  resource_type VARCHAR(24) NOT NULL DEFAULT '',
  resource_id INTEGER NOT NULL DEFAULT 0,
  title VARCHAR(500) NOT NULL DEFAULT '',
  url VARCHAR(1000) NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  excerpt TEXT NOT NULL DEFAULT '',
  order_sort INTEGER NOT NULL DEFAULT 0,
  create_time DATETIME NOT NULL,
  modify_time DATETIME NOT NULL,
  UNIQUE(topic_id, resource_type, resource_id)
);

CREATE INDEX IF NOT EXISTS idx_topic_items_topic ON md_topic_items(topic_id, order_sort, item_id);
CREATE INDEX IF NOT EXISTS idx_topic_items_resource ON md_topic_items(resource_type, resource_id);
```

Supported resource types:

| type | resource_id | title/url/excerpt 行为 |
|----------------------|----------------------------:|----------------------|
| `text` | 0 | 用户手写摘录或证据 |
| `link` | 0 | 外部链接，保存 URL、标题、说明 |
| `document` | `md_documents.document_id` | 引用书籍文档，保存标题快照 |
| `note` | `md_blogs.blog_id` where `blog_type='note'` | 引用笔记 |
| `article` | `md_blogs.blog_id` where `blog_type='article'` | 引用文章 |
| `bookmark` | `md_bookmark.bookmark_id` | 引用书签 |
| `task` | `md_tasks.task_id` | 引用行动项 |
| `upload` | `md_uploads.upload_id` | 引用图片/上传文件 |

### 为什么不是旧的 `md_topic_materials`

新命名用 `items`，因为它不只是“资料”。专题里会有证据、引用、行动、附件和手写摘录。`resource_type/resource_id` 统一跨模块引用，`title/url/note/excerpt` 是快照字段，用于被引用资源删除、改名或外部链接无效时仍能保留上下文。

## Backend API

### Pages

| Method | Path      | Handler                  |
|--------|-----------|--------------------------|
| GET    | `/topics` | `controllers.TopicsPage` |

### Topic APIs

| Method | Path | 用途 |
|------------------------|------------------------|------------------------|
| GET | `/api/topics` | 列表，支持 `keyword/status/date/page/page_size` |
| POST | `/api/topics` | 创建专题 |
| GET | `/api/topics/:id` | 获取详情，含 items、stats |
| PUT | `/api/topics/:id` | 更新 title/question/summary/conclusion/status/is_pinned |
| DELETE | `/api/topics/:id` | 删除到回收站 |
| PATCH | `/api/topics/:id/pin` | 置顶/取消置顶 |
| GET | `/api/topics/daily-counts` | 日历热力统计 |

### Topic Item APIs

| Method | Path                                | 用途                       |
|--------|-------------------------------------|----------------------------|
| POST   | `/api/topics/:id/items`             | 添加资料/引用/行动项       |
| PUT    | `/api/topics/:id/items/:itemId`     | 更新标题、说明、摘录、排序 |
| DELETE | `/api/topics/:id/items/:itemId`     | 移除关联，不删除原资源     |
| PATCH  | `/api/topics/:id/items/sort`        | 拖拽排序                   |
| POST   | `/api/topics/:id/items/from-search` | 从全局搜索结果加入专题     |

### Controller Rules

1.  所有 `:id` 先 `ParseID`，再读取 topic，最后 `checkOwnership`。
2.  `text/link` 的 `resource_id` 必须为 0。
3.  引用型 item 必须验证资源存在且当前用户可访问。
4.  添加重复资源返回 409，前端提示“已在专题中”。
5.  删除 item 只删除 `md_topic_items` 行，不删除原笔记/书签/文章。
6.  删除 topic 使用事务，快照 topic、items、shares。
7.  更新 topic 或 item 后 `touchTopic(topicID)`。

## Frontend UX

### Navigation

1.  知识菜单新增 `专题`，图标使用 `fa-diagram-project` 或 `fa-folder-tree`。
2.  顶部新建菜单新增 `新建专题`。
3.  Profile 默认首页可在第二阶段增加 `topics` 选项，不阻塞 MVP。

### `/topics` Layout

Desktop:

``` text
┌──────────────────────────────────────────────────────────────┐
│ sticky toolbar: [搜索专题] [状态 chips] [标签筛选] [+]       │
├─────────────── list pane ───────────────┬──── detail pane ───┤
│ 专题卡：标题/问题/标签/资料数/结论状态 │ 标题 + 状态 + 操作 │
│ 专题卡                                │ 问题编辑           │
│ 专题卡                               │ 资料列表           │
│ 分页                                  │ 结论编辑           │
│                                       │ 行动项             │
└───────────────────────────────────────┴─────────────────────┘
```

Mobile:

1.  默认显示专题列表。
2.  点击专题进入详情视图，顶部有返回按钮。
3.  新建按钮用移动 FAB，复用书籍页移动策略。
4.  添加资料、编辑专题使用 `asset-modal` + `data-mobile-sheet`。

### List Card

每个专题卡显示：

1.  标题，14px/600，复用 `.list-row-title`。
2.  核心问题，两行截断。
3.  标签 badge，复用 `.tag-badge`。
4.  资料数、行动数、更新时间。
5.  状态 badge：进行中/暂停/已结论/归档。
6.  操作按钮：置顶、分享（二阶段）、删除。

### Detail Pane

Detail pane 分四区：

| 区块       | 控件                                               |
|------------|----------------------------------------------------|
| Header     | 标题输入、状态 segmented control、置顶、保存、删除 |
| Question   | textarea，回答“这个专题要解决什么问题？”           |
| Items      | 卡片列表，支持类型筛选、添加、编辑摘录、移除、排序 |
| Conclusion | Markdown textarea + 预览按钮，保存结论             |
| Actions    | 关联任务列表，支持创建待办或关联已有待办           |

### Add Item Modal

Tabs:

1.  `搜索已有内容`：调用 `/api/search?q=`，结果按文档/文章/笔记/书签/任务分组。
2.  `添加链接`：URL、标题、说明、摘录。
3.  `手写摘录`：标题、说明、摘录。

这比旧实现直接让用户选类型更顺手，因为大多数资料来自系统已有内容。

## Search Integration

`models.SearchResult` 增加：

``` go
Topics []TopicHit `json:"topics"`
```

`TopicHit` 字段：

``` go
type TopicHit struct {
    TopicID int64 `json:"id"`
    Title string `json:"title"`
    Question string `json:"question"`
    Snippet string `json:"snippet"`
    Status string `json:"status"`
    ItemCount int `json:"item_count"`
}
```

`GlobalSearch` 增加第 7 个 goroutine，搜索：

1.  `md_topics.title`
2.  `md_topics.question`
3.  `md_topics.summary`
4.  `md_topics.conclusion`
5.  `md_topic_items.title/note/excerpt/url`

Encrypted article content仍按现有逻辑跳过正文搜索。专题引用加密文章时只搜索专题 item 的手写标题/摘录，不读取加密正文。

## Share Integration

MVP 不阻塞分享，但数据模型应兼容：

1.  `md_shares.share_type` 当前 `VARCHAR(10)`，`topic` 长度可用。
2.  `/api/shares` 第二阶段支持 `share_type='topic'`。
3.  分享页只读展示标题、问题、资料、结论。
4.  被引用私有内容只显示专题 item 快照，不直接暴露原资源正文。

## Trash Integration

`TrashSnapshot` 增加：

``` go
Topic *TopicSnap `json:"topic,omitempty"`
TopicItems []TopicItemSnap `json:"topic_items,omitempty"`
```

删除策略：

1.  删除专题进入回收站。
2.  保留 item、label relation、share 快照。
3.  恢复时如果原 `topic_id` 冲突，插入新 ID，并重建 item 的 `topic_id`。
4.  恢复不恢复被引用资源本体，只恢复关联快照。

## Error & Rescue Registry

| 场景 | 用户看到 | 系统处理 |
|------------------------|------------------------|------------------------|
| 添加不存在资源 | “资源不存在或无权访问” | 返回 404/403，不创建 item |
| 重复添加同一资源 | “已在专题中” | 返回 409，前端可定位已有卡片 |
| 原资源被删除 | 专题卡显示“原资源已删除”，仍显示快照 | 详情 API 带 `resource_missing=true` |
| 外部链接不合法 | “链接格式不正确” | 前端校验 + 后端 `url.Parse` |
| 专题名称为空 | “请输入专题名称” | 400 |
| 移动端弹窗滚动穿透 | 用户无法稳定编辑 | 复用 `BookStarkScrollLock` 和 `data-mobile-sheet` |
| 搜索关键词过长 | 自动截断到 100 字符 | 沿用 SearchAPI 行为 |
| 删除专题误操作 | 可在回收站恢复 | 事务快照 |

## Failure Modes Registry

| 风险 | 严重度 | 预防 |
|------------------------|------------------------|------------------------|
| 专题再次变成孤立大模块 | High | 复用搜索、分享、回收站，不创建平行体系 |
| 引用资源权限泄漏 | Critical | item detail enrich 阶段逐类型校验 member_id/ownership |
| 搜索性能退化 | Medium | topic 搜索 LIMIT 20，索引 member/status/modify，后续再考虑 FTS |
| 删除恢复不完整 | High | trash snapshot 覆盖 topic/items/shares，模型测试恢复 |
| 移动端详情页信息过密 | Medium | mobile 列表/详情双视图，drawer 承载筛选 |
| 多语言遗漏 | Medium | zh/en 同步新增 key，UI 测试至少检查中文页面无裸 key |

## Architecture

``` text
Browser /topics
  │
  ├─ templates/topics.html
  │    ├─ static/css/topics.css
  │    └─ static/js/topics.js
  │         ├─ csrfFetch / BSDialog / renderPagination / escHtml
  │         └─ /api/search for add-from-existing
  │
  └─ routers/router.go
       ├─ controllers.TopicsPage
       ├─ controllers.ListTopicsAPI
       ├─ controllers.GetTopicAPI
       ├─ controllers.Create/Update/DeleteTopicAPI
       └─ controllers.Create/Update/DeleteTopicItemAPI
            │
            └─ models/topic.go
                 ├─ md_topics
                 ├─ md_topic_items
                 ├─ md_shares(share_type='topic', phase 2)
                 └─ md_trash snapshot
```

## Implementation Plan

### Phase A: Backend Core

1.  Add topic schema in `models/db.go`.
2.  Add `models/topic.go` with list/detail/create/update/delete/touch/item CRUD.
3.  Add `controllers/topic.go`.
4.  Register routes in `routers/router.go`.
5.  Add i18n keys in `i18n/zh.go` and `i18n/en.go`.
6.  Add model/controller tests for validation, ownership, duplicate item, delete/restore.

### Phase B: UI Workbench

1.  Add `templates/topics.html`.
2.  Add `static/css/topics.css` using CSS variables and shared components.
3.  Add `static/js/topics.js` using existing `csrfFetch`, `BSDialog`, `renderPagination`, `escHtml`.
4.  Add knowledge nav and create menu entries in `templates/base.html`.
5.  Add mobile list/detail behavior and mobile sheet modals.

### Phase C: Integration

1.  Add topics to `models.GlobalSearch` and `templates/search.html` rendering.
2.  Add topic trash snapshot and restore.
3.  Add optional share support.
4.  Add command palette entries if current command palette supports static registry.

## Test Plan

### Go Tests

| Area | Tests |
|------------------------------------|------------------------------------|
| Model CRUD | create/list/get/update/delete topic |
| Item CRUD | add text/link/document/note/article/bookmark/task/upload |
| Ownership | user cannot read/update/delete another user's topic or resource |
| Duplicate resource | duplicate `(topic_id, resource_type, resource_id)` returns conflict |
| Search | topic title/question/conclusion/item excerpt returned by `GlobalSearch` |
| Trash | delete topic creates snapshot, restore rebuilds topic and items |

### UI Tests

| Test file | Coverage |
|------------------------------------|------------------------------------|
| `topics_ui_test.go` | desktop list/detail/create/update/delete |
| `topics_mobile_ui_test.go` | mobile list/detail navigation, FAB, bottom sheet |
| `topics_add_item_ui_test.go` | add from search, link, text excerpt |
| `topics_search_ui_test.go` | global search shows topic results |

Run command per project rule:

``` bash
./build.py
go test ./...
```

## CEO Review

### Premise Challenge

| Premise | Verdict | Reason |
|------------------------|------------------------|------------------------|
| Users need a module beyond tags and search | Accepted | Tags classify, search finds, but neither preserves a question→evidence→conclusion workflow |
| Topic should reuse existing content | Accepted | Current system already has books/docs/notes/articles/bookmarks/tasks; duplication would create stale content |
| Old topic module can be restored | Rejected | It was deleted and would reintroduce isolated UI/API/schema patterns |
| Sharing can wait | Accepted | Private organization must work first; share adds permissions complexity |

### Dream State Delta

``` text
CURRENT
  内容分散在笔记、文章、书籍、书签、待办；靠标签和搜索回忆上下文

THIS PLAN
  专题把已有内容串成问题、证据、结论、行动；仍复用原内容系统

12-MONTH IDEAL
  专题可自动推荐相关内容、生成研究地图、支持公开专题页和 AI 复盘
```

### Alternatives

| Approach         | Effort | Risk                   | Decision |
|------------------|-------:|------------------------|----------|
| 只用标签模拟专题 |    Low | 无法沉淀问题/结论/行动 | Reject   |
| 恢复旧专题模块   | Medium | 再次成为孤岛，维护面大 | Reject   |
| 新建轻量组织层   | Medium | 需要做好引用权限       | Accept   |

## Design Review

### Scope Score: 8/10

设计覆盖列表、详情、添加资料、移动端、空/错误/加载状态。需要在实现时补齐视觉细节截图验证。

### 7 Dimensions

| Dimension  | Score | Notes                                                 |
|------------|------:|-------------------------------------------------------|
| 信息层级   |     9 | 列表看进度，详情看问题/资料/结论/行动                 |
| 交互状态   |     8 | 已定义 loading/empty/error/duplicate/missing resource |
| 响应式     |     8 | mobile 双视图 + sheet，需实现后截图验证               |
| 可访问性   |     8 | label/aria/focus-visible 继承现有规则                 |
| 视觉一致性 |     9 | 复用 list-row/tag-badge/asset-modal                   |
| 内容密度   |     8 | 工作台式布局，避免营销页                              |
| 多语言     |     7 | 方案要求 zh/en，但具体 key 需实现补齐                 |

## Engineering Review

### Architecture Soundness

明确新增边界：`models/topic.go` 是唯一业务模型，`controllers/topic.go` 是唯一专题控制器，`topics.js/css/html` 是唯一页面面。跨模块能力通过现有 API 或模型函数读取，不把其他资源复制到专题。

### Coupling

Topic item enrichment 会引用多类资源，是主要复杂点。实现时建议用显式 switch：

``` go
switch item.ResourceType {
case "document":
    enrichDocumentItem(...)
case "note", "article":
    enrichBlogItem(...)
case "bookmark":
    enrichBookmarkItem(...)
case "task":
    enrichTaskItem(...)
}
```

不要抽象成通用 ResourceProvider 注册表，当前代码库没有这个模式。

### Performance

列表页不要 N+1 查询 labels/items。`ListTopics` 应用聚合子查询拿 `item_count/action_count/has_conclusion`，详情页再加载 items。资源 enrich 可以按类型批量查询。

### Security

1.  所有引用资源都要 ownership 校验。
2.  外部 URL 只保存，不服务端抓取，避免 SSRF。
3.  分享专题时不可泄漏私有原资源正文，只显示专题快照字段。
4.  加密文章正文不进入专题搜索。

## DX Review

### Developer Journey

| Stage      | Target                                               |
|------------|------------------------------------------------------|
| 找入口     | `routes/router.go` 能看到 `/topics` 和 `/api/topics` |
| 理解模型   | `models/topic.go` 顶部定义 status/resource type 常量 |
| 加资源类型 | 新增常量、验证、enrich switch、测试                  |
| 跑测试     | `go test ./...` 和相关 UI test                       |
| 调试前端   | `/topics` 页面无构建链，直接改模板/JS/CSS            |

### TTHW

当前项目无前端构建链，新增专题页面的开发路径应保持 5 分钟内可启动：`./build.py` 后用 `admin:admin` 登录访问 `/topics`。

## Decision Audit Trail

| \# | Phase | Decision | Classification | Principle | Rationale | Rejected |
|-----------|-----------|-----------|-----------|-----------|-----------|-----------|
| 1 | CEO | 专题作为内容组织层，不作为新内容孤岛 | Mechanical | DRY | 最大化复用现有内容和标签/search/share/trash | 独立内容系统 |
| 2 | CEO | 保留问题+资料+结论核心 | Mechanical | Completeness | 这是旧实现中真正有价值的产品闭环 | 只做文件夹/标签 |
| 3 | Design | 桌面双栏工作台，移动双视图 | Mechanical | Explicit | 匹配当前 notes/books 管理界面和移动端模式 | 单页大表单 |
| 4 | Eng | 使用 `md_topics` + `md_topic_items` 两表 | Mechanical | Pragmatic | 覆盖 MVP，避免过早拆多表 | 资源/总结/行动多表 |
| 5 | Eng | item 使用 resource_type/resource_id + 快照字段 | Mechanical | Completeness | 同时支持引用和外部资料，删除后仍保留上下文 | 只保存 resource_id |
| 6 | Eng | 分享放二阶段，但 schema 兼容 | Taste | Bias toward action | MVP 优先个人闭环，分享会扩大权限验证 | 首版直接做公开专题 |
| 7 | DX | 不引入新前端框架或构建链 | Mechanical | Explicit | 当前系统是模板 + 原生 JS，保持调试成本低 | React/Vue 子应用 |

## Cross-Phase Themes

**Theme: 避免孤岛** — CEO、Design、Eng 都指向同一个结论：专题必须复用现有内容能力，否则会重复旧模块被移除的问题。

**Theme: 权限和快照是成败点** — Eng 和 DX 都指出跨资源引用会带来权限和删除后的可读性风险，必须在模型和测试里处理。

## Implementation Tasks

-   [ ] **T1 (P1, human: \~0.5 day / CC: \~20 min) — 数据模型** — Add topic schema and `models/topic.go` CRUD.
    -   Files: `models/db.go`, `models/topic.go`, `models/topic_test.go`
-   [ ] **T2 (P1, human: \~0.5 day / CC: \~20 min) — API** — Add topic and item controllers with ownership checks.
    -   Files: `controllers/topic.go`, `routers/router.go`, `controllers/topic_test.go`
-   [ ] **T3 (P1, human: \~1 day / CC: \~35 min) — UI** — Build `/topics` workbench with list/detail/add-item modals.
    -   Files: `templates/topics.html`, `static/js/topics.js`, `static/css/topics.css`
-   [ ] **T4 (P1, human: \~0.5 day / CC: \~15 min) — Navigation/i18n** — Add nav/create entries and zh/en keys.
    -   Files: `templates/base.html`, `i18n/zh.go`, `i18n/en.go`
-   [ ] **T5 (P2, human: \~0.5 day / CC: \~20 min) — Search** — Add topics to global search.
    -   Files: `models/search.go`, `controllers/search.go`, `templates/search.html`
-   [ ] **T6 (P2, human: \~0.5 day / CC: \~20 min) — Trash** — Snapshot and restore topics.
    -   Files: `models/trash.go`, `controllers/trash.go`
-   [ ] **T7 (P1, human: \~1 day / CC: \~30 min) — Tests** — Add model, controller, desktop UI, mobile UI tests.
    -   Files: `*_test.go`

## GSTACK REVIEW REPORT

Status: DONE_WITH_CONCERNS

Concerns:

1.  Dual external voices were unavailable in this environment, so this is a single-reviewer autoplan.
2.  The old module history strongly suggests scope creep risk. Keep first implementation to the two-table organization layer.
3.  Sharing should not ship until private topic CRUD/search/trash is stable.

Recommended next step: implement Phase A and Phase B together, then run `./build.py` and targeted UI tests before adding share support.
