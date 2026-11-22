# 第37组：成员审批与权限管理契约（实现前）

只读来源：`routers/router.go`、`middleware/auth.go`、`controllers/admin.go`、`controllers/common.go`、`models/member.go`、`models/db.go`、`controllers/account.go`。没有请求服务，也没有运行测试。此文只写当前 Go 行为，不增加搜索、过滤或服务端分页能力。

## 路由及权限

所有 API 都在认证后的 `/api/admin` 组内，并再经过 `middleware.AdminRequired()`：未认证返回 HTTP 401；认证但 role 不是0返回 HTTP 403。管理员角色值为 `0`，普通成员为 `1`。权限必须以每个请求的服务器响应为准，Flutter 隐藏入口不能替代该检查。

| 操作 | 请求 | 成功响应 | 当前错误响应 |
|---|---|---|---|
| 列表 | `GET /api/admin/members?page=1&pageSize=20` | HTTP 200；`{code:0,data:[Member],total,page,page_size,total_pages}` | 查询失败 HTTP 500，message `获取用户列表失败`。 |
| 审批通过 | `PUT /api/admin/members/{id}/approve`，无body | HTTP 200；`{code:0,message:"已通过审批"}` | 非整数/溢出ID HTTP 400 `无效ID`；SQL执行错误 HTTP 500 `审批失败`。 |
| 拒绝 | `PUT /api/admin/members/{id}/reject`，无body | HTTP 200；`{code:0,message:"已拒绝"}` | ID错误 HTTP 400 `无效ID`；SQL执行错误 HTTP 500 `操作失败`。 |
| 改角色 | `PUT /api/admin/members/{id}/role`，`{"role":0|1}` | HTTP 200；`{code:0,message:"角色已更新"}` | ID错误/JSON错误/role不为0或1 HTTP 400；改自己 HTTP 400 `不能修改自己的角色`；目标不存在 HTTP 404 `用户不存在`；内置 `conf.App.AdminAccount` HTTP 403 `系统内置管理员账号不允许修改角色`；SQL错误 HTTP 500 `设置失败`。 |
| 重置密码 | `PUT /api/admin/members/{id}/reset-password`，`{"new_password":"…"}` | HTTP 200；`{code:0,message:"密码已重置"}` | ID错误 HTTP 400 `无效ID`；缺失/空/JSON绑定失败 HTTP 400 `请输入新密码`；长度少于6或超过72字节 HTTP 400，分别为 `密码长度不能少于6位` / `密码长度不能超过72位`；目标不存在 HTTP 404 `用户不存在`；未审批(status≠1) HTTP 400 `该用户未通过审批`；写入失败 HTTP 500 `重置密码失败`。 |

API错误统一为HTTP状态码同时写入 `{code:<status>,message:<中文错误>}`；认证中间件拒绝时还带`error`字段。成功变更没有返回更新后Member或版本号。

## 列表数据与分页的精确含义

`models.ListAllMembers` 不接受搜索、状态过滤或排序参数：固定 `ORDER BY member_id` 升序，COUNT全体成员，使用LIMIT/OFFSET。controller缺省`page=1&pageSize=20`，模型将`page<1`改成1、`pageSize<1`或`>100`改成20；最大可请求pageSize为100。`total_pages`至少为1（空列表也为1）。超过最后页返回空data，但total和total_pages仍表示总数。

列表SQL只选择`member_id, account, role, status, create_time, create_at, last_login_time`。序列化类型仍为`models.Member`，所以JSON object字段包含：`member_id`整数、`account`字符串、`email`空字符串、`role`整数、`status`整数、`default_home`空字符串、`create_time`时间字符串、`create_at`整数、`last_login_time`为null或时间字符串；`password`因`json:"-"`完全不输出。email/default_home不是从列表SQL读出的真实资料；不能把空值显示成用户真实邮箱/主页，也没有独立member detail GET endpoint。状态来自注册逻辑：0待审批，1已批准，2已拒绝。role 0管理员、1普通成员。当前列表不屏蔽内置admin，不按状态分组，也不提供查询/过滤；原型可以在客户端显示本页记录的状态分类，但不能宣称是全局筛选结果。

