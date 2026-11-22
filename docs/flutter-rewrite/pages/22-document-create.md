# 22 新建文档表单：实现前原型与协议

2026-11-05，独立原型22-document-create.png已生成归档并发送用户，已先实现安全创建状态与持久草稿核心，随后开始DocumentCreatePage首版。与位置选择器不同，本页需要显式创建回执和不确定状态。

白色AppBar返回/新建文档，浅Slate背景、16dp间距。文档位置白色卡片显示实际书籍与父目录名称，更改打开22-document-location；权限说明继承书籍范围。文档名称输入、最多200 UTF8字节提示；文档类型只提供真实接通的Markdown单选卡，说明原生编辑支持附件。信息卡创建后进入编辑器、确认前不产生写入；固定底栏创建并编辑/取消。输入不把字节当字数，动态实际UTF8长度与校验沿用validateDocumentName，不自动截断Unicode。中英320dp200%允许换行并可滚动，键盘不遮住提交和当前错误。

确认前再次核对实际书籍ID和父节点成员关系；DocumentsRepository.create已经再读实际树校验parentId，同步取得POST真实完整回执。只有返回DocumentItem实际id>0、bookId与选中一致、parentId吻合、type=markdown才可打开现有DocumentEditorRepository+NoteEditorPage。不通过创建后额外read掩盖已存在ID。创建成功后编辑器导航/草稿清理失败仍保留真实ID，单独提供打开，不重新POST。选择器返回/类型选择/取消均无写入。

未知结果分支必须有持久安全状态：请求发出前记录原始名称/书籍ID/父ID与pending标志；网络中断、超时、5xx或不能解析的成功回执，不自动重发POST，不只靠名称匹配猜测节点ID（允许同名）。能确定未写入的客户端校验/明确拒绝再开放编辑重试；不可靠幂等情况下保持草稿并明确待核对。未知状态重启后也必须阻止无提示重复创建。保存已知ID但后续失败，与未知是否创建严格区分。原型是正常编辑状态，异常状态沿同组件显示事实状态与允许的核对/退出动作，不加虚假的恢复成功。

本页将使用现有安全草稿机制的单独命名空间/记录格式，不能把待创建记录当已有文档ID，更不能写凭据/密码/正文到非安全存储。明确放弃只删本机草稿/待核对提示，不撤销可能已创建的远端文档，需讲明事实。新建结果返回ResourceCreationResult元数据（真实类型/ID/bookID/title/identify，created与metadataComplete），供后续主题追加引用单独重试，不能自动重复建资源。

测试：输入验证不发POST、原始字节与精确目标、同名不推断ID、成功回执不后读/不重写、确认时父节点失效、请求未知重启保留、已知ID后编辑器失败仍仅打开该ID、草稿故障不发写请求、取消无写、中英文键盘小屏原型截图、实际旧Go与本地SQLite、Android。仍属实现前设计，未完成项不能按本页“已接通”宣称。


实现进展：DocumentCreationVault为已有安全存储回调的独立namespace+SHA256 key，串行读写，不可读不清除；草稿允许有界8192字节无效输入以便保留编辑内容，提交仍严格200字节校验。DocumentCreationController先只读核对书籍/父节点，安全保存submitting意图成功后才POST；中断恢复submitting视为unknown，禁止再次创建/静默清理。未知错误持久保留，明确4xx拒绝才回到editing；真实ID回执本机保存失败仍维持acknowledged，后续只补存回执/打开，不再POST。

DocumentCreatePage已按原型实现名称/实际位置/Markdown/固定底栏与键盘避让；安全草稿自动保留，已创建ID和未知结果分开展示；未知记录可保留退出、查看实际目录或明确确认只清除本机记录（不删除远端/不宣称失败）。打开编辑器失败保持已创建ID。当前7项创建核心/页面测试通过，包括未知重建只读、打开失败不重复创建、320dp200%键盘；浏览器截图及真实新核心Go契约待补。暂未接生产创建协调器，不计整组完成。


后续：7项定向测试与Analyzer通过，表单中英320dp200%浏览器截图通过，实际截图22-document-create[-english-small]-fixture-actual.png已归档测试目录并发送用户。真实Go新增创建核心契约通过：实际父节点/Unicode与字面%2F名称/POST完整回执，安全记录恢复真实ID后再次create被阻止，实际目录仍只有初始节点+新节点两项。日志validation/2026-11-05-document-create-browser-contract.log。前述“待补”是历史状态，当前仍缺生产创建协调器、Android原生表单/键盘及长期迁移门槛。
