# 09 文章完整 WebView 模块 v1（实施前）
2026-11-09。用户明确文章类型使用WebView，本阶段替换远程主文章列表/编辑整模块，不继续扩展原生文章列表/Markdown正文。普通笔记Markdown仍原生，所有复杂编辑器遵循既有WebView覆盖范围。离线本地文章与搜索/主题/分享/恢复等其它文章入口列为后续必做，不能据主入口宣告全组完成。

## 原型
先保存四状态原型，再改代码。draft图编辑态误画为HTML富文本；已请求第二版改成现有CodeMirror HTML源码、既有Go密码框文字，以免为还原假原型发明另一套编辑器。以最终v2图为实施基准，draft保留不覆盖。原型示例标题/封面/时间均为合成数据，正式从服务器实际页面获取。
Flutter只保留应用导航和连接异常处理；搜索、过滤、分页、新建、文章设置/分享、编辑/预览、保存/撤销及类型工具栏由已有Go页面和原Web引擎负责。主蓝#0B57EE、浅底#F7FAFF、深字#0C192E、16边距、48触点。HTML采用源码编辑/预览；不把HTML伪装成富文本编辑器。

## 已核对的真实协议
现有Go /notes?tab=articles&type=article、/blogs/:identify/edit?mode=edit|preview&from=...；AuthRequired接受token Cookie，写API沿用csrf_token Cookie及对应请求头。client已有exportSession，Native保持token HttpOnly。原Web界面支持七类编辑器和自己的保存/草稿行为，不引入另一条Native正文保存路径。
现有默认HtmlBrowserSession每次clear WebStorage会破坏Web端IndexedDB草稿，不能把只读预览直接拿来当编辑模块。因此计划采用AndroidX WebKit1.16中已有的独立Profile，每个规范server+member生成稳定非明文profile标识，CookieManager/WebStorage与默认预览分隔。仍借用现有排他租约先关闭上一个浏览器，防止路由/会话迟到回调恢复旧内容。
官方API依据： https://developer.android.com/reference/androidx/webkit/WebViewCompat#setProfile(android.webkit.WebView,java.lang.String) 与 https://developer.android.com/jetpack/androidx/releases/webkit （Profile隔离从1.9提供；本项目已有1.16依赖）。运行时必须验证MULTI_PROFILE，不伪装为支持。

## 生命周期、权限与附件
退出/账户切换只清理自己拥有的会话Cookie和运行时，不误删其他账户的Web草稿，不调用默认profile全局清库。Web原有草稿语义需真实冷启动核对；与第44组只读原密码无磁盘持久化是不同边界，不混合证据。原网站的密码处理行为要明确验证，不能额外把密码写入Flutter配置。
文章模块获得安全窗口后才装入认证页面。后台隐藏/暂停Web运行时，正常系统SAF附件选择允许Activity暂停，不能再出现误取消；恢复前检查client/账户/租约仍匹配。退出/换会话销毁并等待自己的Cookie清理。返回遵循网页历史/现有未保存提示，不能悄悄丢弃编辑。
文件选择复用系统SAF，限定本次请求的内容URI和数量；不开放任意file/content导航。导出必须覆盖实际HTTP/Blob下载和SAF确认、大小与摘要校验；没有实现的能力不得留空回调声称完成。JS对话框、外链、认证失败、SSL错误、滚动/键盘/中文输入均需回归。
同源/prefix规范与根路径API/资源必须核对；Go原页大量使用根相对URL，不能假定配置prefix后会自动工作。离线/失败呈现原型连接卡片；重试与连接设置执行真实回调。

## 验证与剩余范围
数据/路径/会话的宿主测试，真实Go隔离fixture检查新建、编辑、标签、保护、附件、删除/分享、所有格式和原字节；冻结源码/全量测试/ARM64-only，再NAS redroid真实整模块/键盘/文件/导出/后台与换账户。不得使用Win11模拟器、不得改生产服务或原数据。每个Nativecase保留失败与恢复证明。
本地文章整模块WebView、其它来源入口、远程非文章复杂格式、44激活/保护恢复/备份15/rawDB、45及1–34缺口仍在总目标内。

原型已校正并保存：09-articles-webview-v2.png 为最终基准（HTML CodeMirror源码、已有“该博客已加密/确认”文案）。V1 draft保留，仅作弃用草案。已通过Android官方Profile API核对，本项目现有AndroidX1.16可用；运行时能力还须真机验证。后台先隐藏并暂停当前WebView以保留既有网页内存和Web草稿，回来验证会话再恢复；这与第44组保护副本“销毁并重解锁”的独立流程不同，不混同承诺。离开/刷新必须处理网页未保存提示，主导航也需同一离开屏障，Cookie清理等Native关闭完成后再换账户。


## Implementation checks before Android acceptance

The remote main article entry now uses ArticleWebPage and its Android named-profile container. Local article entries and other cross-module article openers remain pending; this does not complete the whole article migration. The same native element stays mounted beneath transient connection errors so an error message cannot destroy the Go draft. Constructor events defer until the current Flutter frame completes. Leaving to an app route waits for the existing Go save-status check and native retirement. Backgrounding pauses/hides this owned view and resumes only the current scope.

34 targeted Dart tests passed (scope/session/export/widget); complete analyzer passed. Android compileDebugKotlin passed before the final request adapter changes; final frozen build and ARM64 NAS redroid validation remain required. Real Chromium checks preserve POST/PUT/XHR/FormData bytes under a custom server prefix, rewrite native form submit, handle detached export anchors followed by immediate object-URL revocation, preserve BOM/Unicode/CRLF and reject an oversize blob before streaming chunks. Disposable real Go backend browser checks loaded seven article editor types, verified an actual HTML save through the raw-content endpoint and found the protected-password gate. Browser checks are not Android proof or seven-type edit/save acceptance.

The Go editor continues its existing password-cache and localStorage/IndexedDB draft contract within the server/member profile; do not apply migration44 readonly guarantees to this editor. FLAG_SECURE is acquired before account cookies or password input. No protected screenshot is captured. Native visual evidence must respect that protection.


## Android cache alias correction (before V2 code)

Actual target-UID Java instrumentation found cacheDir.absolutePath under /data/user/0 while getCanonicalPath resolves under /data/data. Available capacity and write/fsync/chmod all passed. The V1 download root compared an unnormalized trusted context path with its canonical form and rejected this legitimate Android alias before reading the Blob. V2 canonicalizes the trusted Activity cache directory first, then creates the owned export root beneath that capability. Existing root/job/file symlink and ownership/receipt/hash checks remain. Add a Dart regression for a trusted cache reached through a symlinked ancestor, distinct from a symlink at the export root or job/file, which stays rejected. Actual protected edit/save passed in V1 but image SAF remains unaccepted pending this fix and the new frozen build.
