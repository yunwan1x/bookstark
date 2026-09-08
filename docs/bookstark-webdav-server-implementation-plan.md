# BookStark 内置 WebDAV 服务实施计划

更新时间：2026-07-24

## 使用规则

- 本文档用于规划 BookStark 内置 WebDAV 服务端、独立文件数据库和公共静态资源发布能力。
- 本轮实现已于 2026-07-24 完成；代码评审、自动化测试和本地大小屏浏览器复核结果见文末。
- 实施时按阶段完成并将对应项目从 `[ ]` 改为 `[x]`。
- 内置 WebDAV 服务端与现有“连接外部 WebDAV”客户端是两套能力，不能混用数据模型或权限边界。

## 1. 目标与范围

### 目标

- [ ] BookStark 自身提供标准 WebDAV 服务，支持第三方 WebDAV 客户端连接。
- [ ] 每个 BookStark 用户自动拥有一个独立、默认可用的内置 WebDAV 空间。
- [ ] WebDAV 文件、目录、公开资源映射和 WebDAV 应用密码存入独立 SQLite 数据库。
- [ ] 文件管理界面支持上传、下载、预览、编辑、创建目录、复制、移动、重命名和删除。
- [ ] 单个文件可发布为无需登录即可访问的静态资源，供 BookStark HTML 文档引用。
- [ ] 文件 BLOB 根据扩展名和试压缩结果决定是否 gzip 存储，避免重复压缩。
- [ ] 不增加文件内容内存缓存。

### 不在首版范围

- [ ] 不提供跨用户共享目录。
- [ ] 不公开整个目录，只允许逐文件发布。
- [ ] 不做文件历史版本和在线协同编辑。
- [ ] 不将内置 WebDAV 文件复制到主业务数据库。
- [ ] 不使用用户登录密码直接连接第三方 WebDAV 客户端。

## 2. 现有能力与改造边界

当前实现：

- `services/asset_webdav.go` 是 BookStark 作为客户端访问外部 WebDAV。
- `md_asset_webdav_servers` 保存外部连接配置。
- `/api/admin/assets/webdav-servers/*` 和 `/admin/assets/*` 当前位于管理员权限组。
- 现有 WebDAV 文件管理请求最终转发到远端服务器，不保存文件内容。

新增实现必须满足：

- [ ] 保留现有外部 WebDAV 连接和远端文件管理能力。
- [ ] 新增内置 WebDAV 服务端，不把内置服务伪装成一条可删除的外部连接记录。
- [ ] WebDAV 列表 API 返回一个固定置顶的虚拟条目 `BookStark WebDAV`。
- [ ] 内置条目对每个已登录用户自动存在、不可删除，文件列表只展示当前用户的数据。
- [ ] 外部 WebDAV 连接继续使用主数据库；内置文件只使用新数据库。
- [ ] 普通用户获得内置 WebDAV 文件管理入口；SSH、Docker、系统设置仍保持管理员权限。
- [ ] 若普通用户也允许创建外部 WebDAV 连接，必须先给现有连接查询和 CRUD 补齐 `created_by` 所有权过滤；首版默认仍仅管理员管理外部连接。

## 3. 独立数据库

### 数据库初始化

- [ ] 新增独立连接 `WebDAVDB`，默认路径 `/data/bookstark-webdav.db`。
- [ ] 增加配置项 `WEBDAV_DB_PATH`，本地默认 `./bookstark-webdav.db`。
- [ ] 启用 WAL、`synchronous=NORMAL`、`busy_timeout=5000` 和外键约束。
- [ ] 应用启动时独立执行 WebDAV 数据库迁移；迁移失败时应用启动失败并输出明确日志。
- [ ] 部署和备份流程同时覆盖 `bookstark.db` 与 `bookstark-webdav.db`。

### `dav_blobs`

文件内容采用全局内容寻址存储，同一份原始内容在数据库中只保留一个 BLOB：

```sql
CREATE TABLE IF NOT EXISTS dav_blobs (
    blob_id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash TEXT NOT NULL,
    original_size INTEGER NOT NULL DEFAULT 0,
    stored_size INTEGER NOT NULL DEFAULT 0,
    compression TEXT NOT NULL DEFAULT 'none',
    content_blob BLOB NOT NULL,
    proof_chunk_size INTEGER NOT NULL DEFAULT 0,
    proof_chunk_hashes TEXT NOT NULL DEFAULT '',
    ref_count INTEGER NOT NULL DEFAULT 0,
    create_time DATETIME NOT NULL,
    UNIQUE(content_hash, original_size)
);
```

- [ ] `content_hash` 是原始未压缩内容的 SHA-256，查重同时校验 `original_size`。
- [ ] `compression`、`stored_size` 和 `content_blob` 属于内容对象，不在每个用户文件节点中重复保存。
- [ ] 第一次写入内容时生成固定分块的校验摘要，用于网页端跨用户秒传的所有权证明。
- [ ] `ref_count` 记录所有用户文件节点的引用数，但删除 BLOB 前仍执行 `NOT EXISTS` 查询作为一致性保护。
- [ ] 同哈希并发写入依靠唯一约束决出一个 BLOB；失败事务改为复用已存在记录，不能生成重复内容。

### `dav_nodes`

