# 24 共享 Markdown 编辑：实现前原型与协议

2026-11-05。已先生成并发送24-share-edit.png。当前尚未实现。顶部返回/共享编辑/显式保存；浅蓝能力提示、真实只读标题与格式白卡、编辑/预览Tab、原生多行Markdown与基础格式/撤销工具栏、底部未保存状态。只改正文，不展示或更改owner标题/标签/可见性。预览复用BookstarkMarkdown与独立公开附件，不使用owner附件仓库。附件上传若接入必须走share edit上传端点与同一能力，不借个人Cookie操作DAV。

实际GET /api/shares/:identify/edit?token=... 返回editable,title,content,doc_type,share_type,modify_time,has_password；不返回target_id，不能伪造私有Note/Document owner记录。先读公开ShareDetail的实际上下文，再校验编辑类型/格式和同一标识的能力。book整本不允许共享编辑，blog/document可以；protected blog的GET正文为空，即使旧token仍存在也不能当空正文进入可保存编辑器。首版Markdown与受保护/其他格式必须分别明确支持范围，不以空内容覆盖或WebView冒充。

实际PUT同端点body={content,password?}只更新正文；Markdown上限500*1024 UTF8字节，其他格式5MiB/20MiB另有协议，不扩写猜测。返回modify_time，不返回新ID，保存后只能重读当前能力确认实际内容/格式/权限；禁止在确认失败时自动重发。保存成功回执但重读失败应保留已获回执事实，提供只读核对，不继续POST。超时/断线/无效回执属于结果未知，保留本会话文本，先GET核对；等于提交内容可确认已保存，仍等于旧基线才可由用户明确决定再次保存，遇到第三方内容进冲突状态。不能靠字符串相同去重所有用户动作，区别显式保存与自动重发。

旧服务PUT没有CAS/version/If-Match原子冲突保护。保存前重读对比基线内容/原始modify_time，发现改动先进入冲突界面，可复制本次内容、载入远端、明确覆盖。预读与PUT之间仍有竞争窗口，必须在设计/验证文档保留此事实，不能宣传原子并发安全；若要彻底消除需单独升级服务协议。本客户端不暗自改生产Go服务。

编辑token只驻内存，不入公开URL/听书上下文/日志/错误文案/草稿键名/导出或安全存储。外链与图片读取不附token；客户端默认HTTP错误可能含URI，UI一律受限通用错误。退出确认未保存/未知状态，密码和token本会话结束清理。令牌撤销、格式/目标/保护状态改变时停止保存，提供只读/复制，不拿owner权限绕过。

回归须含完整URL验证、实际公开上下文、正确/错误/重置token、无token只能读、Markdown空正文与UTF8上限、改变格式/撤销、真实修改回执、冲突和结果未知不自动PUT、中英文320dp200%键盘/预览、只读附件边界及实际Android。当前仅原型/协议，后续逐步实现。

协议补充：实际UploadShareEditImage仅允许richdoc/presentation，Markdown不支持此上传端点，因此本Markdown工具栏不放一个会被服务拒绝的上传入口。其他格式随29—34接入。共享BookstarkMarkdown的SelectableText.rich在Web canvas上能正确显示，但当前DOM不完整暴露正文；本批浏览器检查真实模式/回执与截图，正文由Flutter渲染树和真实Go内容分别核对。已发现的Web阅读语义不足列入45无障碍回归，不把截图代称屏幕阅读器通过。
