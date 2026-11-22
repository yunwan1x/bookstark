# 29 HTML 本地与新建补充设计（实现前）

图像：29-html-v4-local-create.png（imagegen 内置工具已生成并复制入项目原型目录，非CLI；已通过cc-connect发送成功）。沿用29-v2/v3的16dp间距、12dp圆角、48dp触控、淡蓝页面底和品牌蓝按钮。新建选择面板、本地源码页、服务器未知POST核对页为三种状态，不以已有编辑页替代新建恢复。

## 入口与页面

笔记/文章的新建操作先显示格式选择：Markdown和HTML。取消不创建记录、不写空草稿。HTML源码编辑沿用代码编辑器、撤销/重做、查找替换、换行保真。标题/标签及源码/预览切换遵循既有29布局。本地页明确显示本地空间和保存在此设备，不声称连接服务器；本地完整JS/资源隔离需另有实测，轻量静态预览不能伪装为完整浏览器。

本地保存是SQLite事务。v12新增notes.editor_type默认markdown，升级只加列，保留ID、原始内容、标签、collection、已删除记录、时间及全部其他表。Markdown仓库遇到非markdown内容须交给专用编辑器，不能读成Markdown后覆盖。HTML仓库只接受html类型，更新在事务中核对基线及修改版本，保存正文和JSON标签必须原子。回收站还原同一行保留editor_type；版本快照、搜索、主题和最近记录不得错误更改类型。新建失败可明确重试同一事务，不能在保存后清理草稿失败时重新INSERT。

## 服务器新建

新建请求前持久化创建意图，按服务器含路径、成员、note/article及html隔离，使用独立new命名空间，不能复用既有正ID记录。服务端无幂等创建键，POST未知结果禁止自动重发。创建结果未确认页展示保留输入，提供只读查找；候选必须逐一读完整原始HTML、类型、身份、保护和标签，摘要不是成功依据。用户查看完整只读版本后明确选择已有ID，重新读取确认没有变化，再采用。内容匹配也只能是观察，不能编造上次请求回执。候选重名、分页、超时、无结果及结果期间变化均保留意图。没有结果不允许自动判失败。

普通创建草稿可存本机，任何保护输入或密码不得落入普通草稿。保护新建及密码管理单独完成，不暂时通过隐式丢弃密码来创建普通笔记。验证输入与标签CSV边界必须发生在任何远程写入前。

## 验收

先验证SQLite11→12真实升级和原14表/2文档/5附件保持，再仅在NAS redroid安装ARM64候选。新增本地HTML→编辑→重启→同ID/类型/源码/标签→回收/还原→原Markdown未变。服务器使用独立Gofixture制造POST已应用但响应丢失，重启后只读候选/显式采用，证明没有第二次POST。未通过的完整JS、公开/分享及旧Android迁移继续保留门槛。

## 图像工具记录

内置 image_gen，透明背景false。原始输出 `/root/.codex/generated_images/01a1a01d-fa4f-7bb0-9828-fa0c61e29065/exec-214515e5-ea75-48bb-94d3-20d9ca1b1447.png`；项目保存 `docs/prototypes/flutter-rewrite-2026-11-04/29-html-v4-local-create.png`。以下为完整最终提示词：

Use case: ui-mockup. Create a precise high fidelity Android Material 3 prototype sheet for BookStark Flutter, three complete flat front phone screens side by side, Chinese interface, pale blue #F1F5FF backgrounds, white cards with 12dp radii, navy text, blue #2563EB buttons, consistent 16dp spacing, readable Chinese typography, 48dp touch targets. Screen 1: bottom sheet on notes list titled 新建笔记, two large vertically stacked choice cards: Markdown 笔记 with description 写作与阅读, and HTML 笔记 with description 代码与交互页面, simple document/code icons; background list includes 日常记录 and 我的网页. Screen 2: local HTML editor top bar 新建 HTML and blue 保存 text action, small computer chip 本地空间, status 未保存, title field 我的网页, label selector 添加标签, segmented 源码 / 预览 with 源码 selected, large syntax-highlighted line-number code editor showing <!doctype html>, <html lang="zh-CN">, <body>, <h1>我的网页</h1>, </body>, </html>. Compact editor toolbar containing undo redo search and line-wrap icons. Bottom quiet note 保存在此设备. Screen 3: server HTML create recovery page top bar 核对新建结果, amber status card 创建结果未确认 and text 请先核对服务器，避免重复创建, readonly draft title 我的网页, compact code excerpt card, outlined button 只读查找已创建的笔记, candidate card with same title 我的网页, HTML badge, source-matching green chip 内容一致, chevron to full read-only review, bottom note 选择并核对已有笔记后继续，不会自动重新创建. Do not show fake success or timestamps. Crisp product specification mockup, no perspective, no decorative illustrations, no watermark.

## 本地恢复前缀与新建去重（下一批实现前）

本地恢复使用独立 bookstark.local-html-recovery.v1 前缀，远程旧 bookstark.html-recovery.v1 键保持不变。即便规范化身份URI/成员/ID相同，本地和远程也不能读取或删除彼此记录；串行队列按前缀与作用域排序。127cded4检查点尚无此独立前缀，原型/存储URI只用于身份，不发HTTP；待该检查点清理本地测试草稿后再安装后续包。

本地新建下一版通过SQLite创建凭据表记录随机创建键、note ID、collection与输入摘要，在同一事务中插入笔记和凭据。凭据不含标题/正文/密码；笔记永久删除时凭据仍可阻止未知结果重试复活旧创建。普通创建草稿保留随机键，提交前先持久化pending；结果未知后只读查找凭据，明确核对/采用已有ID，不另插入一份。此表计划在v13引入，不能把新增表/列偷偷当作原v12快照。
