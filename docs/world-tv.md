# 世界电视订阅与自动拉取

入口：系统管理 → 电视直播 → 世界电视（`/admin/system?tab=tv&tvtab=world`）。
央视 / 卫视沿用已有设置；世界电视展示订阅频道，支持名称搜索、国家/地区筛选、来源链接和浏览器试播。网页来源和 HTTP 流显示打开来源入口；媒体不经过服务器代理。

## 配置与执行

- 管理员保存公网 HTTPS M3U 订阅地址、启用开关、6/12/24 小时间隔。
- 配置、上次执行/成功时间、错误和下次执行时间存入 SQLite `md_settings.world_tv_state`。
- 每 30 秒检查到期任务；服务重启后保留计划，到期任务自动补跑一次。关闭页面不影响任务。
- 立即拉取使用已保存的配置；同一进程内仅允许一个任务运行，拉取期间修改配置返回 409。
- 成功或失败后按配置间隔安排下次尝试，避免失败时连续请求上游。
- 请求超时 60 秒，列表上限 8 MiB/20,000 个频道；空列表、非法内容和默认源少于 100 个频道均不发布。
- HTTPS 请求在实际连接时检查并固定公网 IP，重定向重复检查，不使用环境代理。
- 根据 `tvg-id`（缺失时为国家/分组/名称）生成稳定频道 ID，与旧 Python 更新器兼容。保留首次出现的同 ID 频道。

频道文件仍位于 `data/uploads/worldtv/channels.json`，以同目录临时文件、fsync、rename 原子发布。现有 `/upload-files/worldtv/channels.json` 地址不变，响应使用 `Cache-Control: no-store`。拉取失败保留成功文件；ETag/304 保留频道并更新时间。上游地址变化时不复用旧 ETag。

## 旧任务迁移

首次初始化时，如果此文件存在、含频道且来源为原 Free-TV/IPTV 地址，自动接管原有每 6 小时计划，并沿用最近检查时间；全新安装默认关闭自动拉取。已有数据库配置优先，不会重新开启管理员关闭的任务。

生产迁移步骤：

1. 备份 compose 文件、旧 `worldtv-sync.timer` / `.service` 和频道文件；检查旧 service 已完成。
2. 停用旧 timer，然后使用仓库 `deploy.sh` 发布新版本；如部署失败，恢复旧镜像与 timer。
3. 核对已迁移配置、公共列表、手动拉取以及新计划；验证线上世界电视文章仍能读取列表。
4. 移除旧 systemd 单元并 daemon-reload；保留更新脚本与备份供回滚，不再执行。

当前部署为单实例。多副本部署前需引入数据库任务租约，不能让多个实例共用此任务。

## API

均位于管理员鉴权及 CSRF 保护之下：

- `GET /api/admin/tv/world`：配置、执行状态、频道列表。
- `PUT /api/admin/tv/world`：`{source, enabled, intervalHours}`。
- `POST /api/admin/tv/world/pull`：立即拉取并返回最新状态和列表。

## 验证

`go test -race ./services/worldtv` 覆盖解析、稳定 ID、失败保留、ETag、迁移、到期执行、停用、重启、并发与地址安全。

`BOOKSTARK_BROWSER_TEST=1 go test -run '^TestWorldTVBrowser$' .` 在隔离数据库和文件目录中验证管理员页面、鉴权、CSRF、XSS、筛选、保存/刷新、拉取失败保留、试播生命周期、原频道页回归与移动端布局。Node 需能够加载 Playwright。
