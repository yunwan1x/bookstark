# 30 · 原生表格编辑器：实施前设计

状态：原型和文档已先行；模型与原生网格/编辑基础开始实现，尚未完成整页。29本轮公开HTML检查点已归档，但29整组和全部45组仍未完成，继续保留文档/共享高级编辑、后端兼容及最终设备回归范围。

原型：`../../prototypes/flutter-rewrite-2026-11-04/30-spreadsheet-v1.png`。imagegen技能，内置image_gen默认模式；原始图 `/root/.codex/generated_images/01a1a01d-fa4f-7bb0-9828-fa0c61e29065/exec-6e307bef-98d9-415a-8503-5e93765d129f.png`；本地交付 `/vol1/1000/wy/output/bookstark-flutter/round3/spreadsheet/30-spreadsheet-v1.png`，已发给用户。图中项目预算只用于设计与测试，不能成为生产页面的假数据。

## 原始协议与兼容边界

实际旧编辑器是Univer，不是CSV或Markdown。`models/spreadsheet.go`及`static/js/univer-adapter.js`使用IWorkbookData：id/name/appVersion/locale/styles/sheetOrder/sheets；工作表包含id/name/rowCount/columnCount/freeze/mergeData/cellData/rowData/columnData等。默认1000行、26列，稀疏cellData，格式版本0.25.1。必须保留实际工作簿和工作表ID、未知属性、样式、公式及未修改单元格。不能将未识别JSON或解码错误静默转换为空表；旧adapter的这种回退不继承。未编辑不重编码原文，编辑按结构修改且保留其余字段。

现有Go按spreadsheet类型接收最多5MiB UTF-8正文。笔记/文章、书籍文档、私有/公开/密码/共享编辑必须采用其真实身份与权限，不借Markdown写接口绕过类型检查。对后续格式的API/草稿/本地数据接线逐项测试，不以只读表格或小样替代全部功能。Go博客回收站丢editor_type的既有兼容补丁仍未应用，保留独立HTTP验证/最终后端交付门槛。

## 布局和交互契约

主色#155af5，背景#f1f5ff，白色表面，细网格线#dfe5ee。顶部返回/“表格”/真实保存状态/更多，第二行实际标题及空间标识，随后撤销/重做/格式工具条。地址框B4、fx、公式输入栏；中央二维虚拟表格，行列标头、选区蓝框和操作手柄；底部实际工作表页签、添加/管理入口及选区状态。读权限页面不出现可写控件，不给空回调。已保存只在真实提交及必要回读后显示。

单元格单击选择、编辑操作进入真实输入，公式栏显示原始公式而网格显示有效计算结果。支持键盘/IME、横纵滚动、定位地址、范围、撤销重做；计算中的值不伪装为新结果。格式底部面板先编辑临时选择，取消不改变原表，应用才修改选区；粗体、斜体、下划线、字号、对齐、数字格式、文字/填充色使用真实样式。工作表管理保留ID，创建、重命名、复制、排序、隐藏和删除有实际结果；至少一个可见工作表，删除明确确认并支持已有历史规则。合并/冻结、行列操作等通过相应真实模型接线，不只画按钮。

可见单元格按需构建，不能把1000×26或更大的表一次性创建成全部Widget。行列宽高来自实际快照；大字/320dp允许工具条滚动或换行，地址/公式可操作，键盘弹出仍可提交/取消。正文例图的数据和书签名称来自fixture，生产始终用工作簿内容。

## 计算与数据安全

