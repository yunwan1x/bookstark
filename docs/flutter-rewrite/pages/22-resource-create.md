# 22 资源创建入口：实现前协议与原型

2026-11-04。独立原型22-resource-create.png已生成并归档，本页选择器首版代码已开始实现，尚未连接真实创建协调器。白色AppBar关闭/新建资源；选择资源类型说明；笔记/文章/书签/文档四张独立卡（图标、名称、真实能力提示、chevron）；可见范围说明与取消。选择类型只进入原生编辑/目标选择，不能在入口直接创建空白资源或伪造已保存。新建页/草稿与此前各类型原型共用，新增文档全局书籍/父目录选择还需先补独立原型与规范。

现有Web static/js/resource-create.js：note POST /api/blogs {blog_type:note,editor_type:markdown,blog_title:正文摘要,blog_content,visibility,labels}，要求非空正文；article POST /api/blogs {blog_type:article,editor_type,blog_title,blog_desc,blog_content:'',visibility:0,labels}，创建后进入对应实际编辑器；bookmark POST /api/bookmarks {title,url,description,labels,is_public,favicon}，网页metadata只在明确操作后获取；document 先取真实书籍和目录，再POST /api/books/:bookID/docs {document_name,parent_id,doc_type}。文档继承书籍相关访问范围，不把所有新资源都宣称私有。创建成功以实际回执ID/type/identify为准，不靠列表位置或标题推断新ID。

复用现有Flutter笔记/文章/书签/书籍文档仓库、附件和草稿实现，不重做另一套字段转换造成精确标签/Unicode/visibility丢失。新增共同创建结果模型，供首页/广场/主题引用调用，含实际type/id/title/description/identify/必要bookIdentity；不能把新建结果误当已有资源/重复ID。主题追加引用是第二步，资源已建但挂载失败要保留新ID供只重试引用，绝不再次创建资源。若结果未知，先按相应仓库能力核对，无可靠幂等则保留草稿和明确不确定状态，不自动POST。

默认不在类型切换时丢弃其他类型草稿；退出选择器不产生写入；编辑退出保持各自已验证的草稿/丢弃流程。URL metadata不会覆盖用户在请求期间输入的字段；文档书籍/目录权限与代次隔离，父目录ID必须来自所选书籍真实树，创建前再核对目标。文章与文档类型列表只展示已有真实原生编辑器接好的能力，其余对应29—34继续补齐后接入口，不放空白WebView或无法工作的占位。

测试：四种真实创建/系统选择取消/草稿和可见范围/重复书签/metadata并发/书籍目录切换/父节点失效/新ID回执/创建成功挂载失败/未知保存不重发；旧真实Go协议与本地SQLite仓库；中英小屏大字体键盘与浏览器/Android；原型逐项还原。当前仅设计，不将已有零散编辑器计为本组已完成。


2026-11-05 原型修订先行：保留v1图，当前22-resource-create.png只修正文案：文章当前为已实现的原生Markdown长文入口，不承诺未完成的格式选择/描述；提示明确笔记/文章默认私有、书签可公开、文档继承书籍范围。接下来按原型补齐四色64dp图标面板、加粗卡标题、信息面板与固定取消按钮；卡片选择仍无写入。先前朴素列表截图为首版，不宣称已与最终原型完全一致。


创建协调器现已接入首页真实入口，使用同账号/本地空间既有仓库与安全草稿。回执区分新建/已有书签编辑、部分标签失败与完整成功，笔记/文章ID不会因标签待同步丢失。401检查点已完成Go、SQLite根导航与Android x64happy-path回归；当前继续按修订原型完善视觉，并补本地首页新资源列表/打开与可访问性。公开广场仍待24真实阅读/解锁打开动作，整个22保持实现中。
