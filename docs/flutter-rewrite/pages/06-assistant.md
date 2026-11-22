# 06 AI 助手（实现前原型/协议设计）

原型 `06-assistant.png`，提示词同名prompt.txt。原生Scaffold：返回/标题/菜单，当前空间提示；滚动消息区，用户蓝底气泡、助手白色Markdown卡片（标题、列表、引用、代码、表格、链接/图片复用共享Markdown与附件组件）；服务器提供的来源标签；工具草稿独立卡片，pending/confirmed/cancelled状态；底部多行输入与发送，流式期间变停止，错误/中断可见且保留输入/已接收文本。左右24dp，蓝2563eb/Slate/白，8dp圆角、48dp触控，输入随键盘缩放且大字不溢出。

## 服务器契约

- GET `/api/ai/assistant` 返回顶层session（id/messages/drafts/busy），没有data包装。
- POST `/api/ai/assistant/chat` JSON `{session_id,message,history}`，Accept text/event-stream，Cookie+CSRF同一网络owner。message上限8000字节；history为按user/assistant交替的完整偶数对，最多38条，每条最多24000字节，总包不超过192KiB。历史是客户端上下文，不伪装工具指令，不发送sources作为授权。
- SSE事件 round({round})、progress({tool})、delta({text})、ping({})、error({code,message})、done({code,session_id,messages:[本轮两条],drafts:[本轮]})。UTF-8/行/事件均可跨网络块，CRLF/注释/多data行按SSE解析；非SSE失败先解析JSON错误，未收到done不能显示完成或把半截回答当成功历史。每轮工具循环的round要清理/隔离上一轮临时delta，最终以done中服务器的两条完整消息为准，不重复拼接。
- 取消/离开通过AbortableRequest断开实际HTTP流，让服务器Request.Context取消上游；保留界面部分回答并标“已停止”，不自动重发或创建资源。
- POST `/api/ai/assistant/reset` `{session_id}`，确认后重置本地上下文并使用返回新session。
- POST `/api/ai/assistant/drafts/:id` `{session_id,action:'confirm'|'cancel'}` 返回顶层draft。只有明确按钮确认后调用；聊天文字不是确认。核对弹窗展示完整title/content/due_date，确认前校验session/draft ID；处理中禁重，失败保持pending，冲突/过期以服务端为准并提示重新载入。
- 消息created_at为秒；来源{kind,id,title,url,truncated}和草稿{ID,payload:{kind,title,content,due_date},status,url}全部使用真实响应。来源只按支持的kind/id路由至原生页面，不把服务器/模型任意URL当可信导航或执行代码。已确认资源亦按已知类型路由。

## 状态与持久化

服务器不持久化会话正文快照；本地以[规范服务器路径,经过认证的member_id]隔离保存完整轮次上下文，使用安全存储，限制体积。刷新不能丢上下文或复制旧轮次；新服务器session与本地不一致时明确丢弃/重置选择，不能混用。未确认草稿由服务端持有并刷新，不将客户端历史里的工具文本恢复为可执行草稿。

AI未开启/配置缺失、会话busy、HTTP401/403/409、错误SSE、连接截断、停止、发送重复、重开和重置均需可操作状态。输入限制按UTF-8字节，不按字符数。流式期间限制重置与确认，避免旧响应写入新会话。

本地空间最终也需要原生本地AI适配器（安全存储的服务配置、本地知识查询、确认后原生SQLite写入），不能以“仅服务器可用”永久缩减重写目标；该适配器随本地模型/设置闭环实施，在完成前清单保留未完项。

## 验收门槛

请求头/CSRF/语言/路径前缀；SSE跨中文UTF-8和CRLF网络片段、ping/工具轮次/错误/缺done/取消真正中止；完整消息与来源/草稿绑定；空历史/多轮持久化隔离；确认与取消只调用一次且无聊天自动写入；Markdown流式增量与小屏键盘/大字；原型/实际截图和Android真机。Fixture不能证明真实模型服务或真机后台。

### 来源面板和状态码补充（实现前）

来源标签使用06页内的原生只读资料面板，不把它冒充完整书籍、章节或主题管理页。面板按白名单kind/id调用既有笔记/文章、任务、书签（兼容GET路由带末尾斜线）、书籍、文档或主题接口，显示实际内容/元信息；不能按模型提供的URL请求或跳转。上方原生标题/关闭，下面滚动共享Markdown；加载/读取失败/重试均真实，后续完整阅读器就绪可在原生路由上替换。Source.kind还包括topic。

服务端草稿完成状态实际为done（不是confirmed），放弃为cancelled，过期为expired。done回执URL只允许 `/notes?tab=notes&id=正整数` 或 `/notes?tab=tasks&task_id=正整数` 转成kind/id再打开原生资料面板，绝不执行任意回执URL。任务草稿的title为空，任务内容在payload.content，日期在due_date；笔记才使用payload.title。

服务端语言中间件读取lang Cookie，网络owner须单独附加受限zh/en语言Cookie；不把它混入token/csrf持久会话，也不随第三方图片请求发送。SSE心跳读超时45秒，停止须同时取消获取CSRF和正文流，缺done必须报中断。