界面使用Flutter原生二维表格，不能用WebView套回旧Univer。已核对Flutter官方two_dimensional_scrollables具有惰性构建、固定行列及合并单元格能力，选定版本前核对当前SDK并固定版本；[官方包](https://pub.dev/packages/two_dimensional_scrollables)、[单元格合并API](https://pub.dev/documentation/two_dimensional_scrollables/latest/two_dimensional_scrollables/TableViewCell-class.html)。

公式需要实际计算及依赖传播，不能把缓存v当作编辑后的结果。先核对原格式并验证计算桥；候选为MIT/Apache许可的原生Rust IronCalc，通过受控FFI仅传工作簿数据，不传账号/文件路径。其当前API可构建模型、设置单元格及求值，但兼容性必须用测试证实，不能因为选用了引擎就宣称Excel或Univer全部兼容。[项目与许可证](https://github.com/ironcalc/IronCalc)、[当前API文档](https://docs.rs/ironcalc/latest/ironcalc/)。没有实现的公式、保护规则或资源应保留原始数据并明确只读/不支持，禁止自动清空、错误重算后静默保存；这些仍需在整组完成前补齐。

保存前区分本地事务/服务器已知回执/结果未知。未知结果不能自动重放；完整只读核对后才采用。保护内容草稿不持久化密码或明文恢复快照。使用既有提交持久化屏障/独立命名空间并测试退出清理；若新增本地schema或Native库，保留原14表原列和值及附件并扩展冻结输入/来源证明。Native库打包只允许arm64-v8a/AArch64。保留旧Android及原始数据。

## 实施顺序与验收

1. 有界、保留字段的IWorkbookData模型及地址/稀疏单元格/样式/合并/冻结/工作表语义。
2. 按原型实现Flutter虚拟网格、选区、输入、格式面板、工作表管理和撤销重做。
3. 真实公式计算桥、依赖更新、错误/循环/跨表/绝对引用及旧缓存兼容；不把stub当计算通过。
4. 私有服务器/本地读取、创建、保存、草稿、未知提交与密码接线；随后书籍/公开/共享上下文。
5. 真实Go协议与schema升级、错误/大表/边界、浏览器视觉；冻结源码/完整测试/APK后在NAS redroid运行实际ARM64包，核对安装hash/引擎及旧数据保留。每项以实际结果记录，不提前标完成。

## 最终生成提示词

Use case: ui-mockup. Create one polished high fidelity UI prototype board for BookStark Flutter Android rewrite page30, a fully native spreadsheet editor. THREE large complete Android phones side by side on a white landscape canvas. Crisp readable Chinese text, realistic Material app controls, pale periwinkle #f1f5ff page background, white surfaces, primary blue #155af5, thin light gray gridlines, restrained practical styling, no gradients or marketing art. Board title '30 · 原生表格编辑器'. Phone1 main editor: app bar back arrow, title '表格', compact check status '已保存', overflow menu. Below app bar title '项目预算' with small pencil icon and chip '本地空间'. Compact toolbar undo, redo, a clearly labeled '格式' button. Formula row address box 'B4', small 'fx', formula text '=SUM(B2:B3)'. Large editable white spreadsheet grid with column letters A B C and row numbers 1 through 12. Row1 A='项目' B='预算' C='已用', bold with light blue header fill. Row2 A='设计' B='1200' C='800'. Row3 A='开发' B='3600' C='2400'. Row4 A='合计' B='4800' C='3200', bold; B4 selected with a clear blue outline and small blue selection handle. Remaining rows blank, no fabricated values. Bottom white sheet tabs '预算' selected with blue underline, '说明', plus icon, sheet-list icon. Small bottom status '选中 B4'. Phone2 same main editor dimmed behind a large native rounded bottom sheet titled '单元格格式', subtitle 'B4'. Realistic options: bold B button selected, italic I, underline U; font size selector '14'; alignment left center right icons; section '数字格式' with radio rows '常规' selected, '数字', '货币', '百分比'; a few restrained text and fill color swatches. Bottom actions '取消' and primary '应用'. Phone3 same editor dimmed behind a native sheet titled '工作表', with selectable rows '预算' active blue check and '说明', each row has a drag handle and overflow icon. One small contextual menu anchored to the '说明' row listing '重命名', '复制', '隐藏', '删除' with delete in red. Bottom outlined action '+ 新建工作表' and primary '完成'. All three phones fully visible, clean spacing, legible spreadsheet numbers, believable touch controls and bottom safe areas. Captions beneath phones '表格与公式', '格式设置', '工作表管理'. No WebView/browser address bar, source code, developer diagnostics, fake loading states, passwords, backend details, QR codes, watermarks, extra phones, charts or decorative illustrations. This is a design specimen with example data only; the production editor must use actual workbook data.

## 实施记录（未冻结）

2026-11-06：有界保留字段模型、稀疏单元格/合并空间索引、原文不动、样式继承、工作表添加/重命名/隐藏校验；原生TableView、输入取消/应用、撤销重做、临时格式面板和工作表管理基础已实现。two_dimensional_scrollables固定0.5.5，其实际pubspec要求Dart3.11/Flutter3.41，当前3.13.7/3.47.9符合；不宣称这是最新版本。20项模型与Widget专项通过，包括百万行惰性构建/远处定位、离屏合并、320dp200%只读、样式取消和历史恢复。尚未接入生产读取/保存或新APK。计算引擎验证中，含公式快照禁止标量改写，避免缓存失效；重命名公式工作簿暂时保护，未用空回调替代。格式数字模式/工作表复制删除排序、完整历史/保护/范围/行列等继续待实现。

2026-11-06 读取检查点：26专项、完整881及Analyzer/双Web/ARM64通过，454189d1/1121输入和源码6f8fc78f单独冻结。真实host FFI2项/Rust4项、4组浏览器及表格两路、NAS redroid真实ARM64库计算/冷启动/定位/原文未改与原数据保持通过，详见../validation/2026-11-06-spreadsheet-read-validation.md。生产本地入口目前明确只读；独立计算结果不等于保存。后续编辑/计算缓存提交及类型正确的持久化控制器在新源码阶段实施，不计入此冻结包。

## 用户最新架构覆盖

2026-11-06 用户明确“所有复杂编辑器都用WebView”。本页后续改为复用既有Univer Web编辑器，原生网格/原生公式编辑计划停止扩展；上文设计/454189d1读取检查点保留为历史，不作为后续实施路线。统一容器与保存/恢复设计见后续complex-editors-webview.md。原数据、历史源代码与APK不删除；尚未验收完整编辑/保存的范围继续以WebView方式完成。
