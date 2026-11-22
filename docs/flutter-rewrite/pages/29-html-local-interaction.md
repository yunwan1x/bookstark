# 29 本地 HTML 交互预览（v5，实现前设计）

原型：`../../prototypes/flutter-rewrite-2026-11-04/29-html-v5-local-interaction.png`。沿用v4浅蓝背景、蓝色操作、Flutter标题/标签/源码与预览导航；浏览器仅承担HTML正文渲染。三个状态分别为交互页面、本地附件选择、明确点击后的外部链接确认。实现前先保存本图和本文，不改变当前68be服务器新建验收快照。

## 用户行为

本地已保存HTML页保留轻量预览，并新增交互预览，显示本地身份和资源说明。正文内的JS按钮、CSS、图片与DOM变化真实运行。正文外的导航、资源管理和外部链接确认均为Flutter组件。新建未保存及未知提交核对继续轻量只读预览，避免在核对过程中执行脚本。

底部本地资源入口显示绑定数量，资源选择面板列出此笔记允许使用的图片、样式、脚本等附件；应用后重新加载预览。取消保持原绑定。资源不存在、读取失败或改动必须有实际状态；不能用演示图替代。原型中的书本/计数器是验收用HTML内容，并非产品硬编码正文。源码仍为用户原始字节/换行，不为预览而改写数据库正文。

用户明确点击HTTP(S)外链时，Flutter确认展示实际地址，再调用系统浏览器；取消保持当前DOM。自动跳转、弹窗与脚本发起的外部打开不触发系统浏览器。文件路径和预览内部地址不交给外部应用。错误、空资源、窄屏/200%文字与返回均需可用。

## 运行边界与实现方向

本地预览不能复用带服务器认证的正文运行环境。沿用独占浏览器租约的所有权和退出屏障，先关闭前一个运行实例并清理认证状态，再开启本地预览；先通过实际Cookie隔离验证才允许接入。候选方案为Android专用WebView PlatformView，Flutter保留全部操作外壳。加载随机实例来源下的只读文档和白名单资源，原生拦截提供响应及CSP响应头；关闭直接文件/内容URI访问、网络加载及原生JS接口，不把本地数据库路径暴露给网页。

资源只从应用拥有的附件库读取，校验归属/规范路径/大小后复制到本次预览私有缓存。原生仅访问随机实例的白名单副本，所有路径只解码一次并核对规范路径，拒绝目录穿越、符号链接和未选择资源。清理只移除预览副本，不能影响原附件。应用异常退出后的残留副本须下次启动清理。资源绑定设计以新增独立表保存，不重写原14表数据；具体迁移版本须待现有附件模型分析后确定，不在本文提前宣称已实现。

实际需要验证HTML中的内联/本地脚本、CSS导入、图片、相对路径、DOM事件和重载。CSP及网络开关要对fetch/XHR/WebSocket/Beacon/嵌套文档/自动跳转实际验证，不能只凭设置名称断言隔离。相机/麦克风/定位/下载等运行时请求、Activity重建和后台返回是验收门槛。高级嵌套页面/worker等能力未验证时不得称全部HTML能力完成。

## 验证

先复用现有真实SQLite升级基线，证明原ID、14表原列/值、2文档和5附件不变。资源取消/绑定/移除/丢失/冲突、私有缓存异常退出清理、路径归属和读取上限用有意义的仓库/控制器测试验证。Android仅NAS redroid，APK仅arm64-v8a。交互验收使用真实按钮连续增加计数、原CSS/图片加载、重载恢复初始状态、外链取消/确认，并独立记录隔离测试端点的请求计数。测试后清理自有fixture，不更改生产服务。不以单元测试替代实际WebView行为，也不以本页通过替代全部45组完成。

## 图片生成记录

使用imagegen技能与内置image_gen工具，模式：新图/ui-mockup。默认原图：`/root/.codex/generated_images/01a1a01d-fa4f-7bb0-9828-fa0c61e29065/exec-ab2f3e45-336d-4c1b-8457-af27eb05d70b.png`。项目图已保存上方路径，本机副本`/vol1/1000/wy/output/bookstark-flutter/round3/design/29-html-v5-local-interaction.png`，已检查三屏内容与文字。

最终提示词：

