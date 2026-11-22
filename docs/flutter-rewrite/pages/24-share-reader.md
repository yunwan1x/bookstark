# 24 分享原生阅读：实现前协议与原型

2026-11-05。独立原型已生成归档并发送用户；当前没有分享阅读页面实现。此页也用于22公开广场的真实打开动作，不能将私有owner编辑器用于其他人的公开内容。整体24的评论、共享编辑、书籍目录/章节各需独立原型和回归，不以此首版替代整组。

原型：白色AppBar返回/分享阅读/更多；类型与公开分享标签、真实标题/作者/时间、听书与复制链接；白色阅读区用既有BookstarkMarkdown原生排版正文，代码/链接/图片依原组件行为。文章/笔记Markdown与独立分享文档可先阅读；书籍详情进入独立共享目录和章节阅读；HTML/富文档等按真实doc_type衔接29—34，不擅自当Markdown，也不WebView。底部评论入口遵守真实系统开关和分页，不填虚构计数。

实际协议：GET /api/shares/:identify 返回 ShareDetail，share_type=blog/book/document，target_id正整数，share_id可为公开blog的负ID，share_identify须与请求同一实际标识；未建md_shares的visibility=1 blog直接用blog_identify访问。book带doc_tree真实节点document_id/identify/parent_id/children，章节GET /api/shares/:identify/docs/:docIdentify，服务端校验属于目标book，title/content/doc_type返回，不用私有GET /api/docs伪装公共阅读。canonical公开URL只含已编码的实际identify和必要章节，不包含token/密码/账号。

保护边界：GetShareDetailByIdentify对密码blog正文返回空，但仍可能带labels；原生模型必须在解析时清空锁定资源content/description/labels/contentURL，不能先给UI再隐藏。只允许元数据标题/作者/日期/格式进入解锁页；解锁后数据只在当前内存会话，退出清空。不能把后台返回的负share_id当私有数据库ID执行owner写入；普通阅读无编辑按钮。

附件：公开分享使用独立只读附件通道，不复用RemoteAttachments对 /api/webdav/files/download/preview 的个人认证下载。必须阻止不可信正文自动触发个人/private API；外部图片绝不携带app Cookie/CSRF，URL凭据和危险scheme拒绝；同源公开upload-files或明确public-image路由才可有界只读，重定向不能越界传凭据。外链点击明确系统打开，下载/分享保留真实字节，不执行HTML/SVG脚本。Android原生网络与Web浏览器同源自动Cookie行为需分别核对，不把Web withCredentials=false当成完全无同源Cookie。

HTML/富文档：prepareShareHTMLPayload清空JSON content并返回受限content_url，GET /api/shares/:identify/content/raw，可能Content-Encoding:gzip；实际content_type含html/richdoc。字节、解压后大小、UTF8、同源固定路径均需限制，不能用任意content_url带auth读取；密码原始内容走POST verify-password/raw，仅内存解密。29—34未完成时明确显示格式与可用只读原始内容/导出，不虚假宣称完整渲染。

评论协议：GET /api/shares/:identify/comments?page=&page_size= 返回实际thread树、total、page/page_size，CanDelete由服务端逐条给出；系统禁用时同样200空列表，不能以total=0推断已关闭或已开启。enabled/max_length在旧服务share_view HTML固定JS字面量中，当前JSON无对应能力字段；需安全只读能力适配或明确未知，不猜设置。POST评论需要CSRF，可匿名（昵称/邮箱）或登录账号；正文限制按Unicode rune与真实系统上限，默认2000不可冒充可配置值。回复 parent_comment_id/reply_to_comment_id来自当前真实树，不能把段落/索引当ID。创建未知不自动重发，删除遵循实际can_delete/服务端权限。邮件不展示在公开列表，正文不执行脚本。受保护分享评论当前后端并不要求密码解锁，原生仍需按设计在阅读解锁后再展示，不能泄露保护提示之外的内容。

验证：真实旧Go Markdown/公开blog负ID/显式book与document分享/密码错误与成功/撤销/404与403/跨书章节拒绝；恶意正文URL不访问私有API、不泄露Cookie；请求取消/代次/内存解锁清理；native原型截图、中英文320dp200%与Android。当前仍实现前设计，22广场尚未接生产打开动作。

2026-11-05 实现进展：模型、固定有界JSON/密码验证、只读公开附件、分享阅读与解锁原生页面已实现；分享目录和章节原型/文档先行后实现。21项针对性测试及真实匿名Go契约已通过，另8项书籍/阅读UI测试通过；阅读与解锁中英浏览器回归通过。完整构建及目录/章节浏览器回归尚在进行，尚未Android验证24。评论与共享编辑仍在继续，不能视为整组完成。
