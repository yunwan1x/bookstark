# 29 HTML 恢复交互补充设计

先生成原型 `docs/prototypes/flutter-rewrite-2026-11-04/29-html-v3-recovery.png` 并发送用户，再实现新恢复入口。使用 imagegen 技能内置图像工具（非CLI）。延续29-v2的淡蓝底、深色文字、品牌蓝、16dp间距、12dp圆角与48dp触控。

1. 离开未保存页面：底部面板显示“返回前确认”，三项纵向操作：继续编辑（主按钮）、保留草稿并返回（描边）、放弃修改（中性）。保护正文无保留普通草稿项；未知提交仅允许保留核对记录或继续核对，不能把未知当作失败直接重发。保存本机记录失败不退出。
2. 受保护内容重启恢复：先解锁读取当前服务器版本，再进入“核对服务器版本”只读页。琥珀状态卡、保护提示、标题与只读标记、预览/源码切换；核对预览使用不执行脚本/表单/资源请求的原生只读组件，源码可完整查看；确认进入正常编辑后仍使用完整认证浏览器。底部固定“采用当前版本开始新编辑”和“不会重发上次提交”。操作再次确认、重新读取核对页面所见版本未变化后，才移除旧摘要标记并进入新的编辑；当前数据观察不能伪装为旧请求回执。
3. 普通未知提交：恢复原基线、原输入和未知状态，默认禁止编辑/保存；可查看“你的草稿”与打开时读取的“服务器版本”，显式“只读核对服务器”后才能确定后续只保存标签或进入冲突。保留核对记录可返回，不自动提交。

普通草稿与提交意图的存储键隔离服务器（含路径）、成员、note/article、html与ID。正常草稿保留原始换行和完整基线；保护记录仅有身份、摘要和pending，无标题、正文、标签、解锁密码。跨页面/存储实例排序，避免迟到写入复活被放弃的草稿。写意图成功后才允许HTTP修改；重启不恢复成“已收到回执”。已确认保存但清理本机失败只重试本机操作，不能重发正文。

320dp/200%：底部面板和正文均可滚动；固定底部按钮自然换行；源码区域双向滚动。恢复设计不能替代组合输入、长行、可访问性和实际redroid验证。

## 最终图像提示词（内置工具）

Create a polished high fidelity Android UI prototype sheet for BookStark Flutter app, three complete phone screens side by side on pale neutral background. Chinese interface. Flat front view, crisp readable typography, no perspective. White rounded cards, very pale blue #F1F5FF page background, blue #2563EB primary buttons, navy text. Screen 1: HTML source editor with top bar 编辑 HTML, title 输入与记录, status 未保存, line-number syntax highlighted HTML code, and bottom modal titled 返回前确认, explanatory text 尚有未保存的修改, three actions 继续编辑 / 保留草稿并返回 / 放弃修改. Screen 2: dedicated read-only protected HTML recovery screen top bar 核对服务器版本, amber status card 上次保存结果未确认, small lock icon note 受保护正文未保存到本机, title 我的交互笔记, segmented 预览 / 源码, clean rendered note body with heading 阅读记录, muted read-only tag 只读, fixed blue bottom button 采用当前版本开始新编辑, small gray explanatory note 不会重发上次提交. Screen 3: restored normal HTML editor top bar 编辑 HTML, amber status 正文保存结果未确认, compact two cards 你的草稿 and 服务器版本 with short excerpts, blue outlined button 只读核对服务器, secondary 保留核对记录并返回, code area locked until verification. Match contemporary Material 3 mobile UI; consistent spacing 16dp, rounded corners 12dp, touch targets 48dp. This is a precise product prototype for implementation, no illustrations, decorative branding or English marketing text.

## 恢复边界补充（实现前）

继续编辑或拖动关闭返回面板时，立即保存最新普通草稿，避免取消防抖后遗失修改。未知提交核对后若发现服务器冲突，仍保留 pending 意图；只有明确接受已核对的新基线才转为普通草稿，不能通过放弃修改抹除未知提交记录。冲突离开面板沿用保留核对记录操作。

## 完整版本查看（实现前）

沿用 v3 核对页的淡蓝底、只读标记、预览/源码切换。草稿和服务器版本卡片增加箭头，点击进入完整只读快照页，显示原始标题、逐个标签与全部源码；标签中的逗号仍属于同一个标签。预览不执行脚本，不加载远程资源，不提供提交或采用按钮。返回保留原有冲突状态。截断摘要不能替代完整版本核对。

## 未改变标签的保存（实现前）

已读取 Go UpdateBlog：只有非空 labels 字段才调用 RebindLabels，正文请求不传 labels 会保留原关系。原标签未变化时只提交正文并读回确认，不调用 CSV 标签替换，不编造标签回执；原有含逗号标签可保留。改变标签时仍严格检查 CSV 可表示性，不能把一个含逗号标签拆成多个。正文回执已收到而最终读取失败时进入等待核对，而非标签待保存。

## 同资源编辑入口（下一批实现前）

同一服务器（含路径）、成员、类型及ID在一个进程内仅有一个活动HTML编辑/恢复入口。第二次打开使用简短提示，不读取或覆盖草稿，不创建第二控制器。租约延续到页面实际销毁，退出过渡期间仍生效；取消解锁/恢复及错误路径释放，旧页面迟到释放不能影响新租约。只读快照页属于现有编辑页面，不另开编辑入口。
