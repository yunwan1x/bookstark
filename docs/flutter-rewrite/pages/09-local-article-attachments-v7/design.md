# 本地 Markdown 文章附件 v7

实施前原型：[local-article-attachments-v7.png](local-article-attachments-v7.png)。2026-11-10 使用内置 imagegen 生成，提示词保存于 prompts.json。延续已验收共享文章的紫色栏、分离的编辑/预览标签及格式栏；Flutter负责原生弹窗、附件操作和状态，正文仍是既有CM6/Cherry WebView。

## 页面与状态

390×844dp基准；16dp边距，12dp组间距，44dp以上触摸区，10–12dp卡片圆角。紫色#6530ad，背景#fcfaff，浅紫选中态，深蓝正文。顶栏“本地文章”，返回、附件和保存；标题/本地空间/保存状态单独卡片。键盘弹出时保持同一编辑器并显露光标，320dp和200%字号允许外围滚动。

原生附件底部弹层含“从设备导入”“插入公开链接”“取消”；系统选择器取消不写文件不改正文。导入成功后按当前快照选区插入真实应用附件引用；图片可在既有引擎预览中显示。附件行显示真实文件名、大小和打开操作。读取失败显示琥珀提示，正文和引用保留，可重试、复制链接。原型中的周末阅读计划、leaf.png、植物照片、128KB和“测试内容”都是演示数据，产品必须绑定真实内容，不能硬编码样例。样例leaf.png在实际源码中使用既有bookstark-attachment URI，不改写已保存正文。

## 数据和能力边界

复用LocalAttachments、LocalDataPaths.attachments、同一LocalDataMaintenance及既有Native文件选择器。文件保存在应用私有附件目录；名称仅作显示，文件身份是随机ID。只通过AttachmentRepository读写，WebView不获得文件路径、file/content权限或账户。导入/插入/保存分别确认，不能把文件导入成功显示成文章保存成功。正文保存仍使用现有精确快照、加密恢复和事务核对。选文件期间后台退出，晚到结果不能插入已退休编辑器；已导入文件保留，不擅自删除用户资源。

本地图片资源仅可读取严格合法的应用附件URI，限定可识别栅格图片、单图5MiB/总20MiB/32资源；不得借HTTP、file、content、路径穿越或符号链接读取其它位置。只在独立本地Markdown工厂/租约启用资源，不能扩大通用复杂编辑器或公开工厂能力。资源在退休时取消；不透明预览继续无Native桥、无connect/frame/form/worker权限。公开链接可插入文本；远端图片默认不自动联网，错误提示不泄露文件路径。不声明附件加密或本地密码保护已实现。

## 实施及回归门槛

先连接现有本地文章和新建后打开路径，保持普通note原生及其附件行为。补测取消、准确选区、编辑期间结果晚到、大小/类型/URI/符号链接拒绝、字节边界、生命周期、BOM/CRLF和未知保存不重放。复用Go引擎做浏览器真实预览/隔离回归；只构建ARM64，并在NAS redroid完成系统选择器导入/取消、图片预览、实际SQLite回读及附件字节/哈希核验，原数据每轮精确恢复。原型视觉对照和交互测试分别留证，不用自生成golden宣称与原型逐像素自动一致。

所有45组尚未完成；本页在实现和实际设备回归完成前保持“实现中”。固定26安装包和旧源码/APK不替换。


## 原型后的引擎兼容说明（实现中）

真实Cherry探针确认其URL处理器会过滤自定义scheme。保持原文bookstark-attachment引用，只在本地不透明预览的beforeImageMounted回调中映射到本次随机源的专用图片路径；Native仅该独立工厂把严格校验后的路径交回同一附件仓库。不是HTTP服务器，也不读取任意路径。普通代码块和导出源码不改写。浏览器需证明真实图片、原文精确与隔离，Android另行证明Native读取。系统文件选择前先确认快照、结束旧运行时；选择返回时仅相同原文可按快照选区创建新的工作副本，正文已变则保留可复制链接。取消恢复原工作副本，不写文章SQL；进程退出不伪造成功。

## Android 原生流式选择补充

检查已固定file_selector_android源码确认其new byte[size]在Dart接收前分配全文，因此默认本地文章导入改用独立原生ACTION_OPEN_DOCUMENT通道：内容URI仅在Native内使用；64KiB缓冲复制，声明大小/实际流双重64MiB上限、取消/120秒复制截止与磁盘余量检查，落到随机ID的私有临时收件箱并fsync。Dart只接ID、文件名、长度和SHA256；根据系统私有缓存目录解析该ID，流式校验后交原有附件仓库复制，最后释放临时副本。普通笔记与原备份通道保持原有API。预先冻结v7-r1未打包，完整测试因该修正主动中止，不作为通过证据；新源码须另行冻结与完整检查。

## 大字体错误状态补充

320dp、200%字号下，导入失败说明与图片错误同时出现的额外回归在v7-r2精确复现底部200px溢出。附件版外壳将标题/状态/错误放入有高度上限的Flutter滚动信息区，正文平台视图始终保持同一个带键Expanded父节点；为正文保留随字号增加的140–280dp空间。普通尺寸保持原型自然高度，窗口不足时优先隐藏底部附件卡片，仍可通过正文和附件入口处理。这个修正另行冻结，旧2487项全量属于v7-r2，不提前归为新源码验证。

### Android WebView compatibility
Native C3 regression discovered local image mapping failing on WebView125 while desktop succeeds. Parse only the fixed bookstark-attachment triple-slash URI grammar in presentation callback, without relying on URL.pathname for non-special schemes; retain single filename decoding, all bounds and invalid-path rejection. Do not alter stored source or vendored Go engine assets. Browser regression also disables custom-scheme URL parsing to exercise this boundary. New APK/native acceptance required.

## 原型视觉复核补充
C4真机正常组通过导入、实际PNG预览和明确保存冷重开，视觉复核另发现本地模式未显示原型中独立编辑/预览标签，紫色顶栏继承了深色标题。后续版本为本地文章启用同一既有分离标签布局，预览隐藏格式栏，并显式使用白色顶栏文字。保留C4功能证据，不将其提前标为最终视觉验收。小屏异常测试应先进入目标页面再切换320dp/200%显示，避免通用登录导航未滚动导致未到被测页面。

## 大字体附件卡片高度修正
C5正常/异常设备功能通过，但320dp200%真实截图发现底部附件副标题超出卡片。新增控件边界回归在修复前复现20dp越界。附件区高度随字体从96dp增加到136dp，同一高度参与正文/标题信息区预算，保持字号及文件操作，不以缩小文字隐藏问题。原C5功能证据保留，并明确视觉未验收；后续设置页版本须同时回归该修正。
