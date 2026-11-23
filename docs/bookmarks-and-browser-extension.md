# 书签管理与浏览器插件

BookStark 将书签收藏、检索、分类和批量整理放在同一个工作台。浏览器扩展通过个人 API Token 连接同一套账号数据。

## 搜索与整理

书签页 `/bookmarks` 的关键词搜索匹配标题、URL、描述。打开筛选面板后，可以进一步组合：

| 维度 | 支持内容 |
| --- | --- |
| 标签 | AND：同时具有选定标签；OR：具有其中任一标签。侧栏可搜索标签、浏览分组。 |
| 站点 | 点击书签的站点图标，筛选同一站点的收藏。可继续组合关键词和标签。 |
| 时间 | 创建时间或修改时间；近 1 天、7 天、30 天，或自定义起止日期。 |
| 状态 | 仅置顶、仅导航页展示、仅公开、无标签。 |
| 条件管理 | 已选条件展示、移除、清空与重置。 |

示例：搜索 `Go`，AND 选择「开发」「Go」，定位学习资料；按 `go.dev` 筛选只看官网收藏；切换修改时间筛选回看近期整理的内容。搜索的是保存的元数据，不是目标网页全文；系统不会自动为所有收藏建立网页正文索引。

进入编辑模式后，可以逐条选择，或全选当前查询条件下的所有结果。批量操作包括置顶、取消置顶、添加/移除标签、公开/取消公开、导航页显示/隐藏与删除。**全选作用于筛选结果，不限于当前显示的一页**，执行前应核对选中数量和条件。

管理员可在系统管理中导入浏览器导出的书签 HTML，指定目标用户。导入时读取文件夹名称形成标签，跳过同账号中已存在的 URL。失效链接检测可协助清理长期积累的收藏，清理结果进入回收站。

## 安装与连接扩展

使用 [sissbruecker/linkding-extension](https://github.com/sissbruecker/linkding-extension)：

- [Chrome Web Store](https://chromewebstore.google.com/detail/linkding-extension/beakmhbijpdhipnjhnclmhgjlddhidpe)
- [Firefox Add-ons](https://addons.mozilla.org/zh-CN/firefox/addon/linkding-extension/)

1. 登录自己的 BookStark，在「个人设置 → API Token」创建一个令牌，例如「我的浏览器」。
2. 打开扩展配置，Base URL 填 BookStark 根地址，例如 `https://books.example.com`，不带 `/api`、`/bookmarks` 或末尾斜杠。
3. 将令牌填入 API Authentication Token，可设置默认标签。
4. 点击 Save，确认出现 Connection successful。
5. 打开一个网页，点击扩展图标或默认快捷键 `Alt + Shift + L`，填写标题、描述与标签后保存。

在地址栏输入 `ld`，按空格或 Tab 激活扩展搜索，再输入关键词；选择建议中的 URL 可直接打开收藏。默认快捷键可能受操作系统或浏览器快捷键配置影响。

### 客户端本地工作区

客户端启动并打开本地工作区后，在「个人设置 → API Token」查看并复制「浏览器插件服务器地址（Base URL）」。地址为 `http://127.0.0.1:<实际端口>`，端口由客户端首次启动时分配并保存，后续启动沿用。不要使用服务器部署的默认端口 `8089` 代替此处显示的端口。

浏览器和客户端须在同一台机器上，收藏时保持客户端及本地工作区运行。插件用该工作区创建的 API Token 连接，无需共享客户端登录 Cookie。仅书签兼容接口支持这种访问，客户端的工作区控制和其他页面仍受本地访问校验保护。撤销令牌后插件将无法继续访问。远程工作区则填写远程服务器地址，并在该服务器创建令牌。

如需取消设备的访问权限，在 BookStark 的 API Token 页面撤销对应令牌。令牌用于授权访问账号数据，请勿放入公开仓库或截图。

## 当前兼容范围与公开状态

这是 **BookStark 对 Linkding 的部分 API 兼容**，不是完整 Linkding 服务。已提供创建、查询、URL 查重、标签列表、单条读取、更新与删除接口。

| 插件字段/操作 | BookStark 行为 |
| --- | --- |
| URL、Title、Description、Tags | 保存为网址、标题、描述与标签。 |
| 重复保存同一 URL | 同账号下更新已有书签。 |
| Read later / unread 为 true | 不公开。 |
| Read later / unread 为 false 或未传 | 公开。 |
| Shared | 不决定 BookStark 的公开状态。 |
| Notes、网页快照、归档等 Linkding 专属功能 | 不应视为已兼容；本次验证不覆盖这些能力。不要依赖 SingleFile 自动上传到 BookStark。 |

**建议在扩展设置中启用 “Pre-select unread when adding bookmark”，默认将收藏保存为不公开，再在 BookStark 中决定哪些内容适合分享。** 这个映射是当前实现，不是独立的稍后阅读状态。

兼容 API 使用 `Authorization: Token <个人令牌>`。主要端点包括：

- `GET/POST /api/bookmarks/`：连接测试、关键词查询和收藏。
- `GET /api/bookmarks/check/?url=...`：检查是否已收藏。
- `GET /api/tags/`：标签建议。
- `GET/PATCH/PUT/DELETE /api/bookmarks/:id/`：读取、修改与删除。

注意以上兼容端点的末尾斜杠。关键词查询为 `GET /api/bookmarks/?q=Go&limit=5`；BookStark 网页高级筛选通过自己的接口完成，不能假定 Linkding 的全部搜索语法都适用。

## 截图与验证

2026-11-21 使用独立本地演示账号拍摄书签总览、高级搜索、同站查询、批量管理及扩展配置、收藏表单。扩展为上游 Chrome 分支 `1.15.1`，以实际扩展加载运行，未伪造保存结果。

已验证扩展连接测试成功、表单提交成功、相同 URL 更新已有条目，以及兼容接口关键词查询能返回保存后的描述。收藏表单在独立扩展页中打开拍摄；配置截图中的令牌已遮盖。此验证不代表覆盖所有浏览器版本或所有 Linkding 功能。
