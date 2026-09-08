# BookStark 脏代码 & 未使用文件审计报告

> 审计日期：2026-04-29
> 审计范围：Go 后端、前端静态资源、模板、配置、文档
> 处理日期：2026-04-29（部分已清理，标注 ✅）

---

## 一、Go 后端死代码

### 1.1 未使用的导出函数

| # | 文件 | 行号 | 函数名 | 说明 |
|---|------|------|--------|------|
| 1 | `models/book.go` | 24 | `ListBooks` | 已被 `ListBooksPaged` 取代，无任何调用 | ✅ 已删除 |
| 2 | `models/blog.go` | 132 | `ListBlogs` | 已被 `ListBlogsPagedWithLabels` 取代，无任何调用 | ✅ 已删除 |
| 3 | `models/blog.go` | 298 | `ListBlogsByMemberWithLabels` | 已被 `ListBlogsPagedWithLabels` 取代，无任何调用 | ✅ 已删除 |
| 4 | `models/setting.go` | 56 | `GetAllSettings` | 已被 `GetAllSettingsDetailed` 取代，无任何调用 | ✅ 已删除 |
| 5 | `models/setting.go` | 98 | `UpsertSetting` | 已被 `BatchUpdateSettings` 取代，无任何调用 | ✅ 已删除 |
| 6 | `models/visit_log.go` | 192 | `PurgeOldVisitLogs` | 无任何调用方，从未接入定时任务或管理接口 | ✅ 已删除 |
| 7 | `models/bookmark.go` | 780 | `GetMaxBookmarkSort` | `Bookmark.Insert` 内联计算了 max sort，此函数已废弃 | ✅ 已删除 |
| 8 | `models/document.go` | 102 | `(d *Document) Update()` | 控制器使用 `UpdateDocumentContent`/`UpdateDocumentName`，此方法无调用 | ✅ 已删除 |
| 9 | `routers/router.go` | 350 | `renderPage` | 所有控制器直接用 `c.HTML()` + `commonData()`，此函数从未被调用 | ✅ 已删除 |

### 1.2 未使用的未导出函数

| # | 文件 | 行号 | 函数名 | 说明 |
|---|------|------|--------|------|
| 10 | `models/document.go` | 294 | `reorderSiblings` | 所有调用点直接用 `reorderSiblingsTx`，此包装函数无调用 | ✅ 已删除 |
| 11 | `models/label.go` | 603 | `getResourceIDColumn` | `CheckResourcesOwnership` 内联硬编码了同样的映射，此辅助函数未被使用 | ✅ 已删除 |

### 1.3 未注册的控制器函数

| # | 文件 | 行号 | 函数名 | 说明 |
|---|------|------|--------|------|
| 12 | `controllers/blog.go` | 16 | `BlogsPage` | `/blogs` 路由使用内联重定向，此函数永远不会被调用 | ✅ 已删除 |

### 1.4 未使用的导出常量

| # | 文件 | 行号 | 常量名 | 说明 |
|---|------|------|--------|------|
| 13 | `middleware/auth.go` | 24-26 | `StatusPending`, `StatusApproved`, `StatusRejected` | 控制器直接用数字字面量 `1`/`2` 比较，未使用这些命名常量 | ✅ 已删除 |

### 1.5 应降级为未导出的类型

| # | 文件 | 行号 | 类型名 | 说明 |
|---|------|------|--------|------|
| 14 | `conf/config.go` | 13 | `Config` | 仅在 `conf` 包内部使用，无需导出 | ✅ 已降级为 `config` |

### 1.6 控制器传入但模板未使用的变量

| # | 控制器 | 变量 | 说明 |
|---|--------|------|------|
| 15 | `controllers/book.go` `IndexPage` | `.Books` | 查了数据库传入模板，但 index.html 用 AJAX 加载数据，此变量被丢弃 |
| 16 | `controllers/bookmark.go` `NavPage` | `.MemberID` | 传入模板但 `nav.html` 从未引用 |
| 17 | `controllers/search.go` `SearchPage` | `.Keyword` | 传入模板但 `search.html` 从 URL 参数客户端获取 |
| 18 | `controllers/blog.go` `NotesPublicPage` | `.Page`, `.PageSize` | 传入模板但 `notes_public.html` 不做分页 |

### 1.7 不一致的控制器模式

| # | 文件 | 说明 |
|---|------|------|
| 19 | `controllers/share.go` `SharesPage` | 不使用 `commonData()` 辅助函数，手动构建 `gin.H`，手动解析 JWT 和查询友链。其他所有页面控制器都用 `commonData()`，此处不一致，后续维护可能遗漏字段 |

---

## 二、前端死代码 & 未使用资源

### 2.1 死代码 JS 函数

| # | 文件 | 行号 | 函数名 | 说明 |
|---|------|------|--------|------|
| 20 | `static/js/utils.js` | 118 | `handleApiResponse(res)` | 全项目无任何引用，完全死代码 |

### 2.2 未使用的字体文件（可节省 ~701 KB）