```sql
CREATE TABLE IF NOT EXISTS dav_nodes (
    node_id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id INTEGER NOT NULL,
    parent_id INTEGER,
    name TEXT NOT NULL,
    is_dir INTEGER NOT NULL DEFAULT 0,
    mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
    blob_id INTEGER,
    etag TEXT NOT NULL DEFAULT '',
    create_time DATETIME NOT NULL,
    modify_time DATETIME NOT NULL,
    UNIQUE(member_id, parent_id, name),
    FOREIGN KEY(parent_id) REFERENCES dav_nodes(node_id) ON DELETE CASCADE,
    FOREIGN KEY(blob_id) REFERENCES dav_blobs(blob_id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_dav_nodes_member_root
ON dav_nodes(member_id) WHERE parent_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_dav_nodes_blob
ON dav_nodes(blob_id);
```

- [ ] 每个用户创建一个实体根目录节点，根节点 `parent_id=NULL`，其余节点必须引用同一用户的目录节点。
- [ ] `idx_dav_nodes_member_root` 保证每个用户只有一个根目录。
- [ ] 所有查询必须同时包含 `member_id`，不能只根据 `node_id` 读取。
- [ ] 目录的 `blob_id` 必须为空，文件必须引用有效 `dav_blobs.blob_id`。
- [ ] 文件更新在一个事务内切换 BLOB 引用、更新 ETag 和修改时间，并维护新旧 BLOB 引用数。
- [ ] 同一 BLOB 可以被不同用户、不同目录和不同文件名引用；节点的名称、MIME 和公开状态彼此独立。
- [ ] 删除目录依赖外键级联删除子节点及其公开映射。

### `dav_public_assets`

```sql
CREATE TABLE IF NOT EXISTS dav_public_assets (
    asset_id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id INTEGER NOT NULL,
    node_id INTEGER NOT NULL UNIQUE,
    public_path TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    create_time DATETIME NOT NULL,
    modify_time DATETIME NOT NULL,
    UNIQUE(member_id, public_path),
    FOREIGN KEY(node_id) REFERENCES dav_nodes(node_id) ON DELETE CASCADE
);
```

- [ ] `public_path` 是用户空间内的相对路径，禁止空值、`..`、反斜杠、控制字符和保留路径。
- [ ] 同一用户的公开路径唯一；冲突返回 `409`，不能静默覆盖。
- [ ] 重命名源文件默认不修改公开地址，保证 HTML 文档引用稳定。
- [ ] 删除源文件自动删除公开映射，旧地址返回 `404`。

### `dav_app_credentials`

- [ ] 每个用户最多一条当前有效 WebDAV 应用密码记录。
- [ ] 仅保存应用密码哈希、创建时间和最后使用时间，不保存明文。
- [ ] 支持生成、重置和撤销；重置后旧密码立即失效。
- [ ] 用户身份以主数据库中的有效 `member_id` 为准，跨数据库关系由服务层校验。

## 4. BLOB 压缩策略

### 两级判断

1. 先根据小写文件扩展名分类。
2. 通过扩展名初筛后，再对内容做预压缩尝试。

固定规则：

- [ ] 原始内容小于 `4 KiB` 时直接保存，`compression=none`。
- [ ] 已压缩格式直接跳过预压缩并原样保存。
- [ ] 文本及未知格式抽取最多前 `64 KiB`，使用 gzip 做预压缩。
- [ ] 预压缩节省比例达到 `10%` 及以上时，才 gzip 压缩完整文件。
- [ ] 低于阈值时原样保存，不能因为扩展名是文本就强制压缩。
- [ ] 文件扩展名只用于第一层筛选，MIME 仍结合扩展名与 `http.DetectContentType` 判断。

默认跳过压缩的扩展名：

```text
jpg jpeg png gif webp avif heic
mp3 aac m4a ogg flac wav
mp4 webm mov m4v mkv avi
zip gz bz2 xz 7z rar tar
pdf woff woff2
docx xlsx pptx
```

默认进入预压缩的扩展名：

```text
html htm js mjs css
json jsonl xml svg
md markdown txt csv tsv
yaml yml toml ini conf log
```

### 存储与读取

- [ ] `dav_blobs.content_hash` 始终计算原始内容的 SHA-256。
- [ ] `dav_blobs.original_size` 保存解压后的文件大小，`stored_size` 保存 BLOB 实际大小。
- [ ] `dav_blobs.compression` 首版仅允许 `none` 或 `gzip`。
- [ ] WebDAV GET 默认使用 `gzip.Reader` 流式解压为原始文件，不将完整文件加载到内存。
- [ ] 不实现解压结果内存缓存。
- [ ] 图片、音视频和压缩包保持原始 BLOB，继续支持标准 Range 请求。
- [ ] 压缩文本资源首版不声明 `Accept-Ranges`；客户端请求 Range 时返回完整 `200`，避免错误地把压缩字节范围当成原文件范围。

### 内容查重与秒传

共同规则：

- [ ] “相同文件”以原始内容的 `SHA-256 + original_size` 判断，与文件名、目录、用户和压缩结果无关。
- [ ] 命中已有 BLOB 时只新增或切换 `dav_nodes.blob_id` 引用，不重复写入 `content_blob`。
- [ ] 用户逻辑配额仍按每个文件节点的 `original_size` 计算，不能借助全局去重绕过个人配额。
- [ ] 物理存储统计单独按 `dav_blobs.stored_size` 计算，并显示去重节省空间。

网页文件管理上传：

