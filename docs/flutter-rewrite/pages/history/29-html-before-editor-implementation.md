# 29 HTML原生预览与源码编辑

2026-11-05 先保存原型 `docs/prototypes/flutter-rewrite-2026-11-04/29-html.png`，三个状态为原生预览/源码切换、标题与HTML源码编辑、服务器版本冲突核对。后续实现遵循蓝白圆角视觉，字段与操作使用原生Flutter；大字号/软键盘时整体滚动，不使用WebView。

## 协议与边界

Go /api/blogs 创建/读取/更新，editor_type=html，blog_type为note或article。HTML正文UTF8上限5MiB，与Markdown500KB不同。列表对HTML不返回完整正文，必须读取详情；原有RemoteNotesRepository会拒绝非markdown，不能绕过类型检查后误用Markdown保存。保留blog_id、blog_type、editor_type、版本/修改时间、标签与保护状态，不悄悄转换格式。

预览只把解析后的HTML结构映射为Flutter文字、列表、表格和安全链接；不执行script/style脚本、事件属性、iframe、表单、对象和自动外部网络请求。不宣称完整浏览器CSS/JS兼容；正文清晰提示样式差异。源码完整保留，不因预览过滤而重写服务器HTML。超出支持范围的结构给出说明与源码入口，不能显示空白后宣称还原。

链接由用户明确点击才处理，沿用既有安全来源导航，不把私有cookie转给外站。图片需要实际当前服务认证与尺寸/字节边界；未实现前显示可理解占位，不暗中请求远程追踪资源。

## 保存与恢复

编辑草稿按空间/成员/blog_type/editor_type/ID隔离，原本Markdown草稿不覆盖。读取真实版本作为基线，保存前重新核对；冲突保留用户输入，允许看服务器版本，再次明确核对后覆盖。未知写入不自动重发，仅主动读取比较内容；已保存回执与实际读取分别呈现。新建回执丢失不猜测ID或重复创建。密码保护内容与草稿沿用已建立的安全策略，不写普通持久化草稿。

## 回归

实际Go HTML创建/读取/修改/5MiB边界、标签/原格式/保护状态与并发冲突；脚本/表单/外链不执行或自动请求，原始HTML逐字保留；原生预览结构与切换不丢输入；窄屏中英200%/键盘、主列表与全局搜索真实路由、Android实际操作及升级数据保留。目前原型/协议已保存，尚未实现。


## 2026-11-05 功能范围复核与后续修订

原网页 HTML 预览使用允许脚本的 iframe，支持 JavaScript 和浏览器样式；仅将 HTML 转为 Flutter 静态排版不能保持既有功能。先前“不使用 WebView”和“脚本不执行”的静态预览方案不足以作为完整页面验收。已向用户提供选择；未收到新偏好时按保留原功能推进：页面外壳、工具栏、源码编辑器与保存/冲突流程使用 Flutter，完整 HTML 正文采用专用浏览器内核，既有原生静态预览可作为轻量模式。正式正文实现前需先补充对应原型图，不能把现有静态组件视为整页完成。

目前新增 `BookstarkClient.blogHtmlSource`：只构造当前服务器固定 `/api/blogs/:id/content/raw`，受保护内容走带 CSRF 的 `/verify-password/raw` POST；不采用元数据里任意 URL。正文按解压后的 UTF-8 5 MiB 限制读取，拒绝重定向、错误 MIME/字符集和无效 UTF-8；传输层已解压时不得依据残留 gzip 头再次解压。请求有取消与总时限，不持久化密码或正文。协议测试与原有 API/下载测试共同执行；完整仓库、编辑器路由、持久化草稿与真实 Go HTML 合约尚待实现，不能据此宣称页面已完成。


补充原型已保存为 `docs/prototypes/flutter-rewrite-2026-11-04/29-html-v2.png` 并发送用户：左侧为完整交互预览与轻量模式切换，中间为 Flutter 源码/标题/标签编辑与草稿状态，右侧为版本冲突核对。实现以此图为准，保留旧图用于设计演变记录。正文浏览器选型参考 Flutter 官方插件 [webview_flutter](https://pub.dev/packages/webview_flutter) 与 [Android 实现](https://pub.dev/packages/webview_flutter_android)；全屏媒体、权限、外链与会话清理需要分别实现和实际验证，不以基础 WebView 展示替代功能验收。

新增真实服务契约 `flutter_app/tool/html_source_contract.dart` 已在独立 Go 测试实例通过：大于 Markdown 上限的压缩 Unicode HTML、脚本源码逐字匹配、受保护正文直接 GET 为403、带首尾空格密码的 CSRF 解锁、修改后实际原文回读以及 HTML 类型/保护状态不变。新增源接口与旧 API/下载回归13项通过；全量测试另外执行中，尚不能记录全量通过。


后续读取模型已实现 `RemoteHtmlNotesRepository`：当前成员身份、HTML 类型与 note/article 集合检查，原文读取前后版本/修改时间/标题/保护状态核对，以及标签二次核对；检测到变化拒绝混合基线。Go 的无标签 `data:null` 已通过真实服务发现并兼容，缺失或错误标签响应仍拒绝。会话变更、关闭与非法密码不继续读取。新增仓库7项与原文接口5项定向测试通过，真实 Go 完整模型读回也通过。此前原文接口版本完整636项和Analyzer通过；仓库及新依赖加入后不是同一轮636项证明。官方 WebView 依赖固定4.14.1，锁文件核对所有既有包版本未变化；正文组件与Android运行验证尚未完成。


## 下一阶段具体界面约束

补充图以390dp宽为基准：外围16dp留白、16dp圆角白卡、56dp原生顶栏，主要按钮使用现有品牌蓝；正文/源码切换与底部编辑操作保持可触达。标题20sp粗体，正文14sp，源码等宽14sp、行高1.5；大字号允许按钮和卡片自然增高，320dp/200%时通过滚动显示完整操作，不能硬裁切。完整预览显示真实HTML/CSS/JS，轻量预览复用NativeHtmlPreview并明确当前模式。HTML正文自己的字体和样式以源文档为准，不能为了匹配原型覆盖用户内容。

新增 `html_preview_document.dart` 对完整文档原样返回，片段参考原编辑器添加viewport与基础样式；服务器normalize样式地址保留部署前缀。源码中的script、事件、doctype、base、CSS保持原文，包装内容只用于展示。新增3项测试与Analyzer通过，该后续文件不属于已归档455输入的0b79bcdd候选包，尚未接入实际正文组件。

源码编辑器需要保留行号、语法高亮、双向滚动、查找替换、撤销/重做与移动端输入；不能用一个普通文本框就声称覆盖原CodeMirror功能。可考察官方 [re_editor](https://pub.dev/packages/re_editor) / [re_highlight](https://pub.dev/packages/re_highlight)，尚未加入依赖；必须验证中文IME、表情/组合字符、软键盘、可访问性、5MiB与真实ARM64运行表现后才能选定和验收。

完整预览需要接入现有服务认证，并在切换账号/退出/关闭时清理专用浏览器会话与存储。官方通用 [WebViewCookie](https://pub.dev/documentation/webview_flutter/latest/webview_flutter/WebViewCookie-class.html) 未提供HttpOnly参数，不能把服务端HttpOnly token直接降级成脚本可读Cookie；应使用 [Android CookieManager](https://developer.android.com/reference/android/webkit/CookieManager) 等正确属性的桥接方式，并验证旧视图停止后才安装新会话、异步清理顺序、私有资源认证和token不可被脚本读取。该桥接尚未实现，不能把新增WebView依赖视为认证正文已接通。
