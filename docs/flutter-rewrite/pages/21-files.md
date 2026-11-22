# 21 网盘 / 内置 WebDAV：实施前设计

2026-11-04。原型 `docs/prototypes/flutter-rewrite-2026-11-04/21-files.png` 已在UI实现前生成并发送。其他独立页面（文本编辑、文件预览、上传、文件操作/公开设置）各自先出图和文档再写页面。状态：设计中，不将图片库或旧WebView当作本组完成。

## 页面与视觉

白色AppBar：返回、网盘、刷新、更多。背景#f8fafc、正文Slate#0f172a、主色#2563eb，16dp边距、8dp圆角、48dp点击。容量卡→面包屑→“搜索当前目录”→实际文件夹/文件数与名称排序→懒加载目录项→上传文件FAB。目录项只展示实际名称、大小、时间、类型、公开状态，未知值显示未知。搜索只对当前已读取目录，不能说全盘检索；Go没有目录分页，列表数量来自实际数组。排序目录优先、名称/大小/时间切换；返回目录恢复滚动，系统返回优先回父目录，根目录再退出功能。变更目录/筛选时陈旧异步结果不能覆盖当前页面。读取失败不能伪装空目录，刷新保持可见旧数据并明确错误。

容量来自 `GET /api/webdav/profile`：usage.stored_bytes / usage.quota_bytes。**按每用户引用blob去重压缩后大小统计，不是逻辑大小、全服务器磁盘占用，也没有计费功能**；logical_bytes、compression_saved_bytes、deduplicated_bytes可在容量详情按原字段展示，不做错误相加。file_count/directory_count为全空间；目录列表计数仅当前目录。quota<=0按后端含义不限额，不显示0B容量或伪百分比。file_max_bytes、公有文件上限来自真实设置。连接地址和账号仅支持查看/复制，本组不提前放入未实现的应用密码按钮（27单独实现）。

## 权限和真实路径

Go `controllers/local_webdav.go`、`models/webdav_store.go`、`static/js/webdav.js` 为依据。这里的“LocalDAV”是服务端内置网盘，按登录member隔离，**不等于Flutter本地空间**。API路径值是相对用户根目录的JSON字符串，根为""；URI查询只编码一次。文件名含%与Unicode保持原样，不把JSON路径当URL重复解码；拒绝..、反斜线、控制字符和客户端根逃逸。不发送外站登录凭据，不跟随重定向。file.type是真实dir/file；节点ID稳定，路径随重命名变化。页面身份同时绑定空间、目录、ID，切换空间取消在途传输并关闭预览。

列表 `GET /api/webdav/files?path=` 返回数组，通过BookstarkClient包裹data读取。节点字段id/name/type/path/mime_type/etag/size/stored_size/mode/is_public/public_path/create_time/mod_time。无虚构子目录条目数；mode不冒充可编辑权限。没有单节点详情API，canonical核对通过父目录真实列表 + ID/路径；etag是内容SHA256而非mtime。

## 写操作与不确定结果

新建目录POST `/mkdir` {path,name}。重命名/移动POST `/rename` {path,new_path}，复制POST `/copy`同字段；目标完整相对路径，禁止复制/移动到自身子目录，源/目标存在冲突显示真实错误。两者拒绝同名目标，不伪装自动改名。DELETE `/api/webdav/files?path=` 会递归永久删除目录，**不进入回收站**，确认框明确目录全部内容和不可撤销；引用文件的笔记可能失效。批量逐项处理，失败保留、不确定先核对，无静默重发。

POST multipart `/upload` 的file/path，写同名文件会覆盖原节点和内容；实际上传前先列目录核对，并让用户明确选择覆盖/改名/跳过。同名行分别有队列ID，不因文件名折叠。上传源单项流式读取/哈希，大小受服务端设置，发送字节完成不表示落盘成功。网络/取消后如提交可能完成，先列目录核对目标etag/hash，不自动POST。文件读取中变化不能用旧hash冒充验证一致。

**POST `/upload/check` 并非只读**：调用者已引用同一blob时立即LinkDAVBlob到目标路径，可创建/覆盖文件；跨用户返回持有证明nonce/chunk_size/chunk_indices/token，`/upload/prove`验证SHA256(nonce+chunk)后也写目标。不能将其放在文件选择时、预览时、只读“检查”按钮或未经覆盖确认的步骤。证明token单次使用/5分钟有效；失败不自动重新提交写入。若本组采用完整上传通路而暂未做持有证明加速，明确其为待补功能，不冒称所有闭环完成。

## 编辑、预览、下载、公开

