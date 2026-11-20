# 广场新闻

广场默认进入新闻 Tab。浏览器只读取本地缓存的标题、纯文本摘要、来源与发布时间，不请求外站 RSS、正文、图片或视频。原文在新标签打开来源网站。摘要可保存到已有书签，支持中英文界面、语言/分类/来源筛选、搜索和分页；左侧通过 AJAX 更新，电台和时钟持续保留。无编辑精选。

## 管理

系统管理 → 新闻源：

- 新闻源管理：来源搜索、分类/语言/仓库/状态筛选、批量启停、分类语言编辑、错误详情、单源重试。
- 同步设置：每行填写 GitHub 仓库、分支、OPML 路径及该文件对应的分类和语言。推荐使用分类 OPML。保存后定时任务由服务器执行；手动任务使用已保存配置。
- 新源默认待启用，导入后按需求启用。上游移除只标记，保留来源和历史新闻；停止自动抓取。部分文件同步失败时不将其已有源标记为移除。
- 同一 RSS URL 合并并保留多个仓库引用。管理员分类、语言和启停不被同步覆盖。删除一个清单配置仅停止同步该文件；如需停止抓取，应停用其新闻源。

默认仓库：

- `alan-turing-institute/ai-rss-feeds` / `main` / `feeds.opml`
- `xiangyugongzuoliu/awesome-rss-feeds-list` / `main` / `feeds/cn-ai-tools.opml`
- `xiangyugongzuoliu/awesome-rss-feeds-list` / `main` / `feeds/en-ai-research.opml`

默认周期为清单 24 小时、新闻 30 分钟、文章保留 90 天；全新安装的定时开关默认关闭，管理页可启用。过期清理保留被书签引用的新闻。时间使用浏览器本地时区显示，计划时间由后端计算。

## 获取与安全

- RSS 2.0、Atom 和 RSS 1.0；每个源最多读取 8 MiB、每次最多处理前 300 条，摘要最多 700 字符。
- 最多 4 个并发请求，单请求 20 秒、单任务 12 分钟。失败指数退避，手动单源重试绕过退避。
- 支持 RSS ETag / Last-Modified 条件请求。所有内容入库后复用，浏览次数不会增加远端抓取次数。
- 按条目标识和原文 URL 去重；缺失/异常未来日期回退为抓取时间。展示原标题，不自动翻译。
- XML 内容严格解析，摘要去 HTML、脚本与媒体。仅公网 HTTP(S)，禁止凭据、非常规端口与私有/回环/链路本地地址；DNS 地址在连接时校验，重定向同样校验。
- 所有配置、源编辑和任务 API 需要管理员权限；采用现有认证和 CSRF 中间件。任务和配置写入互斥，避免覆盖正在执行的同步。
- 最新 100 个任务留存数据库，管理页显示最近 20 个；程序重启将未完成任务标记中断。

## 验证

- `go test ./services ./controllers -run '^TestNews' -count=1`
- `BOOKSTARK_BROWSER_TEST=1 go test . -run '^TestNewsWorkspaceBrowser$' -count=1`
- `BOOKSTARK_BROWSER_TEST=1 go test . -run '^TestPublicWorkspaceBrowser$' -count=1`

浏览器测试使用临时数据库与模拟 RSS 网络，不修改生产数据。
