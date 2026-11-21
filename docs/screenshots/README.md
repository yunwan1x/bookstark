# README 界面截图

这些 PNG 均为实际运行界面的浏览器截图。知识管理与主题截图使用独立的本地演示数据库；`extension-*.png` 拍摄自公开站点的 HTML 工具页面，没有使用生产账号的私有内容或凭据。

- 拍摄版本：`4ea6ed0`（包含六套主题）。
- 桌面视口：1440 × 1000；手机视口：390 × 844。
- `theme-*.png`：同一演示首页的六套主题。
- 其余图片：笔记、文章、书籍、编辑器、专题、书签、待办、公开广场、创作工具、AI 面板及手机界面。
- AI 截图展示真实面板，不包含模型生成的回答。

更新时请继续使用独立演示数据，以相同文件名替换对应截图，并检查 [项目首页](../../readme.md) 的图片和说明。

## HTML 扩展案例

- 拍摄日期：2026-11-21；桌面视口 1440 × 1000。
- 覆盖 Craft 系列、国内电视直播、世界电视、街机游戏厅和 WebRTC 会议室。
- 来源链接见 [extensions-sources.json](extensions-sources.json)。第三方工具资源独立于 BookStark 主程序发布，不能仅凭主程序提交号确定其版本。
- 截图展示真实运行界面；未伪造 AI 回答、通话参与者或直播画面。会议图为进入房间前的界面；国内直播图为 CCTV-1 综合频道实际播放，世界电视图为美国 Biz TV 实际播放。两张直播图均在确认视频有尺寸、未暂停且播放时间持续增加后截取。
- 更新截图时等待工具资源加载完成，不能使用加载中或错误页面；工具自身的示例与欢迎界面可以保留。

## 书签与浏览器扩展

- 拍摄日期：2026-11-21；独立本地演示数据库，使用 demo 账号。
- `bookmarks-overview.png`、`bookmarks-search.png`、`bookmarks-site.png`、`bookmarks-bulk.png`：实际总览、组合筛选、同站查询与批量操作，桌面视口 1440 × 1000。
- `bookmarks-plugin-settings.png`、`bookmarks-plugin-save.png`：实际安装的 Linkding 扩展 1.15.1，连接本地演示服务；设置页令牌遮盖，收藏表单在独立扩展页拍摄。
- 扩展来自 [sissbruecker/linkding-extension](https://github.com/sissbruecker/linkding-extension) 的 Chrome 分支，第三方扩展不随本仓库分发。
- 已验证实际保存与兼容接口查询，完整范围见 [书签与浏览器插件指南](../bookmarks-and-browser-extension.md)。

## 访问统计与管理员后台

- 拍摄日期：2026-11-21；本地独立演示数据库，1440 × 1000，冰川青蓝 HUD 浅色主题。
- `admin-analytics.png`：`/admin/dashboard`，7 天趋势和最近访问；数据库中预置演示日汇总和记录，由真实页面及 API 渲染，不代表生产流量。示例 IP 使用文档保留网段 `192.0.2.0/24`，另含本地浏览产生的 `127.0.0.1`。
- `admin-members.png`：`/admin/system` 用户管理，预置演示成员和待审核申请；未改动线上账号。
- `admin-settings.png`：系统参数，展开外观设置、收起分页设置以展示配置分组。
- `admin-data.png`：数据管理，展开导出及导入面板；未执行导入、导出、清理或线上配置修改。
- 统计口径已核对 `middleware/visit_log.go` 与 `models/visit_log.go`：限定页面范围、每日汇总、跨日 IP 累加、每个 IP 与账号组合保留最新访问。