**服务端分页边界缺陷需单独记录：** controller对`Atoi(page/pageSize)`忽略错误，并把原始整数传给`apiListSuccess`；模型虽会归一非法值，但响应仍用原始值。特别是`pageSize=0`或非数字被转成0，模型回默认20，随后`calcTotalPages(total, 0)`可能除零；负数/超大值也可能让响应的page/page_size/total_pages与实际查询不一致。Flutter只发送省略参数或有效的`page>=1,pageSize` 1–100，并处理500；Go侧应另修规范化/测试后再依赖对异常参数的行为。COUNT查询自身的Scan错误也被模型忽略。

## 写操作的未知结果与保护边界

`approve`/`reject`只是`UPDATE md_members SET status=? WHERE member_id=?`，不检查RowsAffected；不存在ID也可能以HTTP 200返回成功。它们不检查当前状态、自身ID或内置admin。`SetMemberRole`先读取目标再写，禁止改自己的role和内置admin的role，但存在读取与更新之间的竞态。`ResetMemberPassword`要求批准状态；更新在事务中哈希新密码并增加`md_member_auth_versions`，用于使该用户现有认证版本失效。密码长度按UTF-8字节数而非字符数验证。

所有写接口都没有幂等键、目标版本、变更后对象或可查询操作回执。HTTP非2xx可按错误处理；超时/断连属于结果未知，不能当作失败并静默自动重放。approve/reject/role虽是赋值型写入，重放仍可能覆盖期间另一管理员做的新选择；密码重置的重放会再次更新密码哈希并递增auth version。未知结果应先重新GET列表核对可见状态；密码不能从服务端读取核对，必须显示“结果未知”，由操作者明确发起一次新的重置，而不是自动重复旧请求。当前后端允许审批/拒绝自身或内置admin，也允许给未审批用户改role；UI不能假称服务端会阻止这些动作，若产品要求限制需先变更Go契约。

## 原型建议（不扩展后端）

- 列表以页为单位显示账号、状态、角色、创建时间、最后登录时间；邮箱/主页在该API中不可得，避免预留假详情。固定按member_id升序，明确页码、总数与上一页/下一页边界；页面只提供当前页本地查看，不加全局搜索/filter控件。
- 每行可打开基于该列表对象的轻量详情/操作面板，标明“当前列表可用资料”；显示ID、账号、状态、角色、时间，不显示空邮箱或密码。详情不是另一个服务端资源。
- 待审批记录展示“通过/拒绝”确认对话框，明确目标账号和不可撤销副作用；成功后刷新当前页并用服务端状态回读，不只靠本地改色。处理404/500/401/403与结果未知时保留上下文。
- 角色操作只提供0管理员/1普通成员，先确认账号、旧/新角色；对当前管理员自己在客户端禁用并解释服务端拒绝，对内置admin的限制来自服务端403，错误仍要能读。不要加入“锁定/封禁”控制，现有API没有该动作。
- 密码重置单独确认目标，要求重复输入确认但只提交`new_password`；输入遮蔽、明确6–72 UTF-8 bytes契约、永不记录或回显密码。成功只显示server message，失败可编辑重试；未知结果不得自动重试。
- 窄屏和200%字体下长账号/时间不遮操作；确认对话框可滚动。拒绝、改role、重置密码均有独立处理中状态，防连续点击；页面切换/退出后丢弃旧请求结果。

## 后续可执行测试

1. 隔离Go测试：AdminRequired的匿名401/普通用户403/admin成功；列表字段精确、不泄露password/真实email，默认page 1/size20、升序、总页数最小1、末页空结果；明确复现并修复pageSize=0/非数字的panic及非法page回显。验证status 0/1/2、role0/1。
2. Go mutation测试：所有成功/错误HTTP状态及message；不存在ID的approve/reject现行错误语义；role非法、自身、内置admin、目标不存在；密码空/5字节/6字节/73字节/72字节、多字节边界、未批准用户；重置后auth version递增，目标旧token失效。
3. Flutter repository fake HTTP：只允许上述五个endpoint和HTTP方法；精确解析null last_login_time/时间字符串/page envelope；非法分页元数据拒绝而非默默伪造；401/403清空成员数据；无搜索请求/参数；提交unknown不自动重放且保持待核对状态。
4. Widget：列表空态/加载失败/重试/分页；待审批确认和刷新；角色变更/禁止自己；内置admin 403；密码字节限制、遮蔽、未知回执；快速连点只发一次；长账号与200%字体可访问，旧generation响应不覆盖新账号。
