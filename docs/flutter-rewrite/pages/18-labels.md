# 18 标签管理：实施前设计与协议

列表原型18-labels.png先于界面实现生成。Slate背景、蓝色主操作、白色卡片、8dp圆角；搜索、真实全部/使用中/未使用统计、排序、原生详情、创建与管理员操作。列表空白/请求失败保留查询，搜索与翻页使用世代隔离；新增返回真实ID，重复或网络结果未知不能静默再POST。中英文、320dp、200%文字、键盘和滚动纳入回归。详情、编辑、合并、推荐设置在写对应界面前另出原型。

GET /api/labels?keyword=&sort_by=name|book|blog|bookmark|total|recent&sort_order=asc|desc&page=&page_size=。total、used_count、unused_count均属于当前keyword匹配集合，而非永远服务器全局。真实分页，无前端伪造总数。keyword由旧Go LIKE处理，百分号/下划线目前是通配符，不宣称字面搜索。

标签在服务器内全局共享，不标为仅自己的标签。三类展示计数只含book、blog(笔记与文章合计)、bookmark，不含document；used_count以全部关联类型计算。因此三类计数全零不能推断未使用。原型中的未使用徽标只有在真实详情items为空且非截断时才可呈现；默认列表不根据三个零误标。按recent排序的recent_count是近90天关联量；不是修改次数。

所有登录用户可POST /api/labels {label_name}。PUT/DELETE /api/labels/:id、DELETE /api/labels/unused、POST /api/labels/merge仅管理员。Go以UTF8字节len≤100限制名称，原生提示为100字节，不按100中文字符接受；名称身份保留空格、不随意trim重命名。创建接口空白名称处理须遵循实际旧接口并在客户端避免无意义空串。删除是标签/关联永久删除，源资源保留，没有回收站承诺；全服务器未使用清理不是当前搜索结果清理，确认说明范围。批量删除循环不得伪装成原子事务。

GET /api/labels/:id/detail 返回label_id,label_name,book_count,blog_count,bookmark_count,items(resource_id,title,relation_type,identify)，最多500条。UI明确“最多返回500项”，500不能当总数；混合资源数量不包含document计数，不能用三类计数和算完备。blog需实际读取确定note/article，document资料旧接口标题为空时显示真实ID，不伪造书籍标题。原生打开每类源资源，按真实权限拒绝不可访问，禁止拿全局关联当拥有编辑权限。

POST /api/labels/merge {target_id,source_ids}：1—100个正源ID、不含目标、不重复，全部真实现存。先核对目标/源存在，展示将合并到的目标名称与源数量；服务端事务合并关联去重并移除源标签。客户端不以逐项重绑定模拟事务。未知结果先重新读取标签及目标详情再允许重试。标签重命名/删除/合并后重新读取相关资源计数，不承诺Go提交后的label冗余字段同步无故障。

推荐：GET /api/labels/recommendation-settings {strategy,manual_labels,page_size}，所有登录用户可读；PUT同结构仅管理员。strategy recent/total/book/bookmark/manual，page_size1—50。manual按Go trim/去重≤50，单名≤100字节，服务端以逗号拼接，不能宣称含逗号标签可无损保存为精选。GET /api/labels/recommendations?strategy=&manual_labels= 实际预览；切换策略与预览不得隐式写设置，保存需明确按钮；非管理员显示真实设置和权限说明，不能启用提交。推荐是全服务器共享设置，说明影响其他用户。

本地空间使用真实SQLite标签、笔记/文章/书籍/书签/文档关联，删除/重命名/合并须事务维护关联与冗余字段，保留其它主题与资源。不要把远端全局权限套在本地；本地明确当前空间范围。新SQLite版本与44旧Android导入是两件事。

验收包括名称UTF8/emoji边界、全局权限、真实分页与三类计数/文档关联差异、删除范围、合并去重与失败原子性、推荐预览不写入、未知写入重查、原生源跳转、中英小屏大字号、截图和真实Go。尚未实现18，原型不代表交付。

## 当前实现检查点
五页已实现并通过242项/Go/12组浏览器/APK回归，详细见../validation/2026-11-04-labels-validation.md。上文“尚未实现”是初始设计时状态，现由本记录更新；18仍不标完成。SQLite9标签登记已接入；本地recent按源资源修改时间并在界面说明，与Go关联创建时间不同。