内容GET `/content` 返回path/content/etag/mime_type，但Go把任意bytes转string可损坏二进制；原生文本编辑应先按有界原始download严格UTF-8解码，拒绝无效UTF8/NUL等二进制，不默默替换。保存PUT `/content` {path,content,content_type}是覆盖写，空字符串也是真实清空；客户端预读etag冲突需比较/另存/明确覆盖，保留草稿。旧Go没有If-Match原子条件写，预读不能保证并发无覆盖，作为后端待验收门槛，不作虚假保证。

下载/preview同源认证GET，Go支持ServeContent Range、ETag；preview返回private/no-store、nosniff、CSP。图片复用NativeImage/InteractiveViewer与SVG约束；PDF必须原生PDF渲染，音视频必须原生播放器，HTML显示纯文本/源码或后续29原生受限预览，不能iframe/WebView执行任意内容。大文件下载流式写临时文件，取消/失败清理未完成文件，分享真实完成文件。原始下载不得改写字节或伪造完成；系统保存/分享失败或取消不记录成功。不要将凭据嵌入公共URL，私有媒体预览应限定同源认证与请求取消。预览缓存、离开清理、进程终止残留恢复列入45。

公开POST `/public` {path,public_path}返回asset和真实url；只在明确确认后提交。公开无需登录，可保留缓存，覆盖文件会维持公开地址并更新etag；重命名不等于取消公开。取消公开DELETE `/public?path=`后刷新真实状态，不承诺已缓存副本删除。公开路径冲突/大小超限/失去权限显示真实错误，复制只复制canonical服务器地址。文件菜单还包含详情、打开、预览、下载/分享、文本编辑、重命名、复制/移动、永久删除；每个入口在对应能力真正接好后才出现。

## 本地空间与验收

Flutter本地文件空间独立于附件目录及服务端DAV数据库，存储在应用私有目录；不能扫描NAS数据树、系统文件或上传本地附件。旧Android内置GoDAV导入属44，不能拿新目录可用声称迁移完成。文件名/路径边界、同名覆盖、目录递归删除、符号链接隔离、容量真实计算、失败回滚与重启恢复必须验证。若本地文件公开不可用，只展示该空间实际支持的操作，不放无效“公开”按钮。

验收包含仓库协议测试、真实Go私有数据集CRUD/覆盖/去重/Range/公开与取消/权限、真实FS本地边界与失败恢复、编辑冲突/草稿、传输取消与未知结果核对、原生PDF/音视频/图片、每屏中英320dp/200%字体与键盘、原型截图对照，以及真实Android回归。各项缺失继续保留实现中，绝不使用静态fixture作为生产数据。

数据层进展：已实现路径/文件/容量/UTF8模型、RemoteDriveRepository、分块源指纹与持有证明、可取消认证Range响应。基础13项与分块源5项测试通过；真实Go目录CRUD、上传/owned hash linking、覆盖保护、去重容量、稳定ID移动/复制、BOM/CRLF/空编辑、过期基准拒绝、Range/If-Range、显式公开/取消已通过。发现真实Go mkdir回复path为空，按最小回执id/name/type校验后再从真实父目录列表取得canonical节点，不按请求捏造路径。状态进入实现中，尚未接入生产页面，固定APK仍为20快照。

本地仓库实施细化（实现前）：新增SQLite11表保存稳定node_id/逻辑path/类型/实际大小/hash/MIME/时间/不可变blob_key，物理文件使用应用私有独立drive-blobs目录与生成的blob名称，不按用户路径拼接物理文件。目录改名/移动/复制只在一个SQLite事务更新逻辑树，复制得到新ID、移动保持ID；事务唯一path约束保护同名。上传/编辑先写私有临时blob并完成hash校验/flush，再原子重命名发布blob，SQLite引用成功后才报确认；失败保留旧引用/旧文件，待回收的新blob不能成为可见节点。删除逻辑树在SQLite事务完成后才允许回收无引用blob；回收失败可重试，不能把已删除误报未删除。启动恢复在数据库事务内核对未引用blob/临时文件，避免与另一写事务的发布窗口竞争；所有blob访问拒绝符号链接且根目录必须真实私有目录。流下载返回已打开的只读handle与真实长度，严格处理Range/IfRange，关闭订阅释放handle。文件内容必须来自实际FS，不用SQLite BLOB模拟文件下载；容量本地不伪造压缩收益，按独立实际blob字节计算。提供真实FS+SQLite失败注入、重启恢复和ID/路径/源变动/符号链接测试后再接根本地空间。此段是后续实现方案，尚无LocalDriveRepository，不宣称SQLite11已升级。
