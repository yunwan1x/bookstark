# 29 HTML 完整预览与 Flutter 源码编辑

设计先于实现：2026-11-05保存29-html.png，复核原应用支持脚本/完整样式后保存补充原型 `docs/prototypes/flutter-rewrite-2026-11-04/29-html-v2.png` 并发送用户。当前以补充图为准；之前设计记录保存在history/29-html-before-editor-implementation.md。

## 页面与功能

页面外壳、工具栏、标题/标签、源码编辑与保存/冲突流程采用Flutter。完整HTML正文使用专用浏览器内核，保留原有JavaScript、CSS和交互；轻量模式才使用NativeHtmlPreview。不能把只支持静态排版的组件作为完整HTML功能验收。

390dp基准，外围16dp留白、圆角白卡、56dp原生顶栏、现有品牌蓝操作。标题20sp、正文14sp、源码等宽14sp/1.5行高；320dp/200%时卡片与按钮自然增高，通过滚动保持操作完整。源码具备行号、高亮、折叠、双向滚动、查找替换、撤销/重做和移动端输入。正文自身CSS优先，完整文档不改写，片段只在预览时补外壳；包装内容不得作为保存源码。

## 协议和数据保留

沿用Go /api/blogs，创建必须editor_type=html和正确note/article类型。正文UTF8上限5MiB、标题200字节；详情只返回元数据，完整HTML从固定当前服务器content/raw读取，保护内容走带CSRF的verify-password/raw，不采用任意content_url、不依据残留gzip头重复解压。保存只更新原ID的标题/正文及编辑所需密码，不改editor_type/保护；标签用专用接口保存并读取确认，空标签data:null合法。保留原换行、Unicode、脚本及标签身份。

读取前核对所属成员，读取前后核对版本/修改时间/标题/保护与标签，保存前核对完整基线。服务端无原子CAS，不能宣称消除最后检查与写入间所有竞争。冲突保留输入，展示服务器版本，明确核对后继续编辑，另外按保存才写入。未知回执不自动重发，主动读取不伪造回执；观察到正文后只继续标签，不重复正文PUT。

## 草稿、格式与浏览器会话

草稿/提交意图按服务器、成员、note/article、html格式与ID隔离；需持久化版本基线与提交阶段，重启时未完成提交恢复为未知，不能自动重试。保护内容不写普通持久化草稿，解锁密码仅在打开会话中存在。当前内存事务已实现，持久化尚待接入。

完整正文浏览器必须安装正确属性的HttpOnly令牌、固定服务器认证，并在切换账号/关闭/退出时按顺序停止旧视图、清理Cookie与存储，再启用新会话。通用WebViewCookie没有HttpOnly字段，不能直接降级认证Cookie。全屏媒体、外链/下载与权限需要实际实现和验证。

## 当前实施状态

HTML读取、保存事务、控制器、源码组件与页面外壳已实现；同轮51项和Analyzer通过，完整Go保存/回执丢失/仅标签恢复/保护空正文合约通过。源码编辑器两个上游延迟计时器生命周期问题已用最小MIT许可本地补丁修复，快速销毁回归通过。详细证据见 `../validation/2026-11-05-html-editor-validation.md`。

实际入口与Android完整正文认证已接入，NAS redroid实际完整正文CSS/JS/认证、HttpOnly/Cookie清理、普通标题保存和保护源码查找替换保存均通过。持久化草稿/未知意图恢复、新建HTML、本地类型迁移及分享/附件/保护管理功能接线仍未完成。源码canvas的可访问性、5MiB/长行/中文组合输入与软键盘仍需验证。当前不能标记29页完成，不能把组件测试当作Android实测。

## 参考

- 官方WebView：[webview_flutter](https://pub.dev/packages/webview_flutter)、[Android实现](https://pub.dev/packages/webview_flutter_android)、[Cookie类型](https://pub.dev/documentation/webview_flutter/latest/webview_flutter/WebViewCookie-class.html)、[Android CookieManager](https://developer.android.com/reference/android/webkit/CookieManager)。
- Flutter源码编辑：[re_editor](https://pub.dev/packages/re_editor)、[re_highlight](https://pub.dev/packages/re_highlight)。保留本地补丁LICENSE及来源；后续构建快照包含该依赖全部源码和补丁。
- 已复现服务端HTML回收站还原丢失格式，证据与未应用补丁见 `../backend-compatibility/README.md`；不能通过客户端猜测格式后转为Markdown保存。


浏览器阶段：681项全量测试、Analyzer及严格ARM64构建通过，a61ca9ab1e9860facfc583eb3aed936dd17f38dfefcb3690241aabb76a7f8d81与512输入（含41份vendored文件）已归档。双Web构建完成；首轮浏览器在背景设置英文场景的无障碍开启占位按钮等待失败，保留失败证据并仅修正测试启用判定，专项复验中，不能合并宣称同次26组通过。详见 `../validation/2026-11-05-html-browser-validation.md`。
