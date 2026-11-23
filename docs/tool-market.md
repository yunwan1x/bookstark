# 工具市场

## 发布和安装是两个独立步骤

HTML 文章设为公开、无访问密码后，作者在编辑页点击「发布为工具」。市场只显示主动发布的工具。文章标题、简介和当前 HTML 作为发布内容存入 `md_tool_releases`；发布端保留原有静态资源引用，不下载、不打包、不复制资源。

编辑文章不会自动改变已发布内容。点击「发布更新」覆盖当前发布内容并生成新修订号，包括只有资源变化的情况。没有发布历史或回滚副本。「下架工具」停止新的安装和更新，不删除安装者已经下载的内容。

安装时，安装端从发布内容解析并读取实际静态资源，将当前 HTML、安装信息和结构化使用数据写入主数据库 `md_tool_installs`，将资源写入内置 WebDAV 的安装专属目录，并将静态引用改写为安装端地址。资源下载失败则安装失败，原安装保持可用；不会悄悄退回原文资源地址。

本地客户端工作区使用设备上的 SQLite 和内置 WebDAV。在工具市场「工具来源服务器」输入发布端的 HTTP(S) 根地址即可浏览并安装远端工具。来源服务器及工具 ID 按当前账号映射，不与本地文章 ID 冲突。在远程工作区操作则保存到当前远程服务器，不会自动写入设备本地工作区。安装需要登录安装端；浏览当前服务器公开目录无需登录。

## 静态资源和动态服务

安装器支持 HTML 图片、srcset、脚本、样式、图标、海报、静态音视频和字幕；递归处理 CSS `url()` / `@import`、JS 的字面量模块导入及 `new URL()` 资源，以及普通 import map。相同 URL 在一次安装中只下载一次，内置 WebDAV 按内容去重。

内联 data URL 保持内联。HLS/DASH 播放清单、运行时 API 等动态服务继续联网。运行时拼接生成的资源地址无法静态推断；需要改为明确的静态引用才能安装。带 scopes 的 import map、转义依赖地址会明确拒绝安装，应改为明确模块 URL。外部 CSS/JS 重写后会移除原 HTML 中不再匹配的 integrity 属性。

单资源上限 20 MiB，整套下载上限 100 MiB、最多 256 个资源；另受 WebDAV 文件大小和账号配额约束。网络下载检查实际连接 IP 及重定向，不携带登录凭据，不允许访问回环、内网和元数据地址。当前服务器的公开上传、WebDAV 公共资源和 `/static/` 通过公开处理器读取。跨服务器来源需使用公开可访问地址。

安装后的资源通过随机安装实例和资源实例组成的只读地址提供给隔离 iframe；响应不使用缓存，带沙箱、CORS 和禁止嗅探头。资源 URL 是持有即可读取的能力链接，应避免公开转发。卸载或更新后旧资源地址失效。代码通过父页面加载到无同源权限的 iframe，不能直接读取宿主登录信息。

## 存储及清理

- `md_tool_releases`：作者当前发布的代码及描述，不包含资源副本。
- `md_tool_installs`：账号的当前安装、gzip 编码的 HTML、修订号、安装实例和使用数据。
- `/BookStark/tools/<安装实例>/assets/<资源实例>/`：真正下载的当前版本静态资源。
- `/BookStark/tools/<安装实例>/data/`：该工具产生的用户文件。
- IndexedDB 不保存工具安装、代码或使用数据。

更新先准备完整资源，成功后切换数据库中的当前代码和资源路径，再清除旧资源。失败或中断留下的临时资源登记在持久化清理队列中，重试或打开管理页时回收。完成后只保留一个当前版本，不提供历史备份或回退。更新保留使用数据和 `data/` 文件。

卸载删除安装记录、代码、使用数据及整个安装目录，没有「保留数据」选项。重新安装使用新实例、空数据。清理失败返回「资源清理未完成」，不会假报成功；重试继续清理。共享 BLOB 按引用计数释放，不删除发布端原文件或其他安装仍在使用的内容。SQLite 释放页由后续写入复用，不在每次卸载时执行全库 VACUUM。

## HTML 工具数据接口

iframe 的 `localStorage` 通过受控消息桥保存到安装端数据库，单工具结构化数据上限 5 MiB。通过下面的接口写入安装端 WebDAV：

```js
await BookStark.files.write('exports/report.txt', '报告内容');
await BookStark.files.write('images/result.png', imageBlob);
const bytes = await BookStark.files.read('exports/report.txt');
const text = new TextDecoder().decode(bytes);
```

支持字符串、Blob、ArrayBuffer 和 TypedArray。文件路径不能越出工具数据目录。写操作验证修订号和安装实例，旧窗口不能修改重新安装后的工具。数据保存失败可重试或导出未提交数据，不使用离线队列重放已经卸载的工具写操作。

原生 IndexedDB、Service Worker 和依赖外部身份的 API 仍需工具自行适配。同一工作区同一账号可以跨浏览器使用；本地工作区与远端工作区是独立存储。

## 验证

- `go test ./controllers ./internal/toolpackage -run 'TestTool|TestStaticDependency|TestDependency|TestImportMap|TestMarketPackage'`：独立发布、草稿隔离、资源实际下载和重写、移除源资源后读取、更新失败保留旧版、旧资源回收、远端关闭后本地可读、账号隔离、卸载清空、下载边界。
- `BOOKSTARK_BROWSER_TEST=1 go test . -run '^TestToolMarketBrowser$'`：安装运行、跨浏览器保存、WebDAV 文件、静态脚本及模块实际执行、源资源删除后运行、发布/下架、移动端入口、多主题和双语布局。
- `node --test tests/browser/tool_market_worker_test.cjs`：安装、来源、资源缓存边界和离线重放隔离。