| # | 文件 | 大小 | 说明 |
|---|------|------|------|
| 21 | `static/webfonts/fa-brands-400.ttf` | 208 KB | 项目中无任何 `fa-brands`/`fab` 图标类使用 | ✅ 已删除 |
| 22 | `static/webfonts/fa-brands-400.woff2` | 117 KB | 同上 | ✅ 已删除 |
| 23 | `static/webfonts/fa-v4compatibility.ttf` | 11 KB | 项目中无 FA4 风格（`fa fa-*`）类，仅用 FA6 风格 | ✅ 已删除 |
| 24 | `static/webfonts/fa-v4compatibility.woff2` | 5 KB | 同上 | ✅ 已删除 |
| 25 | `static/css/fonts/ch-icon.eot` | 26 KB | IE6-8 专有格式，现代浏览器不需要 | ✅ 已删除 |
| 26 | `static/css/fonts/ch-icon.svg` | 334 KB | SVG 字体格式已废弃，TTF/woff/woff2 覆盖所有现代浏览器 | ✅ 已删除 |

**可选删除**（兼容性取舍）：

| # | 文件 | 大小 | 说明 |
|---|------|------|------|
| 27 | `static/webfonts/fa-solid-900.ttf` | 412 KB | woff2 格式已覆盖所有现代浏览器，ttf 仅 IE11/旧 Android 需要 |

### 2.3 重复 CSS

| # | 位置 | 说明 |
|---|------|------|
| 28 | `templates/base.html` vs `templates/editor_common.html` | `bs-dialog` 组件样式重复定义。base.html 用 CSS 变量，editor_common.html 用硬编码值，视觉不一致 | ✅ editor_common.html 改用 CSS 变量统一 |
| 29 | `templates/base.html` vs `templates/editor_common.html` | 滚动条、`focus-visible` 样式重复定义 | ✅ 已删除 editor_common.html 中的重复 |
| 30 | `templates/base.html` vs `static/css/search.css` | `header-search-bar`/`header-close-search`/`search-trigger` 样式重复定义 | ✅ 已删除 search.css 中的重复 |
| 31 | `templates/login.html` vs `templates/register.html` | `.sr-only` 类重复定义（且 `font-awesome.min.css` 已包含此样式，两处均多余） | ✅ 已删除两处内联 `.sr-only` |
| 32 | `templates/editor_common.html` vs `static/css/editor.css` | `.tb-btn` 相关样式重复定义 | 保留 editor_common.html 中的基础定义，editor.css 只有修饰选择器 |

### 2.4 冗余的 script 引用

| # | 文件 | 说明 |
|---|------|------|
| 33 | `templates/index.html:61` | 已通过 `footer` 模板加载 `bs-dialog.js`，又单独加载一次 |
| 34 | `templates/notes.html:182` | 同上，冗余加载 `bs-dialog.js` |

### 2.5 Bug：`notes_public.html` 缺少 `utils.js` 依赖

| # | 文件 | 说明 |
|---|------|------|
| 35 | `templates/notes_public.html` | 加载了 `bs-dialog.js`（依赖 `escHtml`/`escAttr`），但未加载 `utils.js`。`bs-dialog.js` 在 `notes.js` 之前加载，此时 `escHtml`/`escAttr` 未定义，存在运行时错误风险 |

---

## 三、模板死代码

### 3.1 未使用的模板定义

| # | 文件 | 行号 | 模板名 | 说明 |
|---|------|------|--------|------|
| 36 | `templates/base.html` | 344 | `{{define "empty-state"}}` | 定义了可复用的空状态组件，但全项目无任何 `{{template "empty-state"}}` 调用。各页面均内联实现空状态 | ✅ 已删除 |

### 3.2 死 CSS 类（定义了但从未使用）

**base.html 内联样式中的死类：**

| # | 类名 | 说明 |
|---|------|------|
| 37 | `.text-secondary` | 无任何模板或 JS 引用 | ✅ 已删除 |
| 38 | `.text-meta` | 同上 | ✅ 已删除 |
| 39 | `.text-link` | 同上 | ✅ 已删除 |
| 40 | `.text-success` | 同上 | ✅ 已删除 |
| 41 | `.text-danger` | 同上 | ✅ 已删除 |
| 42 | `.bg-success-hover` | 同上 | ✅ 已删除 |
| 43 | `.bg-info-light` | 同上 | ✅ 已删除 |
| 44 | `.text-placeholder` | 同上 | ✅ 已删除 |
| 45 | `.text-muted-light` | 同上 | ✅ 已删除 |

**components.css 中的死类：**

| # | 类名 | 说明 |
|---|------|------|
| 46 | `.type-badge` | 无任何模板或 JS 引用，已被 `share-type-badge` 取代 | ✅ 已删除 |
| 47 | `.type-badge-blog` | 同上 | ✅ 已删除 |
| 48 | `.type-badge-doc` | 同上 | ✅ 已删除 |

### 3.3 模板中使用但未定义的 CSS 类