- [ ] WebDAV 管理界面的上传使用 BookStark 专用上传 API，不直接模拟标准 WebDAV PUT，因此允许增加上传前查重和秒传握手。
- [ ] 浏览器在 Web Worker 中分块计算文件 SHA-256，不能一次把完整文件读入页面内存或阻塞主线程。
- [ ] 上传前调用查重接口，只提交文件大小、SHA-256、目标目录和文件名。
- [ ] 如果当前用户已经引用该 BLOB，服务端可以直接创建目标节点并返回“秒传完成”。
- [ ] 如果 BLOB 只属于其他用户，不能只凭完整文件哈希授予访问权，必须进入内容所有权证明。
- [ ] 所有权证明由服务端随机选择若干原始内容分块并返回短时挑战；浏览器提交带挑战随机数的分块摘要，服务端与现有 BLOB 内容核验。
- [ ] 挑战不返回其他用户、文件名、路径或公开状态，过期时间不超过 5 分钟且只能使用一次。
- [ ] 证明通过后创建当前用户节点引用并返回“秒传完成”；失败后继续正常上传，不能暴露已有内容。
- [ ] 小文件或不足以安全抽样的文件直接走正常上传，不启用跨用户秒传。
- [ ] 查重结果为 `instant_complete` 时不再发送文件请求体，直接把服务端返回的新文件节点加入当前列表。
- [ ] 查重结果为 `upload_required` 时才开始普通分块或 multipart 上传。
- [ ] 批量上传时每个文件独立查重：已存在的文件立即完成，其余文件继续上传，一个文件失败不能取消整批任务。

标准 WebDAV PUT：

- [ ] 标准 WebDAV 客户端没有秒传握手，因此仍需把请求体发送到服务端。
- [ ] 服务端边接收边写入受限制的临时文件并计算原始 SHA-256；接收完成后查询 `dav_blobs`。
- [ ] 命中已有 BLOB 时丢弃临时文件，只创建或更新节点引用，从而避免数据库重复存储。
- [ ] 未命中时再执行扩展名初筛、预压缩和完整内容入库。
- [ ] 不能因为请求携带一个未经证明的哈希头就跨用户复用内容。

覆盖、复制与删除：

- [ ] 同一用户复制文件只创建新节点并增加 BLOB 引用，不复制内容。
- [ ] 覆盖文件时先增加新 BLOB 引用，再切换节点，最后减少旧 BLOB 引用，整个过程必须在事务内完成。
- [ ] 删除单个用户文件只删除该用户节点和公开映射，不影响其他用户对同一 BLOB 的引用。
- [ ] 只有所有用户的文件节点都不再引用该 BLOB 时，才删除 `dav_blobs` 内容。
- [ ] 删除 BLOB 的条件必须同时满足 `ref_count=0` 和 `NOT EXISTS (SELECT 1 FROM dav_nodes WHERE blob_id=?)`。
- [ ] 目录递归删除、用户注销和覆盖写入都必须执行相同的引用清理规则。
- [ ] 增加孤立 BLOB 清理与引用数修复任务，发现计数漂移时以 `dav_nodes` 实际引用为准。

## 5. WebDAV 协议服务

### 路由与认证

- [ ] WebDAV 入口为 `/dav/*path`。
- [ ] 使用 HTTP Basic Auth，用户名为 BookStark 账号，密码为独立 WebDAV 应用密码。
- [ ] 网页文件管理继续使用现有登录 Cookie/JWT，不要求重复输入应用密码。
- [ ] 禁止停用、未审核或不存在的用户访问。
- [ ] 认证失败统一返回标准 `401` 和 `WWW-Authenticate`。

### 首版方法

- [ ] `OPTIONS`
- [ ] `PROPFIND`
- [ ] `HEAD`
- [ ] `GET`
- [ ] `PUT`
- [ ] `MKCOL`
- [ ] `DELETE`
- [ ] `MOVE`
- [ ] `COPY`
- [ ] `LOCK`
- [ ] `UNLOCK`

实现建议：

- [ ] 使用 `golang.org/x/net/webdav` 处理协议行为和 XML 响应。
- [ ] 实现 SQLite-backed `webdav.FileSystem`，写入文件时使用受大小限制的临时文件或流式处理，关闭时提交事务。
- [ ] 使用 `webdav.NewMemLS()` 提供单实例锁；应用重启后锁失效可以接受，但不能影响文件数据。
- [ ] 路径解析统一清理 URL 编码、重复分隔符和 `.`，拒绝 `..` 穿越。
- [ ] COPY/MOVE 必须校验源和目标都属于当前用户。

## 6. 文件限制与配额

- [ ] 增加系统设置：单文件最大容量、单用户总容量、允许公开资源的最大容量。
- [ ] 首版建议默认值：单文件 `50 MiB`、单用户 `1 GiB`、单个公开资源 `20 MiB`。
- [ ] 在系统设置的 WebDAV 区域增加“使用独立静态资源地址”开关，默认关闭。
- [ ] 增加“独立静态资源基础地址”输入框；开关关闭时禁用，开启后必填。
- [ ] 设置键使用 `webdav_public_asset_separate_url_enabled=false` 和 `webdav_public_asset_base_url=''`。
- [ ] PUT 和网页上传在接收过程中执行硬限制，超限立即停止，不能先全部读入内存。
- [ ] 用户容量按 `original_size` 计算，避免压缩率不同造成配额含义不一致。
- [ ] 文件列表返回当前已用容量和配额，管理界面显示紧凑进度。
- [ ] 数据库写入失败或容量不足时，原文件保持不变。

