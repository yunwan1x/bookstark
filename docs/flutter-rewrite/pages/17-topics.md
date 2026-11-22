# 17 主题：列表、详情、小结、资料、任务、评论（实施前设计）

已先生成17-topics.png、17-topic-detail.png、17-topic-editor.png并发给用户。Slate/蓝色主题、8dp卡片、4dp网格、最小48dp触控；列表按问题组织，标题/问题/真实资料小结任务数量，关键词/日期/日历、置顶、创建编辑删除。详情问题卡+四个可换行分区“小结/资料/任务/评论”，复用现有原生Markdown和独立编辑/草稿。旧布局无需保持，但功能范围全部保留。所有页面中文/英文，320dp及200%字体可滚动。更深编辑、小结/资料选择/评论/日历页面在写UI前另出原型，不把这三张图当成所有子页已经设计。

GET /api/topics?keyword=&date=YYYY-MM-DD&page=：真实分页total/page/page_size。关键词实际搜索标题/问题/小结/资源快照/任务内容，字面LIKE转义；界面搜索提示不应声称只搜索标题。按日期匹配主题修改、小结修改、资料创建、任务修改任一活动，不是创建日期。GET /api/topics/daily-counts?year=&month=年度1970—9999，count是主题/小结/资料/任务活动数量之和，不等同主题数量，日历不能误标成“当天主题数”。具体路由以routers为准，先契约核对。

POST /api/topics、PUT /api/topics/:id {title,question,is_pinned}。Go trim标题和问题，标题必填，200 Unicode码点，问题2000码点（不是笔记的UTF8字节数）。置顶PATCH幂等{is_pinned}。GET详情返回topic,summaries,resources,tasks,stats；权限严格owner，admin也不能凭role覆盖他人主题，不复用书签owner/admin判断。topics列表的task_count真实总数，详情目前只加载100条任务且stats.task_count用已加载长度；原生需使用任务仓库topic_id分页补齐并区分真实总数，不能拿100当全部。

小结：/api/topics/:id/summaries POST，/:summaryId PUT/DELETE，/sort PATCH。content.trim必填≤20000码点；summary_type manual/ai，order_sort保留真实值。更新不能重置原type/order；排序只提交当前topic真实ID，不凭跨页局部排序覆盖其他记录。原生Markdown编辑/预览，手动与AI类型明确标识。AI需复用现有真实SSE和停止/错误/草稿确认机制，AI输出先进入可审核草稿，不自动保存；已保存的ai小结显示“AI小结”，不能标成未确认草稿。原图已修正此标记。需核对现有topics.js的topic-summary上下文协议，不能把通用聊天输出冒充已写入小结。

资料：类型document/note/article/bookmark/task，target_id必须真实正ID，服务器要求源资源owner一致；不能新增外部虚构ID。title_snapshot≤500码点、desc_snapshot≤2000码点，空值服务器从真实资源补齐；重复引用明确显示已存在。缺失资源保留快照并标记resource_missing，不跳错资源。点击源对象复用已实现原生阅读/笔记/文章/书签/任务路由，解析open_url不得把登录Cookie带到外部主机。管理资料引用的删除只移除关联，不删除源资源。源资源编辑后需重新读取、保留旧快照语义。

任务：复用原生任务编辑和父子/日期/完成/草稿逻辑，实际topic_id保存与清空，所有读取分页到真实总数；任务树移动不能串错主题。直接关联任务资源与topic-owned tasks在模型上是两类，应按服务实际行为呈现，不能把重复计数伪装为不同任务。详情搜索和类型过滤按真实已加载范围说明。

评论：/api/topics/:id/comments GET(target_type,target_id,page,page_size≤200)/POST，/:commentId PUT/DELETE；创建target_type仅resource/summary/task，ID绑定当前主题内的真实资料关联/小结/任务；没有可直接创建的topic根评论。GET不传target_type可列出全主题评论，不能把这一读取能力当成根评论写入。仅一级评论，parent_comment_id必须0；content trim后1—20000码点，完整请求≤256KiB。Markdown显示与同源附件复用现有组件。编辑只改content，不改目标；分页真实，保存/删除后更新详情计数，错误保留输入。不得把书签的公开权限扩展到私密主题评论。

删除主题必须确认说明会连同小结、关联资料、主题内任务、评论及主题分享一起进入真实事务删除；源资料本体不删除。Go先SnapshotTopic+CreateTrash，任何快照失败整体回滚，不能用多请求循环模拟同一事务；本地SQLite新版本需同样快照，包含真实任务数据，保留原1—7表。删除前后验证其他主题和源资源不变。恢复页属28，旧Android导入属44，不把新库升级当导入。

草稿：按服务器/owner/topic及子资源隔离，安全记录存储，显式恢复/放弃，部分保存保留真实ID；新增POST网络结果未知不能声称绝不重复。网页元数据或AI不能覆盖用户并发输入。打开页面、选择标签/资源、预览、小结生成不得隐式写入远端。

验收：远端真实Go与本地CRUD/分页、字符限制/emoji、日期与日历语义、owner权限、资源去重/失效/源跳转、小结类型与排序、任务topic_id和100条边界、评论目标和请求上限、删除快照原子性、草稿/AI停止与确认、小屏中英/键盘/200%字体、各子页原型截图与真实Android。当前仅三张初始原型和协议设计，尚未实现17；未覆盖子页不记完成。

## 当前检查点
已完成本轮原生链路实现与220项/Go/11组浏览器/APK验证，九张子页原型和实际截图保留，详细证据见../validation/2026-11-04-topics-validation.md。此前“尚未实现”是初始设计时状态，已由本记录更新；17仍待真实Android和高级路径，未标完成。