> Use case: ui-mockup. Asset type: BookStark Flutter Android rewrite prototype, page 29 v5 local interactive HTML preview. Generate one polished landscape UI design board with THREE large Android phone screens side by side, all readable Chinese typography, white background outside phones, pale periwinkle #f1f5ff app background, restrained deep blue #3d5bd9 primary actions, rounded white cards, Material style icons, modern practical reading app. Consistent top bar on all screens: back arrow, title 'HTML 笔记', subtle saved status '已保存', overflow icon. This is a realistic implementable app prototype, not marketing. Screen 1: title '我的交互页面', chip '本地空间', tabs '预览' selected and '源码'; segmented options '轻量预览' and selected '交互预览'. A small info row '本地交互预览' with folder icon, '使用此笔记的本地资源'. Main white HTML content panel shows heading '今天的阅读', a small book illustration thumbnail, '阅读打卡' and a working-looking blue button '已读 3 次' with plus icon; below a neat small progress meter and caption '每次点击增加一次'. Footer toolbar '本地资源' with paperclip and count '2', refresh icon '重新加载'. Screen 2: same page dimmed behind a clear bottom sheet heading '本地资源', helper '选择这篇页面可以使用的附件'; two rows with checked boxes and file icons: 'cover.png' subtitle '图片 · 128 KB', 'theme.css' subtitle '样式 · 2 KB'; third row '添加附件' with plus; bottom blue button '应用并重新加载', secondary '取消'. Screen 3: same interactive page dimmed behind a centered rounded dialog heading '打开外部链接？', body '将在浏览器中打开此地址。', one monospaced domain label 'https://example.org', horizontal buttons '取消' and blue '打开浏览器'. At top outside phones, title '29 · 本地 HTML 交互预览' and tiny subtitles under each phone '交互页面', '本地附件', '外部链接'. Keep layouts clean, generous spacing, no decorative gradients, no impossible controls, no developer code or implementation jargon, no passwords or credentials, no watermark. High fidelity, clear crisp text, all phones full height visible.


## 当前实现选择与验证界线

v14源码已新增独立资源绑定表及notes永久删除触发器，普通软删除/还原不移除绑定。绑定包含节点ID、网页内路径及用户已确认的内容哈希，原文件移动可跟随原节点，删除后同名新文件不能继承旧审批。实际读取使用既有LocalDriveRepository的私有blob边界和有界流，再核对摘要；资源配置更新先验证全部文件，再在SQLite事务中核对完整绑定基线并原子替换。正文、标签和原文件元数据不因绑定而改写。

已选择内存资源传输方案，而不是上文候选的磁盘预览副本：Flutter传入有界不可变字节，原生只响应当前随机HTTPS来源的白名单路径及CSP响应头。没有文件路径传入WebView；没有本轮私有缓存目录需要恢复或删除。单资源5MiB、32资源、总20MiB；原文5MiB，片段包装另允许16KiB，原始数据仍不改写。预览退到后台关闭，回来后明确重新加载；旧回调以租约隔离。Cookie接受在本地预览期间关闭，认证预览接入前先退出本地实例。

Flutter已接入本地轻量/交互模式切换、资源面板、外链确认和重新加载。资源面板可从本地文件库选择或从系统文件导入，并设置网页内相对路径。导入本身将文件保存在本地文件库，勾选并应用才改变当前笔记绑定；取消不改原绑定，说明文字明确导入文件仍保留。新建未保存、未知结果及冲突核对仍不运行脚本。页面外壳为Flutter，原生WebView仅呈现用户HTML正文。

真实SQLite资源仓库及兼容测试32项通过；资源UI/模型/租约17项相关回归通过，包括真实文件导入、取消、外部更新后的重新确认、窄屏200%文字。早期原生组件仅做过ARM64编译探测，尚未安装验证运行；当前仍在收紧生命周期组件测试，随后完整构建与redroid验证。不将此源码与68be/799项已归档服务器检查点合并，也不提升固定下载包。


## 首轮原生发现与后续修订

fb40112f/560输入/完整821项/双Web/ARM64已独立归档，实际v13→14升级保留原14表原列和值、2文档、5附件。真实本地资源选择后，JS/CSS/SVG全部加载，坐标点击计数实际达到3；外部探针代码执行后TCP连接仍0。但虚拟显示嵌入没有输出正文DOM无障碍节点，原生脚本不能按语义定位正文，故该候选不验收、不提升固定下载包，诊断与截图另存。首次底部工具条定位因尚未滚动超时，后续只继续导航，不重复资源写入。探针Android控制链观察到TCP连接，但nc控制适配未形成HTTP请求；目标隔离指标采用更严格的连接计数0，不伪称HTTP阳性。

后续源码改用Android混合嵌入，本地与认证浏览器正文均支持内部滚动手势。按v5将正常本地预览的保存状态移到AppBar、标题与本地标识合并，移除重复说明；新增可用的更多菜单，窄屏/200%文字使用上下模式按钮和标题布局，避免按钮文本落到可点击区域之外。未知保存、冲突及丢回执已观察状态仍保留原详细说明，不伪造保存回执。上述更改及两项页头/窄屏回归不属于首轮fb归档；相关12项回归已通过，接下来单独完整构建和原生复验。


混合嵌入候选1147b25f（561输入/完整823项/双Web/ARM64）及冻结4组浏览器已归档，redroid实际恢复正文DOM节点，JS/CSS/SVG、语义点击计数3、取消配置、手动重载、Home后台关闭、外链取消均通过。认证混合预览也实际读到服务器认证成功且JS不可读令牌。外链确认独立浏览器收到TCP/HTTP阳性；快速关闭外部浏览器返回时发现Flutter可能未收到paused事件，旧运行时仍活跃，故此候选不验收。后续源码在跳转前await关闭租约，测试在原逻辑上复现关闭顺序失败，修订后11项通过；将另建824项候选，不覆盖1147证据。远端认证验证初次错误使用绝对0断言，实际探针保留此前明确确认浏览器的1次请求；只续读验证计数未增加，未重放登录/创建。
