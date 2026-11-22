# 10 待办列表、编辑、子待办与日历（实现前）

列表原型 `10-tasks.png`，内置imagegen，原始提示词同名prompt.txt。白色56dp AppBar，返回/行动·待办/日历；16dp边距，搜索、未完成/全部/已完成切换、所有日期筛选；按截止日期分组，白色8dp圆角边框卡，14sp任务标题、12sp日期、原生勾选框、更多/子待办操作。编辑和日历有独立补充原型，必须先落地再实现。320dp、英文、200%文字与键盘须可滚动，不能固定卡高。

## 已核对的真实接口

- GET `/api/tasks`：keyword/done/parent_id/topic_id/due_before/due_after/due_on/date/page/page_size；data数组+total/page/page_size。done只能在选择未完成/已完成时传入，全部时省略，不能把空字符串当“全部”。parent_id省略包含所有层级，传0只含根；include_children递归附加子任务且每层最多100条，不可把它当无限完整树。
- GET `/api/tasks/:id`：data为完整任务。字段task_id/content/due_date/done/parent_id/topic_id/child_total/child_done/children/complete_time/create_time/modify_time。
- POST `/api/tasks`：content/明确的due_date/done/parent_id，可选topic_id。content按Unicode码点最多1000，去首尾空白后不能为空。原生日期校验须拒绝不存在的日期。服务端空日期会默认七天后，UI不能显示“无日期”后悄悄让服务端补日期；新建直接显示可修改的七天后默认值。
- PUT `/api/tasks/:id`：完整内容/日期/done/parent_id；保留详情取得的原parent_id，不因编辑正文将子待办移到根。topic_id不提供时服务端保留，不能默认0清除原专题关联。
- PATCH `/api/tasks/:id/done` `{done:bool}`：等待成功后刷新状态/完成时间；失败保留原状态并显示重试，禁止重复点击，不自动勾选子任务。
- DELETE `/api/tasks/:id`：服务端将整棵子树制作回收站快照再删除。确认弹窗须说明“包括子待办”，不是无损隐藏。不能在客户端逐个DELETE子项破坏一棵树的回收站快照。
- GET `/api/tasks/daily-counts?year&month`：data[{date,count,done_count,active_count}]。**统计按modify_time，不是due_date**。原生日历标注“修改记录”，点日期使用date=YYYY-MM-DD；列表“截止日期”筛选另走due_on/due_before/due_after。不能将同一统计冒充截止日任务数。服务端overdue过滤due_before为<=，UI分今天与逾期时必须将今天单列，明确日期含义。

## 原生交互约束

- 筛选与分页由Repository执行；全量/未完成/已完成切换都清分页和旧错误，异步旧响应不能覆盖新查询。子待办采用可分页原生子列表，不用递归100条接口宣称已加载全部。搜索/日期/完成筛选可返回子记录，显示父任务关联并可打开父级，不因为父记录不符合条件而吞掉命中子项。
- 展示真实Markdown，复用共享渲染器与附件读取owner。编辑只保存完整详情，不能把卡片摘要覆盖正文；创建/编辑/子待办保持输入、日期、脏内容离开确认。保护敏感内容的草稿使用既有串行安全记录存储，并将新建根/不同父任务的新建草稿隔离。
- 列表里已知子记录可缩进，缺失子记录显示真实child_done/child_total和“查看子待办”入口。不能以本页已加载数当服务端总数。完成与删除对同ID持有操作锁，回退/切换时旧请求不会写进另一空间。
- 新建/编辑支持已有Markdown格式、完成/取消完成、截止日期、子待办；原站待办AI改写/拆解与专题关联仍属于完整闭环，随AI编辑/17专题补齐，未验收前10页不标完成。
- 本地Repository独立SQLite任务表，持久化父子/完成时间/日期；读写/删除事务化，防自引用/循环/孤儿，删除保存可还原子树。迁移只升级Flutter库，旧Android数据迁移仍由44页核对后导入，不覆盖原库。

## 验证门槛

真实Go接口的创建/修改/完成/取消/父子/日期/删除快照；Unicode长度与无效日期；本地数据库升级、重开、层级循环/级联回收；完整分页与错误重试、旧搜索竞态、失败不得丢输入；日历修改日统计与截止日筛选互不混淆；中英文小屏键盘/大字、原型截图对照、Android实际设备回归。Fixture仅作视觉和可控交互，不代替真机/真实账户数据。
