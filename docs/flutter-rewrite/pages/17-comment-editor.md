# 17 评论正文编辑（实施前设计）

原型17-comment-editor.png。与小结同一共享NoteEditorPage正文模式：上下文为主题/目标类型/实际目标标题，无可编辑标题、无标签，Markdown编辑/预览、附件工具栏、20000码点验证和安全草稿。目标标签只读，编辑不能改变目标。编辑态显示真实Markdown源码，预览态才渲染强调/列表，不能把图中编辑框的视觉强调当成富文本写入。

CommentEditorRepository仅适配TopicsRepository.comments/saveComment，不写笔记接口，不用资料源ID替代资料关联ID。新增返回真实comment_id，后续保存沿用同ID；已有评论保留topic/target/target_id，save只提交content。选择不存在/已删除/跨主题目标要真实报错，不降级发到主题根或其他目标。仅一级，无parent输入。

草稿namespace按server/owner/topic/type/target和comment_id隔离，原先笔记/文章/文档模式不改变；受保护源笔记不自动解锁，不自动引用其正文。返回列表回读计数和分页。小屏中英/200%字/键盘、保存失败保留、部分ID、类型不移位、空白/emoji上限、原型与实机回归。先保存原型和文档，再接入评论页流程。