| # | 类名 | 使用位置 | 说明 |
|---|------|----------|------|
| 49 | `.hide-mobile` | `admin_dashboard.html:152,305` | 用在 `<th>` 和 JS 渲染的 `<td>` 上，但未在任何 CSS 文件中定义，无实际效果 |

---

## 四、Git 跟踪的构建/数据产物（应从仓库移除）

| # | 文件 | 大小 | 说明 |
|---|------|------|------|
| 50 | `db.sqlite3` | 11 MB | 旧 Linkding 源数据库，`scripts/import_linkding.py` 的默认数据源 |
| 51 | `db.sqlite3-shm` | 32 KB | SQLite WAL 共享内存文件 |
| 52 | `db.sqlite3-wal` | 0 KB | SQLite WAL 日志文件 |
| 53 | `bookstark.db.bak` | 228 KB | 数据库备份文件 |
| 54 | `bookstark_test` | 35 MB | 编译的测试二进制文件 |

**修复方式**：`git rm --cached` 后提交，这些文件已在 `.gitignore` 中但之前已被跟踪。

---

## 五、迁移遗留文件

| # | 文件 | 大小 | 说明 |
|---|------|------|------|
| 55 | `scripts/migrate_mindoc.py` | - | 一次性 mindoc 迁移脚本 |
| 56 | `mindoc.db` | 964 KB | mindoc 迁移源数据库，未在 `.gitignore` 中 |
| 57 | `scripts/import_linkding.py` | - | 一次性 Linkding 导入脚本 |
| 58 | `db.sqlite3` | 11 MB | Linkding 源数据库（同 #50） |

如果迁移已完成，这些脚本和数据库可归档或删除。

---

## 六、其他问题

### 6.1 `.gitignore` 缺失项

| # | 缺失模式 | 说明 |
|---|----------|------|
| 59 | `mindoc.db` | 迁移源数据库未被忽略 |

### 6.2 Docker Compose 卷挂载过宽

| # | 文件 | 行号 | 说明 |
|---|------|------|------|
| 60 | `docker-compose.yml` | 9 | `./bookstark/:/data/` 挂载了整个项目目录，暴露源码和 `.git`。建议改为 `./data:/data` |

### 6.3 `sw.js` 预缓存包含未使用字体

| # | 文件 | 说明 |
|---|------|------|
| 61 | `static/sw.js:42-50` | 预缓存列表包含 `fa-brands-400.*`、`fa-v4compatibility.*` 等未使用字体，浪费约 341 KB 缓存空间 | ✅ 已更新 |

### 6.4 `font-awesome.min.css` 引用未使用字体

| # | 文件 | 说明 |
|---|------|------|
| 62 | `static/css/font-awesome.min.css` | `@font-face` 声明了 `fa-brands-400` 和 `fa-v4compatibility` 字体，但项目中从未使用对应图标类 | ✅ 已移除 |

---

## 汇总统计

| 类别 | 数量 | 可节省空间 |
|------|------|-----------|
| Go 死代码（函数/常量/类型） | 14 | - |
| 控制器冗余变量/不一致 | 5 | - |
| 前端死代码函数 | 1 | ~120 B |
| 未使用字体文件 | 6（+1可选） | ~701 KB（+412 KB 可选） |
| 重复 CSS | 5 处 | ~0.8 KB |
| 冗余 script 引用 | 2 | - |
| 依赖缺失 Bug | 1 | - |
| 模板死定义 | 1 | - |
| 死 CSS 类 | 12 | ~2 KB |
| Git 跟踪的产物文件 | 5 | ~46 MB |
| 迁移遗留文件 | 4 | ~12 MB |
| 其他问题 | 4 | - |
| **合计** | **62 项** | **~59 MB** |

---

## 建议优先级

### P0 - Bug 修复
- **#35** `notes_public.html` 缺少 `utils.js` 依赖

### P1 - 清理 Git 产物（节省 ~46 MB 仓库体积）
- **#50-54** `git rm --cached` 移除数据库、二进制文件

### P2 - 删除未使用字体（节省 ~701 KB+）
- **#21-26** 删除 FA Brands、FA v4compat、ch-icon.eot/svg
- **#61** 更新 `sw.js` 预缓存列表
- **#62** 更新 `font-awesome.min.css` @font-face

### P3 - 删除 Go 死代码
- **#1-14** 删除未使用的函数、常量、类型

### P4 - 清理前端死代码 & 重复
- **#20** 删除 `handleApiResponse`
- **#28-32** 去重 CSS
- **#33-34** 删除冗余 script 引用
- **#36-48** 删除死模板定义和死 CSS 类

### P5 - 清理迁移遗留
- **#55-58** 归档或删除迁移脚本和数据库
- **#59** `.gitignore` 添加 `mindoc.db`

### P6 - 低优先级
- **#15-18** 控制器冗余变量
- **#19** `SharesPage` 不一致模式
- **#49** `.hide-mobile` 未定义类
- **#60** Docker Compose 卷挂载