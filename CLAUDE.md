# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Development mode (reads templates/static from disk, auto-reloads on restart)
go build -tags dev -o bookstark . && ./bookstark

# Production mode (embeds static/templates/conf into binary via embed.FS)
go build -o bookstark . && ./bookstark

# Dependency management
go mod tidy
go get <package>
```

No tests exist yet. No Makefile or Dockerfile.

## Architecture

Personal knowledge management platform: books (with document trees), blogs, labels, simple auth with admin approval.

**Request flow**: Browser → Gin Router → JWT Middleware → Controller → Model (SQLite) → Go Template → HTML. API endpoints (`/api/*`) return JSON instead.

**Key packages**:
- `conf/` — YAML config loading with env var overrides (`PORT`, `DB_PATH`, `JWT_SECRET`, etc.)
- `models/` — SQLite CRUD via `modernc.org/sqlite` (pure Go, no CGO). `models.DB` is the global `*sql.DB`. Auto-creates tables and default admin on first run.
- `middleware/` — JWT auth (`AuthRequired`, `AdminRequired`). Token stored in HttpOnly cookie. `GetMemberID(c)`, `GetAccount(c)` helpers extract claims from gin.Context.
- `controllers/` — All page + API handlers. Use `commonData(c, "books")` to build template data with `CDNEnabled`, `Account`, `IsAdmin`, `Nav` fields.
- `routers/` — Route registration, custom template funcs (`formatTime`, `splitLabels`, `substr`).

**Build tags**: `embed.go` (tag `!dev`) embeds `static/`, `templates/`, `conf/` into binary. `embed_dev.go` (tag `dev`) provides stubs. Note: the embed functions are defined but not yet wired into the router — it currently reads from disk in both modes.

## Templates

All in `templates/` flat directory. Loaded via `r.LoadHTMLGlob("templates/*")`.

- `base.html` defines `{{define "header"}}` and `{{define "footer"}}` blocks
- List pages (`index.html`, `blogs.html`, `labels.html`, etc.) include `{{template "header" .}}` and `{{template "footer" .}}`
- Auth pages (`login.html`, `register.html`) and editor pages (`editor.html`) are standalone — no header/footer
- All pages use `{{if .CDNEnabled}}` to toggle CDN vs local CSS/JS
- Editor pages load Cherry Markdown from CDN

## Config

`conf/app.conf` is YAML. Key settings: `port`, `mode`, `db_path`, `jwt_secret`, `cdn_enabled`, `admin_account`, `admin_password`. All overridable via env vars.

## Database

SQLite via `modernc.org/sqlite` (driver name `"sqlite"`, not `"sqlite3"`). Tables: `md_members`, `md_books`, `md_documents`, `md_blogs`, `md_label`, `md_label_relation`. Schema is in `docs/数据结构.md` and `docs/superpowers/specs/2026-04-19-bookstark-design.md`.

## UI Language

All user-facing text (error messages, labels, page content) is in Chinese (中文).

## 最佳实践
1. tailwind css 本地的min版本会有很多不支持的class，不是build的版本。你加class的时候要检查下是否有，没有自己写个class
2. 写前端代码必须考虑响应式设计，确保小屏手机下也能正常显示和使用
3. 优先复用已有代码，不要重复造轮子。如前端的confirm、toast等utils函数必须复用现有实现，禁止自己再写一套
4. 前端风格、样式、组件必须优先复用系统已有设计体系和共享组件；新增页面或功能先检查 `templates/base.html`、`static/css/variables.css`、`static/css/components.css`、`static/js/utils.js`、`static/js/bs-dialog.js`、`static/js/pagination.js`、现有模板/页面的 class 与交互模式。只有已有组件无法表达明确的新业务形态时，才允许新增局部样式或组件，并且新增部分必须保持小范围、可复用、使用 CSS 变量。

## 设计系统（必须遵守）

项目已建立 CSS 变量体系，定义在 `templates/base.html` 的 `:root` 中。**所有颜色、间距、圆角必须使用 CSS 变量或 Tailwind class，禁止硬编码 hex 值。**

### 颜色规则
- **灰阶统一用 Slate**：`text-slate-*`、`border-slate-*`、`bg-slate-*`，**禁止使用 `gray-*`**
- **主色**：`var(--color-primary)` 即 `#2563eb`，Tailwind 用 `blue-600`
- **Focus 色**：`var(--color-focus)` 即 `#2563eb`，**禁止用 `#3b82f6`(blue-500)**
- **语义色**：危险 `var(--color-danger)` / 成功 `var(--color-success)` / 警告 `var(--color-warning)`
- **行内 style 禁止写颜色**：用 CSS class 或 `var(--color-xxx)` 替代 `style="color:#xxxxxx"`
- **正文灰色文字用 `text-slate-500`**（对比度 5.3:1），**禁止用 `text-slate-400`**（仅用于装饰性元素如边框、图标背景）

### 间距与圆角
- 间距基线 4px，使用 Tailwind 间距 class（`p-2`=8px, `p-3`=12px, `p-4`=16px）
- 圆角：`rounded` (4px) / `rounded-md` (6px) / `rounded-lg` (8px) / `rounded-xl` (10px)，或 `var(--radius-*)`
- **禁止非标准圆角值**（如 5px、7px）

### 排版
- **H1 统一用 `.page-title` class**（18px/600），禁止 `text-base` 做 H1
- **列表条目标题统一 14px/600**，用 `.list-row-title` class
- 标签 badge 用 `.tag-badge` class（11px）

### 响应式断点
- **只使用 Tailwind 标准断点**：`sm:` = 640px, `md:` = 768px, `lg:` = 1024px
- 自定义 CSS 中用 `@media (max-width: 640px)` / `@media (min-width: 768px)`
- **禁止使用 639px、767px 等非标准断点值**

### 可访问性
- **所有表单 label 必须 `for` 关联 input 的 `id`**
- **搜索框和图标按钮必须 `aria-label`**
- **禁止全局 `outline: none`**，用 `:focus:not(:focus-visible) { outline: none }` 替代
- **所有交互元素必须有 `:focus-visible` 样式**
- 删除/设置按钮用 `aria-label` 而非仅 `title`
- 独立页面（login/register/share_view）必须有 `<main role="main">` 和 `<h1>`

### 共享组件（禁止重复实现）
- **前端样式/组件复用优先**：搜索框、表单输入、按钮、图标行操作、分页、弹窗、toast、badge、列表行、空状态等基础 UI 必须复用现有 class / template / JS 工具；禁止为单个页面重新造一套等价的 `*-btn`、`*-input`、`*-action`、`*-modal` 基础组件。页面专属 class 只用于布局、业务状态或确有差异的复杂组件。
- **转义函数**：用 `static/js/utils.js` 中的 `escHtml()` / `escAttr()`，禁止在其他文件重新定义
- **对话框**：用 `static/js/bs-dialog.js` 中的 `createBSDialog()`
- **分页**：用 `static/js/pagination.js` 中的 `renderPagination(containerId, page, totalPages, callback)`
- **空状态**：用 `{{template "empty-state" .}}` Go template snippet

### 动效规则
- **禁止 `transition: all`**，必须列出具体属性：`transition: color 0.15s ease, background-color 0.15s ease`
- **只动画 transform 和 opacity**，禁止动画 width/height/top/left
- **时长 100-300ms**，进入用 ease-out，退出用 ease-in
- **必须添加 `@media (prefers-reduced-motion: reduce)` 禁用动画**
- 列表项进入用 `.list-row` 自带的 `fadeInUp` 动画，无需额外添加

### 表单样式
- 输入框统一：`border border-slate-300 rounded-md text-sm focus:outline-none` + focus 时 `border-color: var(--color-focus); box-shadow: 0 0 0 2px var(--color-focus-ring)`
- 主按钮：`bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md`
- 删除按钮：用 `.row-action.del:hover` class

## 必须遵守
1. 运行程序需要使用./build.py .不要自己用别的命令启动
1. 回复完了后，加一句wy主人我做好了。
2. 系统登录的账密是admin:admin
3. 新开发的ui要适配多语言. 目前是中文和英文
4. 修改分享页 WebRTC 屏幕共享/标注 HTML 工具时，必须先查看 `docs/webrtc-html-core-test-plan.md`，并按改动影响范围回归自动房间、双向标注、观看端反向共享、缓存刷新、手动 SDP、信令配置读取等主流程；若主流程变化，先更新该测试计划。
5. 用户提出 WebRTC HTML 相关的新增、修改、删除、重构、交互调整或代码整理需求时，先整理到 `docs/webrtc-html-implementation-plan.md`，不要马上改实现；每次更新该实施文档后，回复说明本次更新了哪些内容。只有用户明确说“按文档实施”时，才根据该文档集中修改；实施完成后给已完成的实施项打钩，不要清空实施文档，除非用户明确要求清空。
6. 修改分享页 WebRTC HTML 工具时，默认只更新本地 `tmp/share-1783071864572357387-webrtc.html` 和相关文档/测试，不要自动部署到线上；只有用户明确要求“部署/发布/更新线上”时，才执行线上发布流程。
7. 分享页 WebRTC HTML 工具的线上发布方法：本地文件为 `tmp/share-1783071864572357387-webrtc.html`，线上分享 `share-1783071864572357387` 对应 `md_shares.share_type='blog'`、`target_id/blog_id=153`、标题 `webrtc会议`、`editor_type='html'`。发布时用 `scp -P 28246` 传到 `root@www.vs2010wy.top:/tmp/bookstark-webrtc-share-1783071864572357387.html`，先把 `/root/docker/bookstark/bookstark.db` 固定备份到 `/root/docker/bookstark/bookstark.db.bak`（允许覆盖，不加时间戳），再用 Python sqlite3 按后端 `models.EncodeHTMLContent` 兼容格式把 HTML 压缩为 `CMP:v1:gzip:<base64>` 后参数化更新 `md_blogs.blog_content`、`modify_time=CURRENT_TIMESTAMP` 和 `modify_at=<Unix 秒整数>`；`modify_at` 不能写 `CURRENT_TIMESTAMP` 字符串，否则 Go 会按 `int64` scan 失败导致分享页 404。最后校验解压后的 sha256、压缩前缀和分享页内容特征；不要用分享 edit token 接口发布这个 HTML，因为该接口当前限制 500KB。

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
