# 38 友情链接与评论管理：列表实现前设计
2026-11-07。虚构示例，仅设计；不代表页面已实现或完成回归。先读 controllers/friend_link.go、models/friend_link.go、controllers/share_comment.go 与 models/share_comment.go，路由均为 authenticated/admin。
## 友情链接列表
GET /api/admin/friend-links 返回 data.items 与 simple_mode。列表无分页，最多200；按group_order、sort_weight、link_id排序。白底蓝色卡片显示分组、名称、URL、启用、排序，顶部简洁模式与新增，底部保存全部。列表修改只形成草稿，不即时逐行写入。
PUT相同路径 body为items完整数组和simple_mode，服务端事务删除原链接、重新插入，ID与创建信息会改变。必须保留未编辑的group_name/group_order/qr_code/description等字段；不能仅发送当前可见行。全量无版本条件，刷新核对后仍可能有并发覆盖，确认必须说明整体替换。断线结果未知，重新读取比较语义字段，不能按旧ID判断，禁止自动重放。
新增/编辑/删除草稿确认页面仍需单独原型后实施。支持普通HTTP(S)链接或二维码项；二维码仅本站规范/upload-files/图片路径，不擅自把二维码条目当无效空URL删除。名称/分组100、URL/二维码2048、描述1000均按UTF8字节核对；二维码组标题/描述须一致。请求1MiB上限；空数组表示清空全部，必须明确确认。新增不支持任意远程二维码URL。
## 评论列表
GET /api/admin/share-comments 用page、page_size=20、keyword、status、target_type。状态只发visible/deleted或省略，类型只发blog/book/document或省略。服务端keyword LIKE匹配正文、作者、分享标识、回复目标作者，通配符沿用Go行为，不宣称字面精确搜索。按create_time DESC、comment_id DESC分页。filters/search改变先清空勾选并回第一页。
卡片展示真实author_name/content/status/target_type/share_identify/create_time及可选回复关联，不输出email/IPhash/useragenthash（管理员payload未提供）。只有永久删除，没有审批/恢复/编辑API。页内勾选，底部已选数量及永久删除；分页、权限或会话变化清空选择，不让跨页隐藏ID混入操作。
POST /api/admin/share-comments/delete body={comment_ids:[positive IDs]}。服务端去重跳过非正值；主评论删除comment_id及root_comment_id关联回复，单条回复只删除该行，返回data.deleted为实际影响行数，可能大于勾选数。确认页须另作原型，说明永久删除及回复影响；请求未知不自动重复。成功后刷新，页数减少时明确回到有效页。不能把deleted=0伪造为删除成功多条。
## 生命周期与验证
320dp/200%字体自适应滚动，48dp点击区域，状态同时用文字。管理员入口fresh profile核对，所有请求仍由Go鉴权，401/403清除列表/表单/选择；旧会话迟到响应不能恢复资料。保存/删除进行中禁止连点，失去所有权取消并拒绝回执。原型示例不可硬编码为运行数据。
后续测试用隔离Go DB验证全量替换语义、二维码字段保留、字节长度、200项/1MiB边界、筛选分页及删除主回复数量；fakeHTTP验证endpoint/body/401403/未知无重放，widget小屏与确认取消，NAS redroid真实操作及独立SQL核对，原数据不变。编辑页、删除确认与真实集成尚未完成，38和全部45组仍未完成。

## 实施前状态细化（2026-11-07）

第37组已独立验收并归档。第38组使用先行原型，开始接入模型与会话仓储，尚无UI或原生验收。独立Go契约已核对整表替换/ID重建/UTF8/二维码/200项/1MiB、评论24条20+4筛选与主评论3条/回复1条/不存在0条，测试实例已清理。

友情链接草稿使用内存中的稳定行标识，编辑应用与移除不发HTTP；仍由保存全部的独立确认发PUT。成功回执与回读分开；未知写入与提交前发现服务器配置变化都保留原草稿为只读状态，在原列表布局中展示受控提示和明确读取按钮。重新读取后展示当前服务器列表，采用当前配置并结束核对需明确确认放弃原内存草稿；不自动重放旧PUT，也不把相同现状当旧请求成功。已知成功但回读失败只补GET。Go没有条件版本，确认页始终保留并发覆盖说明。

评论勾选绑定当前筛选/页/行快照；筛选、分页或刷新清空勾选。删除确认冻结选择和版本，新读目标变化则不POST，返回重读后重新选择。已知回执保留服务器实际deleted（含0及级联更多），回读失败只补GET；未知结果保留目标摘要，不保留可重复点击的旧提交。原列表只读状态承载明确读取与核对，完成核对后才能开始新的选择。权限或会话变化撤销所有所属弹框并清空列表/草稿/选择，旧回调不能恢复数据。


2026-11-07 V1验收：1312项全量测试、83个本组浏览器视图及同一冻结ARM64 APK的独立链接/评论NAS redroid子流程完成。实际业务写入4次整表PUT与3次评论删除POST分别验证，两个子流程各自精确恢复原18表/2文档/5附件、偏好与会话。此前失败尝试保留，不冒称一次全通过。详见[验收](../validation/2026-11-07-admin38-v1-validation.md)。固定26未提升，全部45组未完成，继续39。