## 7. 公共静态资源

### 发布流程

- [ ] 文件操作菜单增加“发布为静态资源”。
- [ ] 默认公开路径取当前文件名并保留扩展名。
- [ ] 发布弹窗允许输入自定义相对路径，例如 `libs/chart/app.js`。
- [ ] 实时显示完整 URL，并提供复制、保存和取消公开。
- [ ] 文件列表显示“已公开”状态和复制地址操作。
- [ ] 同一个文件只保留一个公开地址；修改公开路径时旧地址立即失效。

### 公开地址模式

- [ ] 默认不启用独立地址，生成 BookStark 同源地址：
  `https://books.vs2010wy.top/dav-public/{member-key}/{public-path}`。
- [ ] 管理员可以在系统设置中开启“使用独立静态资源地址”，并填写绝对基础地址，例如 `https://assets.vs2010wy.top`。
- [ ] 开启后生成：
  `{webdav_public_asset_base_url}/{member-key}/{public-path}`。
- [ ] 独立地址必须为合法 `http/https` URL，不允许用户名、密码、查询参数或片段；保存设置时去掉末尾 `/`。
- [ ] 开关开启但地址为空或校验失败时拒绝保存，不能静默回退到同源地址。
- [ ] 切换地址模式只改变随后展示和复制的完整 URL，不修改 `public_path`、文件内容和公开映射。
- [ ] 设置界面提示：切换模式后以前复制到 HTML 文档里的完整地址不会自动修改。
- [ ] 独立地址由反向代理指向 BookStark 公共资源处理器，并且不复用 BookStark 登录 Cookie。
- [ ] 默认同源模式允许直接引用 JS、CSS 等资源，但系统设置中显示安全提示：多用户或不受信内容推荐改用独立无 Cookie 域名。
- [ ] 返回 `Access-Control-Allow-Origin: *` 和 `X-Content-Type-Options: nosniff`。
- [ ] 两种地址模式使用同一套资源查询、权限、MIME、压缩和缓存逻辑，不能形成两份文件数据。

### HTTP 输出

当文件以 gzip BLOB 存储且客户端发送 `Accept-Encoding: gzip`：

- [ ] 直接流式输出数据库中的 gzip BLOB，不在服务端解压。
- [ ] 设置原始 `Content-Type`。
- [ ] 设置 `Content-Encoding: gzip`。
- [ ] 设置 `Vary: Accept-Encoding`。
- [ ] 使用原始内容哈希生成稳定 ETag。

客户端不支持 gzip 时：

- [ ] 使用 `gzip.Reader` 边读取边解压输出，不建立内存缓存。

未压缩文件：

- [ ] 原样流式输出，支持 `HEAD`、条件请求和适用时的 Range。

缓存规则：

- [ ] 默认 `Cache-Control: public, max-age=3600`。
- [ ] 支持 `If-None-Match`，内容未变化返回 `304`。
- [ ] 文件内容更新后 ETag 改变，地址不变。
- [ ] MIME 必须来自保存时检测结果，不能仅信任用户自定义公开路径的扩展名。

## 8. 管理界面

### WebDAV 列表

- [ ] WebDAV 管理区域对普通已登录用户开放，但 SSH、Docker 和系统设置仍仅管理员可见。
- [ ] 第一项固定显示 `BookStark WebDAV`，状态为“内置服务”。
- [ ] 内置条目显示服务器地址、当前用户、已用空间和文件数量。
- [ ] 操作包括“文件管理”“连接信息”“重置应用密码”，不显示编辑和删除。
- [ ] 外部 WebDAV 条目保持现有样式，视觉上区分“内置”和“外部”。

### 文件管理

- [ ] 复用现有 WebDAV 文件管理表格、面包屑、上传、编辑器和移动端 modal/sheet 样式。
- [ ] 内置服务文件操作调用本地 API，不再通过 `AssetWebDAVManager` 发 HTTP 请求给自己。
- [ ] 点击上传后先显示“计算指纹”，再按结果进入“秒传完成”“验证文件”或“上传中”，不能先创建一条假的 100% 上传任务。
- [ ] 秒传完成与普通上传完成使用相同的文件列表刷新和成功提示。
- [ ] 增加公开状态列与“发布资源”操作。
- [ ] 小屏下公开状态放入文件副信息，公开、复制和取消公开归入操作菜单。
- [ ] 所有异步列表、上传和目录切换使用现有骨架屏或进度状态。

## 9. API 规划

网页管理 API 使用当前登录用户身份：

```text
GET    /api/webdav/files
GET    /api/webdav/files/download
GET    /api/webdav/files/content
PUT    /api/webdav/files/content
POST   /api/webdav/files/upload
POST   /api/webdav/files/dedup/check
POST   /api/webdav/files/dedup/prove
POST   /api/webdav/files/mkdir
POST   /api/webdav/files/rename
POST   /api/webdav/files/copy
DELETE /api/webdav/files

GET    /api/webdav/profile
POST   /api/webdav/app-password/reset

POST   /api/webdav/public-assets
PUT    /api/webdav/public-assets/:id
DELETE /api/webdav/public-assets/:id
```

