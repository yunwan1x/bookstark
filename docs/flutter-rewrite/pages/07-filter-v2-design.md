# 07 笔记列表筛选与多选 V2（实现前设计补充）

状态：仅设计，未改应用源码、测试或 Native harness；07 尚未完成。以现有 07-notes.md/png 为基础，新增选定图 07-filter-v2.png、提示词 07-filter-v2.prompt.json、完整协议 07-filter-v2-protocol.json，旧图不覆盖。生成采用内置 imagegen 的 ui-mockup 模式。

## 视觉与入口

沿用白底、Slate文字、蓝2563eb、24dp页边距、48dp点击区和原笔记页签。选定图左侧是服务器空间笔记多选，右侧是同页可滚动筛选 bottom sheet；内容不显示代码/后端术语。搜索文案改为“搜索标题或标签”，不沿用旧图不符合 Go 的“正文”搜索承诺。列表显示真实公开/私有、置顶与保护标记，摘要限制与权限保持；格式不明不能用空正文覆盖。普通 Markdown 原生，文章及所有复杂格式仍进入既有 WebView。

筛选入口附非默认条件数量，应用后显示可删除 chips。面板先编辑临时条件，关闭/系统返回保留原已应用查询；“应用筛选”才用该完整快照重置分页请求。“重置”只将面板值还原，需应用才清查询。应用失败保留条件与旧列表，明确错误，不伪装空结果。200%英文/键盘下单列滚动，footer动作可换行，不用固定高度裁掉日期或代码条件。

选定图默认 label/date/pin 不限，visibility公开、has_code启用，对应两个 chips。日期是有效日历单日，文案“创建日期”，不是修改日期或范围。“仅含代码”默认关闭；没有“不含代码”选项。置顶三态：全部/已置顶/未置顶，可见性三态：全部/私有/公开；全部都省略对应 query，不发送错误的字面值 all。

## 实际 Go 协议与能力边界

完整可机读契约见 07-filter-v2-protocol.json。依据 controllers/blog.go、models/blog.go、controllers/common.go、routers/router.go；这是源代码协议审计，没有访问真实用户服务。

GET /api/blogs 的本页固定 type=note；page默认1，page_size 1..200，未有效指定则系统 page_size_blogs，否则12。keyword 查询标题或标签 LIKE，不查正文；label 为精确标签，date 为 DATE(create_time) 等值，按服务端既有日期语义，不擅自按手机时区重写日期范围。pinned 是查询名，is_pinned 是列表返回名。has_code=1/true 才启用，服务端排除 html 并按代码围栏/反引号 SQL 规则判断，不是精确 AST 分类，不提示“已证明全部代码”。

shared、encrypted、editor_type 确有后端参数，但旧 Notes 主筛选没有它们：本次主要面板只补旧实际 date/label/pinned/visibility/has_code。后续高级条件须另明确范围和回归；shared 与公开不是同一概念，encrypted 筛选不是授权解密。排序固定置顶降序、pin_order升序、modify_time降序，不能添加不存在的 sort 接口。

本地 schema16 当前没有 visibility/is_pinned 字段，不能将服务器筛选照搬为本地假成功。当前能力仅显示真正支持的本地条件；本地日期/代码须后续实现真实只读查询再启用，且不为列表筛选擅自改变库格式。切换空间必须退休旧请求与选择身份。

## 单条与批量置顶

单条 PATCH /api/blogs/:id/pin 是 toggle，无目标值 body；返回 data.is_pinned 布尔，列表 is_pinned 整数需分别正规化。请求中禁重复点击。若结果未知，先读回当前状态，不自动重放 toggle；同样约束 visibility toggle。可见性切私有会清分享、公开会建分享，单条继续走真实确认与既有分享设置，不把它当纯视觉切换。

批量 POST /api/blogs/batch-pin body 只有 ids，语义仅设置1，返回 affected 数量而不是逐ID成功列表。原型只显示“置顶所选”，没有不存在的批量取消置顶。确认时冻结去重的正ID集合，仅这些ID可写；禁止把当前查询、total数量或下一页未选择记录当作授权。

跨页选择保留真实 IDs；显示已选数及其他页数，不宣称“全选所有结果”。置顶/回收站逐项失败或结果未知，保留条目和失败选择，包括当前不可见页；只读回核对后标记已完成。affected 单独不足以证明每条成功。回收站继续实际 DELETE 单ID流程；不得 invent batch-delete blogs 接口。更改搜索/筛选如需清多选，先让用户确认；取消保留旧查询与选择。空间身份变化清理本地选择并阻断迟到响应。

## 标签、并发与权限

实际列表 labels 为 []string，允许空 null。兼容读取旧版序列化 JSON 数组文本与普通逗号文本需专用 decoder：JSON数组必须每项字符串，坏数组/混合类型保留错误，不默认为空标签。写标签沿用真实资源标签 API 的 labels CSV字符串协议，不给它传 JSON数组；不虚构批量标签/批量可见性 endpoint。若后续实现这些 bulk，先逐ID读实际状态并计算合并/移除，处理并发与失败，只有显式选中ID在范围内。本轮原型未承诺这些额外 bulk 已实现。

所有远程读写沿当前源的认证客户端与 CSRF 契约，服务器 owner/memberID 为最终权限边界。403、会话过期、网络失败不乐观改成成功；过期会话不重用旧账号选择集合。隐藏/禁用的功能不显示可成功的占位交互。

## 下一批实现与验收计划（仍未执行）

先扩 typed query/result metadata，再接真实 filter sheet 与 clear chips，之后单 pin/批 pin 查询核对和多选失败保留。查询 generation+完整参数固定分页身份；同页重复ID去重且不能混旧查询，清空回第一页。列表真正点击不同 editor_type 打开中央既有 WebView 路由，不只测试来源链接。

自动回归覆盖 exact query/prefix/编码、三态默认、省略不含代码、单日有效性、全部重置、toggle未知不重放、batch only selected IDs、affected不足与跨页失败、labels三种兼容/坏数据、空间退休、320dp/200%英文键盘。实际 NAS redroid ARM64验证本地与隔离Go服务器真实列表/筛选/分页/多选/权限/复杂格式入口，并独立核对 SQL/API 请求与字节；原应用和全部数据恢复后清临时产物。此文档和原型都不等于测试或07验收完成。
