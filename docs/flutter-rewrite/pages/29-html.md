# 29 HTML 完整预览与 Flutter 源码编辑

状态：实现中，全部45组目标不变。设计先于实现：主界面以 `docs/prototypes/flutter-rewrite-2026-11-04/29-html-v2.png` 为准，恢复流程以 `29-html-v3-recovery.png` 与 [恢复设计](29-html-recovery.md) 为准，两图均已生成并发送。早期设计保存在history。

## 页面与正文

外围页面、标题/标签、源码编辑、保存/冲突和恢复流程均为Flutter。正常完整HTML正文使用认证浏览器保留CSS/JavaScript交互；轻量模式及未确认结果/冲突的只读核对不运行脚本或表单。源码只作为文本编辑，不把预览包装内容保存回服务器。

390dp基准，16dp外围、圆角白卡、56dp顶栏、品牌蓝操作；标题20sp，源码等宽14sp/1.5行高；320dp/200%可滚动。源码具备行号、高亮、折叠、双向滚动、查找替换和撤销重做。re_editor0.10.0两个已复现延迟计时器的销毁问题以保留MIT许可的本地最小补丁修复；快销毁回归不靠预先排空计时器。

## 协议与原文

既有note/article资源从共享原生入口按editor_type派发，重新核对成员、集合、ID与完整基线。正文UTF8上限5MiB、标题200字节。详情只读元数据，原HTML从固定当前服务器content/raw读取；保护内容用带CSRF的verify-password/raw，不采用任意content_url，不按残留gzip头二次解压。

更新只写原ID的标题/正文及必要密码，不改editor_type或保护状态。标签专用接口写入并读取核对，data:null合法。保留原换行、Unicode和脚本。现有CSV标签接口不能表达逗号身份时明确拒绝，不能静默拆分；该限制尚待进一步兼容处理。

保存前比较基线，冲突保留输入并要求明确核对后再按保存。服务器无原子CAS，不能声称消除最后一次检查与PUT之间所有竞争。未知回执不自动重发，主动读取不伪造回执；仅在正文收到或明确观察到后才允许只恢复标签。

## 恢复与认证

普通HTML恢复记录按服务器路径/成员/集合/html/ID隔离，保留版本基线与原输入；提交意图先成功写盘才发送HTTP修改，重启恢复为未知。保护记录只有身份与摘要，不写标题、正文、标签或密码，重启需再次解锁并只读核对，确认采用当前版本前重新读取。

Android后台commit屏障覆盖恢复偏好和wrapped-key偏好；登录存储明确保持原名称，避免插件的名称缓存误定向。损坏记录不自动删除，存储失败阻止修改或丢弃输入。已确认服务器保存但本机清理失败只重试本机。

浏览器token保持HttpOnly，HTTPS分支Secure、SameSite=Lax；关闭、切换、退出按队列清空原文与Cookie/存储，旧lease不能清掉新lease。实际HttpOnly/原文CSS/JS/认证/Cookie清理均已在NAS redroid验证；本轮测试服务HTTP，不冒称实际HTTPS测试完成。

## 现有证据

- 初期编辑组件51项+Analyzer及完整Go保存/丢回执/仅标签恢复/保护空正文合约，见 [编辑验证](../validation/2026-11-05-html-editor-validation.md)。
- 浏览器检查点681项、真实Go原文/保存及NAS redroid CSS/JS/HttpOnly、原生标题/保护源码查找替换保存，见 [浏览器验证](../validation/2026-11-05-html-browser-validation.md)。
- 恢复检查点：写盘屏障前全量706项及完整Go合约；最终屏障与根登录存储修正后48项相关回归、双Web和ARM64构建；同次26组浏览器脚本通过。521输入与5b35e940开头APK归档，见 [恢复验证](../validation/2026-11-05-html-recovery-validation.md)。不将这些数字合并成最终全量710项已运行。
- 最终ARM64 APK在NAS Android14通过真实回执截断及强制进程重启：普通草稿恢复、普通未知结果只读核对、保护内容再次解锁/只读核对/明确采用都没有重发正文。独立Go回读原ID/类型/源码/标签/密码保持，实际退出后冷启动不恢复旧登录；旧14表、2文档、5附件字节保持。宿主x86_64使用native bridge，非物理ARM。

## 未完成门槛

HTML创建、本地类型迁移、公开/分享HTML、附件/保护管理、外链/下载/全屏媒体/权限和Activity/返回重认证仍待接线；完整冲突版本查看、继续编辑后的草稿补写、同资源多路仲裁待补。源码硬件End键、中文组合输入、长行5MiB及可访问性仍需实际验证。不能标记第29组完成，也不提升固定下载APK。

服务端回收站还原丢editor_type已真实复现，隔离验证和历史缺字段策略仍待处理，见 [后端兼容记录](../backend-compatibility/README.md)。不能凭内容猜测后把HTML转成Markdown。

## 参考

- [webview_flutter](https://pub.dev/packages/webview_flutter)、[Android实现](https://pub.dev/packages/webview_flutter_android)、[Android CookieManager](https://developer.android.com/reference/android/webkit/CookieManager)。
- [re_editor](https://pub.dev/packages/re_editor)、[re_highlight](https://pub.dev/packages/re_highlight)；快照包含本地依赖完整源码、LICENSE与补丁。
- [Android写盘语义](https://developer.android.com/reference/android/content/SharedPreferences.Editor)。


## 2026-11-06 本地HTML检查点

v12/127cded4已通过完整727项及NAS redroid实际迁移/编辑/重启/草稿/回收站验证，原数据保持仅加类型列；详见 ../validation/2026-11-06-local-html-validation.md。新建原型v4及文档已先保存并发送，后续v13新建页/凭据恢复继续实施，不属于127包。本地完整脚本运行及其他29门槛仍未完成。


## 2026-11-06 本地新建检查点

v13/bf2beb0b完成753项、双Web、ARM64和实际redroid新建/冷启动/草稿强停/永久删除验证；详见 ../validation/2026-11-06-local-create-validation.md。未知创建结果的故障注入目前为单元及组件证据，服务器新建与本地完整脚本等仍待完成。


## 2026-11-06 服务器新建检查点

68be1e32/550输入/完整799项/双Web/ARM64与实际redroid服务器新建、真实POST丢回执强停恢复、保护冷启动/完整只读复核/采用/退出及原数据保持通过，详见 ../validation/2026-11-06-server-create-validation.md。本地交互预览v5图和文档已先保存，后续源码将与本包区分。29及全部45组仍未完成。