- [ ] 所有本地文件 API 使用 `AuthRequired` 和 CSRF 防护。
- [ ] 每次文件操作从上下文获取 `member_id`，请求体不接收可覆盖的用户 ID。
- [ ] 查重接口只返回 `upload_required`、`proof_required` 或 `instant_complete`，不返回其他用户或已有文件信息。
- [ ] 秒传完成响应与普通上传使用一致的文件节点结构，前端无需维护两套列表逻辑。
- [ ] 公开读取路由不使用认证中间件，只允许读取 `enabled=1` 的映射。
- [ ] 错误状态统一覆盖 `400/401/403/404/409/413/507`。

## 10. 数据一致性与生命周期

- [ ] 主数据库删除用户前先调用 WebDAV 数据服务清理该用户节点、公开映射和应用密码。
- [ ] 主数据库与 WebDAV 数据库不能假设存在跨库原子事务；失败时记录可重试的清理日志。
- [ ] WebDAV 数据库提供独立完整性检查：孤立节点、孤立 BLOB、引用数漂移、重复路径、无源公开映射、大小和哈希不一致。
- [ ] 系统数据导出页面增加独立的“WebDAV 文件数据库”备份入口，不把大量 BLOB 默认塞入现有 JSON 导出。
- [ ] 恢复 WebDAV 数据库后重新校验表结构、哈希和公开路径唯一性。

## 11. 测试计划

### 模型与压缩

- [ ] 文本、未知格式、已压缩格式和小文件分别命中正确策略。
- [ ] `64 KiB` 预压缩与 `10%` 阈值边界测试。
- [ ] 扩展名伪装文件不会造成内容损坏。
- [ ] gzip 写入后读取内容、原始大小和 SHA-256 完全一致。
- [ ] 已压缩文件不会被二次 gzip。
- [ ] 并发更新、重命名冲突和容量超限不会留下半写文件。
- [ ] 两个用户上传相同内容后只有一条 `dav_blobs`，但各自拥有独立文件节点。
- [ ] 同一用户复制相同文件只增加引用，不增加 BLOB。
- [ ] 删除一个用户的文件后其他用户仍能读取；删除最后一个引用后 BLOB 才被删除。
- [ ] 并发上传相同内容不会突破唯一约束或产生错误引用数。
- [ ] 覆盖文件失败时原节点、原 BLOB 引用和内容保持不变。

### 秒传安全

- [ ] 当前用户已拥有内容时，网页上传查重可以直接完成且不发送完整文件。
- [ ] 仅知道其他用户文件的 SHA-256 不能创建引用或下载内容。
- [ ] 跨用户挑战证明通过后可以秒传，挑战失败、过期或重复使用均被拒绝。
- [ ] 查重响应不泄露其他用户、路径、文件名和公开状态。
- [ ] 标准 WebDAV PUT 命中相同内容后不重复写数据库，但仍正确消费完整请求体。

### 权限

- [ ] 两个用户使用相同路径时数据互不影响。
- [ ] 用户不能通过 node ID、路径穿越、MOVE 或 COPY 访问其他用户文件。
- [ ] 重置应用密码后旧凭据失败，新凭据成功。
- [ ] 普通用户不能访问 SSH、Docker 和管理员设置。

### WebDAV 客户端

- [ ] macOS Finder、Windows WebDAV 或至少一个标准 CLI 客户端完成挂载。
- [ ] 完成目录创建、上传、覆盖、下载、复制、移动、重命名和递归删除。
- [ ] 中文、空格和 URL 编码文件名正常。
- [ ] 断线重试不会生成重复文件或损坏 BLOB。

### 公共资源

- [ ] JS、CSS、图片和字体可被 HTML 文档直接引用。
- [ ] 默认设置生成主站 `/dav-public/{member-key}/{public-path}` 地址。
- [ ] 开启独立地址并配置基础 URL 后，界面生成独立地址且文件内容保持不变。
- [ ] 独立地址开关默认关闭；开启时空地址、相对地址和带凭据地址均不能保存。
- [ ] 切换地址模式不会修改公开路径映射，并明确提示已有 HTML 引用不会自动迁移。
- [ ] 支持 gzip 的浏览器收到 `Content-Encoding: gzip` 并正确执行或渲染。
- [ ] 不支持 gzip 的请求获得完全一致的原始内容。
- [ ] ETag、`304`、CORS、MIME 和缓存头正确。
- [ ] 自定义路径冲突返回 `409`。
- [ ] 取消公开或删除文件后地址返回 `404`。
- [ ] 公开资源请求不携带或依赖 BookStark 登录状态。

### UI

- [ ] 每个用户首次打开 WebDAV 管理都能看到内置条目。
- [ ] 内置条目不可删除，外部条目行为不回归。
- [ ] 桌面和小屏文件管理、发布弹窗、复制地址和容量提示无溢出。
- [ ] 上传、保存、删除和发布均为 AJAX 更新，不刷新整个页面。
- [ ] 上传状态明确区分“计算指纹”“验证文件”“上传中”和“秒传完成”，不能在计算哈希期间显示为卡死。

## 12. 实施顺序

1. [x] 建立独立数据库连接、内容寻址 BLOB、引用模型、迁移和压缩编码测试。
2. [x] 实现按用户隔离的文件服务、引用生命周期、查重秒传与网页管理 API。
3. [x] 实现标准 WebDAV 协议、应用密码和自动化客户端兼容测试。
4. [x] 将内置服务接入现有 WebDAV 管理和文件页面。
5. [x] 实现公开静态资源映射、默认同源/可选独立地址设置和浏览器 gzip 响应。
6. [x] 补充配额、独立数据库备份、用户数据清理入口和引用完整性修复。
7. [ ] 完成真实 Finder/Windows 客户端、线上反向代理、独立静态域名和部署后 canary；本地自动化及桌面/小屏浏览器复核已完成。
8. [ ] 实施“问题 2：大文件 BLOB 分块存储”，将数据库内容读写改为固定分块和有界内存流式处理。

