# 17 小结Markdown编辑（实施前设计）

原型17-summary-editor.png。复用既有NoteEditorPage的同一状态机、原生Markdown预览、工具栏、附件插入/分享/取消、草稿队列与生命周期保存，通过明确contentEditorTitle配置正文编辑模式。保留文档编辑布局中的上下文行、编辑/预览、工具栏、正文和底部草稿提示；隐藏不属于小结的标题输入与标签。主题标题和manual/ai类型作为上下文，不写入正文。20000 Unicode码点上限在本模式前置验证，API层再次验证，不能沿用笔记UTF8标题限制去截小结正文。

新增SummaryEditorRepository适配真实TopicsRepository；save只调用小结接口，保留原topic_id/summary_type/order_sort，create返回真实summary_id以便失败重试不重复新建，不写/api/notes或blogs。读取核对所属主题；空Markdown不提交，类型不改变。草稿namespace包含服务/owner/topic/summary，不能串到普通笔记或其他主题的新建草稿。明确恢复/放弃，附件共享原有安全访问能力。

保存仍留在编辑器，可继续修改，返回详情须重新读取真实摘要/计数。生成AI输出只作为未提交正文打开本页，保存之前不得调用summary POST；若已有ai小结修改，type保持ai。更新共享编辑器后必须回归原笔记/文章/文档的标题、草稿、附件与预览，不能因新增模式改变旧布局。320dp中英200%字体与键盘整体滚动，原型中的工具栏宽度不足则Wrap，避免横向裁掉操作。

当前先保存原型和设计，再接入共享编辑器。AI生成、评论目标、资源选择与日历的子页另有原型，尚未借本图计为全部实现。
