# 12/13 文档类型路由与大文档阅读 v2
状态：原型先行；2026-11-11；尚未集成、未测试、未构建、未Native验收。原型 documents-v1.png，提示词 prompt.json（内置 image_gen）。不覆盖旧12/13图。

## 视觉与交互
原型从左到右：真实章节目录、原生Markdown阅读、现有复杂WebView引擎只读入口、大Markdown完整原文分块阅读。白底、Slate正文、#315fca动作；48dp触控，320dp/200%和180dp键盘遮挡仍可滚动。四屏是设计表达，不是验收截图。
章节图的文件夹外观只表达层级；父文档本身仍可打开正文，箭头独立展开。搜索保留祖先路径，树菜单/移动/权限沿用现有实现。类型徽标取真实doc_type，不根据内容猜类型。
正常Markdown仍用BookstarkMarkdown与现有鉴权附件，保留原位置恢复、上一篇/下一篇、摘录和明确编辑。图片不得整篇迁入WebView。
复杂正文复用ComplexEditorBrowser且默认readOnly=true，保留Flutter书名/路径/权限/导航外壳；不能拿原生TableView、JSON文本占位或提示“专用原生编辑器”作为正常复杂阅读。
“进入编辑”仅在权限、已验证的文档专属writer、恢复/未知保存安全控制均就绪时出现并可用；adapter草稿不提供writer，因此集成前不能把原型蓝色按钮接成不持久的内存编辑。
超过500000 UTF8字节的Markdown切只读完整原文，复用SourceChunks/SourceTextView的有界分块，不向BookstarkMarkdown或NoteEditorPage传整篇；保留BOM/CRLF/NUL/emoji。段号跳转、上一/下一段、可选文字、摘录当前段；编辑明确禁用并说明。原型段数为合成数据，运行时从完整原文计算。
未知类型/格式无效：显示真实错误、重试、明确“查看原文”的只读分块入口，不生成空引擎文档、不保存。ENC:保护载荷（允许一个BOM）不得作为原文显示或编辑；沿用typed锁定错误。

## 已核对的真实协议
- controllers/content_type.go:isSupportedDocumentType严格支持 markdown/html/spreadsheet/drawing/mindmap/richdoc/presentation，空仅服务端创建时默认markdown；不把未知type降级成markdown。
- controllers/document.go:GetDocument返回 document_id/book_id/doc_type/markdown/modify_time/prev_id/next_id。html及richdoc特别返回 markdown:''、content_url:'/api/docs/:id/content/raw'、content_encoding:'gzip'。现DocumentItem.fromJson丢content_url/encoding，是必须修的加载缺口。
- controllers/html_content.go:GetDocumentHTMLRawContent执行原资源owner校验；writeRawContent为真实内容/传输gzip。客户端应走现有BookstarkClient带凭证且挂载前缀处理的受限raw读取，不手动再解gzip、不把储存压缩串喂引擎、不信任任意content_url主机。
- inline原markdown承载spreadsheet/drawing/mindmap/presentation的原JSON；html/richdoc远端必须rawloader，本地SQLite正文为plain source，不能套远端raw接口。
- API PUT /api/docs/:id使用字段markdown保留实际类型；rename独立PUT document_name，空正文不能同非空名称一起提交。服务端上限Markdown500000、html/spreadsheet/drawing/mindmap/richdoc5MiB、presentation20MiB。不能借笔记/blog API保存文档。
- ComplexEditorKind同名一一对应；ComplexEditorDocument验证Unicode、大小、JSON结构并保留exact source。Univer IWorkbookData(sheetOrder/sheets)、Excalidraw(elements/appState或旧数组)、MindElixir(nodeData/linkData)、Canvas Editor富文档(bookstark-richdoc schema_version1,data.main)、PPTist(width/height/slides/IDs)由现host.js现引擎消费，禁止转换为新格式。
- Browser/transport默认只读；可编辑需要onReady/onState/onSaveRequested/beforeRetire/onReloadRequested全套，并有generation/revision、bounded chunk snapshot、lease retirement。不能仅改readOnly=false。
- local_documents_repository现_row/_rows查询全部列，非MD source可能超过CursorWindow；集成必须改metadata projection+受限BLOB读取（不能先全拉正文再分块）。RemoteDocumentsRepository现client.get也全量JSON解码，需分流/有界读取；UI分块不是I/O流式证明。

## 摘录与位置兼容
正常Markdown不改现document_excerpt来源/归属校验及ReadingPositionVault prefix/namespace。大文档以段锚点映射0..1 fraction，仍写现ReadingPosition(fraction,modifiedAt)，刷新先对modifiedAt；不得冒充旧像素滚动位置。迁移普通→分块时只恢复近似fraction并明确提示。
分块只展示source全文而非拼片段Markdown渲染，避免跨段代码/表格含义改变；摘录显式选中/当前段，原documentId与bookId传现onExcerpt，不能静默整篇复制。复杂引擎没有现成选择/滚动回调；不把Flutter外壳0高度当引擎内阅读位置。暂保留章节级导航；引擎内位置/摘录须独立协议和Native验证后接入，不能假称本批完成。

## 独立草稿与接线边界
外部scratch位于next-stage/admin44-implementation/documents12-13-next-patch；只新增typed route adapter、只读surface、小范围测试草稿，不改冻结应用source。Root接main/books/nativeResourceOpener共享入口并决定writer/storage接口。准备稿不宣称通过测试。
必要接线：所有文档入口统一身份/同书/type校验；remote DTO保留rawmetadata+boundedloader；本地metadata/BLOBboundedreader；文档专属writer（事务fresh身份/type/权限/baseline、未知save不重放、readback核对、恢复vault与flush）；引擎附件资源策略/owner lease；大文档位置/摘录与生命周期。
编辑门禁必须按最新正文/类型与byteLength重核，reader初始快照不能授权之后变化的资源。

## 最小验证与Nativecase
单测：7type精确dispatch；html/richdoc rawmetadata不得空fallback；恶意/错ID/错书/rawURL跨host/旧type/ENC拒绝；BOM与Unicode；500000/500001 UTF8边界；invalidJSON原文仍保留；未知type只读；writer未就绪时无编辑；跨文档更新重置chunk；fraction恢复；摘录保留source身份。
Widget：7type正常render（platformview stub仅路由证据）；320EN200%/keyboard180动作可达；large只构建有界段；error不生成空文档；正常Markdown摘录/位置现有回归。
Native仅NAS ARM64后续：目录7type真实入口→对应现engine可视/可访问；HTML/richdoc真实raw含BOM；复杂附件/权限/后台retire与快速返回；真实保存/掉响应/进程重启不重放；大MD多MB最后段可达、原文hash不变、恢复/摘录；两屏布局。未实施或未验项必须保留pending。