## 13. 实施与评审结果

### 已完成

- [x] 新增独立 `WebDAVDB`、`-webdav-db` 参数和 `WEBDAV_DB_PATH` 配置，启动时自动迁移并修复引用计数。
- [x] 文件内容使用 SHA-256 全局去重；用户节点、目录、公开地址和应用密码保持独立权限边界。
- [x] 按扩展名初筛并试压缩，已压缩格式不重复压缩；未增加文件内容内存缓存。
- [x] 网页管理上传使用 Web Worker 分块计算 SHA-256，支持同用户秒传和跨用户一次性分块证明。
- [x] 标准 WebDAV 支持 `OPTIONS/PROPFIND/HEAD/GET/PUT/MKCOL/DELETE/MOVE/COPY/LOCK/UNLOCK`，使用独立应用密码认证。
- [x] 文件管理支持目录、上传、下载、文本编辑、复制、重命名、删除和静态资源发布，操作均为 AJAX。
- [x] 公共资源支持同源/独立基础地址、ETag、`304`、HEAD、Range、CORS、MIME、gzip 协商和固定地址更新。
- [x] 管理设置支持单文件、用户配额、公开文件上限及独立静态地址校验。
- [x] 系统导出区提供 WebDAV 数据库独立备份入口。
- [x] 桌面和小屏浏览器复核通过，公开 URL 可在弹窗输入时实时预览。

### 评审中修复

- [x] 修复相同内容并发上传偶发 `SQLITE_BUSY`：根目录读取不再产生无意义写事务，提交增加有限指数退避重试。
- [x] 修复网页端目录名、上传父路径和模型层路径的 `..` 穿越风险，同时保留合法空格文件名。
- [x] 修复复制到“父路径其实是文件”时仍可能创建节点的问题。
- [x] 修复 gzip 存储资源在客户端不接受 gzip 时缺少 `Vary: Accept-Encoding` 的缓存污染风险。
- [x] 修复用户物理空间统计重复累计同一 BLOB 的问题，并补充去重与压缩节省字段。
- [x] 修复秒传成功后仍提示“已上传”的状态误导，并在容量条下展示文件数、实际存储、去重和压缩节省量。
- [x] 修复移动端公开资源弹窗和文件操作菜单的尺寸、焦点、Escape 与忙碌状态问题。

### 验证基线

- [x] `go test ./... -count=1`
- [x] `go vet ./...`
- [x] `go test -race ./models ./services`
- [x] `go test -race ./controllers -run TestLocalDAV -count=1`
- [x] WebDAV 模型测试连续 20 轮通过；同内容并发上传测试连续 20 轮通过。
- [x] WebDAV 控制器测试连续 10 轮通过。
- [x] `node --check static/js/webdav.js`
- [x] `node --check static/js/webdav-hash-worker.js`
- [x] `git diff --check`
- [x] 本地桌面与小屏浏览器复核无控制台错误。

### 上线前仍需验证

- [ ] 使用 macOS Finder、Windows WebDAV 或独立 CLI 客户端完成真实挂载回归。
- [ ] 验证生产反向代理允许 WebDAV 方法和 `Destination`、`Depth`、`Lock-Token` 等请求头。
- [ ] 若启用独立静态资源域名，验证 DNS、TLS、无登录 Cookie 和跨域响应。
- [ ] 部署时同时备份主数据库与 `bookstark-webdav.db`，部署后执行公开资源和 WebDAV canary。

备注：完整控制器 race 套件仍会触发项目已有的 `models/visit_log.go` 后台写入与测试替换全局 `models.DB` 的竞态；WebDAV 定向控制器 race 测试通过，该既有问题不属于本次实现。

## 14. 问题 2：大文件 BLOB 分块存储计划

### 问题与目标

当前 `dav_blobs.content_blob` 将一个文件作为单个 SQLite BLOB 保存。即使上传阶段先落临时文件，入库、读取、解压、公开资源响应和部分校验路径仍可能把完整 BLOB 载入 Go 内存。文件增大或多个请求并发时，内存峰值会随“文件大小 × 并发数”增长。

本项改造目标：

- [x] 数据库存储、读取、压缩、解压和 Range 响应均不再依赖完整文件 `[]byte`。
- [x] 单次传输的服务端内存占用由固定分块决定，不随文件总大小线性增长。
- [x] 保持现有内容寻址去重、跨用户引用、应用密码、WebDAV 协议和公开资源 URL 行为不变。
- [x] 删除最后一个文件引用时，在同一事务中完整删除元数据和全部内容分块。
- [x] 不增加文件内容内存缓存。

### 固定分块决策

- [x] 原始逻辑文件按固定 `1 MiB`（`1,048,576` 字节）切分，最后一块允许不足 `1 MiB`。
- [x] 首版不把分块大小暴露为系统设置；分块大小作为数据库格式常量并记录到 BLOB 元数据中。
- [x] 空文件保留 BLOB 元数据但不创建内容分块；非空小文件只创建一个分块。
- [x] 每个原始分块独立执行压缩判断，压缩收益达到现有阈值时保存为 `gzip`，否则保存为 `none`。
- [x] 每个压缩分块必须是独立、完整的 gzip 数据，不跨分块共享压缩流。
- [x] `dav_blobs.content_hash` 仍是完整原始文件的 SHA-256；每个分块另外保存原始字节 SHA-256，用于读取、所有权证明和修复校验。

### 数据表设计

当前没有 WebDAV 文件数据，直接采用最终分块表结构：

```sql
CREATE TABLE IF NOT EXISTS dav_blobs (
    blob_id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash TEXT NOT NULL,
    original_size INTEGER NOT NULL DEFAULT 0,
    stored_size INTEGER NOT NULL DEFAULT 0,
    chunk_size INTEGER NOT NULL DEFAULT 1048576,
    chunk_count INTEGER NOT NULL DEFAULT 0,
    ref_count INTEGER NOT NULL DEFAULT 0,
    create_time DATETIME NOT NULL,
    UNIQUE(content_hash, original_size)
);

CREATE TABLE IF NOT EXISTS dav_blob_chunks (
    blob_id INTEGER NOT NULL,
    chunk_index INTEGER NOT NULL,
    original_size INTEGER NOT NULL,
    stored_size INTEGER NOT NULL,
    compression TEXT NOT NULL DEFAULT 'none',
    chunk_hash TEXT NOT NULL,
    content_blob BLOB NOT NULL,
    PRIMARY KEY (blob_id, chunk_index),
    FOREIGN KEY (blob_id) REFERENCES dav_blobs(blob_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_dav_blob_chunks_blob
ON dav_blob_chunks(blob_id);
```

- [x] `chunk_size=1048576`，`chunk_count` 必须与实际分块数一致。
- [x] `original_size`、`stored_size`、`compression` 和 `chunk_hash` 属于单个分块。
- [x] `dav_blobs.stored_size` 保存所有分块 `stored_size` 之和，物理空间统计口径不变。
- [x] `dav_blobs` 不再包含 `content_blob`、文件级 `compression` 或重复的证明哈希列表。
- [x] 部署前确认生产内容表没有文件节点和 BLOB 数据，然后直接建立最终表结构。

### 写入流程

- [x] WebDAV PUT 和网页普通上传继续边接收边写受限制的临时文件，同时计算完整文件 SHA-256 和原始大小。
- [x] 命中现有 BLOB 时删除临时文件，只在事务内新增或切换节点引用，不生成分块。
- [x] 未命中时从临时文件顺序读取 `1 MiB` 原始分块，逐块计算哈希、尝试压缩并写入 `dav_blob_chunks`。
- [x] 跨用户所有权证明直接复用分块原始哈希，不再额外保存一份重复的证明哈希列表。
- [x] 写入 BLOB 元数据、全部分块、节点引用和引用计数必须在同一事务中完成；任意一步失败则整体回滚。
- [x] 请求取消、超限、数据库忙或压缩失败时立即停止后续分块并删除临时文件，不能留下半成品 BLOB 或孤儿分块。
- [x] 同内容并发上传继续由 `UNIQUE(content_hash, original_size)` 决定唯一 BLOB；唯一约束失败的一方回滚自己的分块并复用胜出记录。
- [x] 压缩和数据库写入采用有界顺序流水线；单请求最多同时持有一个原始分块、一个编码分块和必要的哈希/压缩缓冲。

### 读取、Range 与 HTTP 压缩

- [x] 新增顺序 `ChunkReader`，按 `chunk_index` 查询单个分块，校验元数据后按需解压，并通过 `io.Reader` 向上层输出。
- [x] 普通 WebDAV GET、下载和预览统一复用 `ChunkReader`，关键大文件路径不拼接完整 `[]byte`；文本编辑 API 仍在上限内显式读取字符串。
- [x] Range 以原始文件偏移计算首尾分块，只读取命中的分块并裁剪边界字节。
- [x] Range 响应固定输出 identity 内容，不叠加 `Content-Encoding: gzip`，`Content-Range` 和 `Content-Length` 均以原始字节计算。
- [x] 公开资源客户端接受 gzip 时，将 `ChunkReader` 的原始字节流写入单个 `gzip.Writer` 流式响应；混合的 `none/gzip` 存储分块不能直接拼接为一个 HTTP 内容编码。
- [x] gzip 动态响应不预先缓冲计算长度，可省略 `Content-Length` 并使用流式传输；保留 `Vary: Accept-Encoding`。
- [x] `HEAD` 返回与对应 GET 一致的类型、ETag、缓存和协商头，但不为动态 gzip 响应伪造压缩后长度。
- [x] ETag 继续基于完整原始内容，不因分块压缩结果或响应编码变化。
- [x] 读取期间若缺块、块序号不连续、解压失败、块哈希不符或累计大小不符，停止响应并返回完整性错误。

### 删除、引用与修复

- [x] 单文件删除、覆盖、目录递归删除和用户注销先删除节点或切换引用，再按实际节点引用重算受影响 BLOB。
- [x] BLOB 仅在 `ref_count=0` 且 `NOT EXISTS dav_nodes` 时删除；删除 `dav_blobs` 后由外键 `ON DELETE CASCADE` 删除全部 `dav_blob_chunks`。
- [x] 引用计数变更、BLOB 删除和分块级联删除必须位于同一事务，不允许先提交节点删除再异步删分块。
- [ ] 完整性修复增加：孤儿分块、缺失分块、重复/跳号分块、分块计数漂移、累计大小漂移和块哈希错误检查。
- [ ] 修复任务可以删除无主孤儿分块，但对“有节点引用且缺块”的 BLOB 只标记损坏并告警，不能静默删除用户节点。
- [x] 删除大文件不逐块发起独立事务；依靠单次 BLOB 删除和数据库外键级联完成。

### 并发与资源约束

- [x] WebDAV PUT/COPY/GET、网页上传和动态 gzip 共用进程级重型传输并发上限，避免缓冲和 SQLite 事务同时堆积。
- [ ] 一个重型传输按 `4–6 MiB` 峰值预算：原始分块约 `1 MiB`、编码分块约 `1 MiB`、SQLite/驱动复制约 `1 MiB`，再预留 gzip、哈希和响应缓冲。
- [ ] 若为文件传输单独预留 `100 MiB` 内存，从内存角度可支持约 `12–16` 路重型传输；首版默认限制为 `8` 路，给 Go 运行时、瞬时复制和 SQLite 写竞争保留余量。
- [ ] 纯 identity 下载可在压力测试后放宽到 `16` 路，但上传、动态 gzip 和混合流量仍遵守 `8` 路重型传输上限。
- [ ] 如果 `100 MiB` 是整个 BookStark 进程的总内存上限，而不是文件传输专用预算，则默认并发应降为 `6–8` 路，并以部署环境基线内存实测结果为准。
- [x] 所有循环读取、压缩、写入和响应都检查 `request.Context()`，客户端断开后尽快释放数据库游标、gzip 对象和临时文件。
- [x] 大文件操作不在数据库写事务内执行网络读取；事务只覆盖最终节点/BLOB 写入和一致性窗口。
- [x] 保留单文件大小、用户配额和公开文件大小限制；公开文件被覆盖时同样重新校验公开大小上限。
- [x] 使用临时文件作为上传背压边界，不建立跨请求内容缓存。

### 测试与验收

模型测试：

- [x] 覆盖 `0`、`1`、`1 MiB-1`、`1 MiB`、`1 MiB+1` 和多分块文件。
- [ ] 覆盖全可压缩、全不可压缩以及压缩/原始混合分块，读取后字节和完整 SHA-256 一致。
- [ ] 覆盖分块缺失、顺序错误、大小漂移、哈希损坏和 gzip 损坏的检测。
- [x] 覆盖同内容并发上传、跨用户复用、覆盖失败回滚和请求取消无残留。
- [x] 覆盖删除一个引用后内容仍可读、删除最后引用后元数据与全部分块同时消失。
- [x] 覆盖目录递归删除和用户注销，确认不存在孤儿 BLOB 或孤儿分块。

协议与响应测试：

- [x] GET/HEAD、完整下载和跨分块 Range 已自动回归；其余 Range 变体由 `http.ServeContent` 标准实现覆盖。
- [x] `Accept-Encoding` 包含 gzip、`gzip;q=0` 和不支持 gzip 的响应已覆盖。
- [x] 公开压缩内容、ETag 和 `304` 行为已覆盖。
- [ ] Finder、Windows WebDAV 或 CLI 客户端上传、断线重试、下载和覆盖大文件。

性能与数据库测试：

- [ ] 使用至少 `100 MiB` 的可压缩与不可压缩文件做上传、下载、Range、公开读取和删除回归。
- [ ] 执行多客户端并发大文件传输，确认进程内存峰值由“并发上限 × 固定分块缓冲”决定，而非文件总大小。
- [x] 使用空 WebDAV 文件库初始化最终表结构，确认应用密码和系统配置不受影响；生产库在部署前再次检查。
- [x] 运行 `go test ./...`、WebDAV 定向 race 测试和 `go vet ./...`；生产库 `PRAGMA integrity_check` 在部署阶段执行。

验收条件：

- [x] WebDAV 大文件关键路径不存在 `io.ReadAll` 或整文件 `[]byte` 聚合。
- [ ] 单连接处理 `100 MiB` 文件时，Go 堆内存不会接近文件大小，且取消请求后能回落。
- [x] 读取任意合法 Range 最多解码覆盖该范围的分块，不扫描完整文件。
- [x] 删除最后一个引用后，`dav_blobs`、`dav_blob_chunks`、公开映射和节点均无残留。
- [x] 最终实现只有分块存储和分块读取路径，不保留整文件 BLOB 回退代码。

### 实施与两轮评审记录

- [x] 第一轮评审：修复中断或超限 PUT 提交半文件、请求级并发未覆盖网络接收、单并发槽位 COPY 嵌套等待，以及下载期间删除最后引用导致后续分块消失。
- [x] 第一轮回归：新增中断 PUT、未知长度超限 PUT、单槽位 COPY 和删除期间快照读取测试，定向测试通过。
- [x] 第二轮评审：修复排队请求沿用旧并发设置、公开文件覆盖绕过公开大小上限，以及公开读取未验证 BLOB 元数据。
- [x] 第二轮回归：完整 `go test ./...`、`go vet ./...` 与 WebDAV 定向 `-race` 均通过。
- [x] 生产部署前确认内容库为空，并固定覆盖备份主库与 WebDAV 库。
- [x] 生产部署后执行数据库完整性、跨分块 WebDAV PUT/GET/Range/COPY/DELETE 和公开资源 gzip/Range canary，临时数据已清理。
