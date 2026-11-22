# 17 新建恢复 v1
原型先于本目录UI代码：prototype/creation-recovery-v1.png。复用17原有编辑页，不改变已有实体编辑。
主题、小结、评论三类创建独立scope+随机128bit attempt key；类型、topic、target与已校验请求正文冻结。prepared transport完成auth/CSRF之后await严格pending→unknown CAS+flush+readback，只有唯一claim成功才POST。unknown不回pending，不自动重放。knownID只重试存储。明确结束不宣称服务器未创建。
实际ID核对：当前member+固定topic/target、完整正文/metadata；同名不是证明。明确接纳前再次fresh完整fingerprint一致。仅记录选定ID，不证明来源。scope退休不能写新scope；missing expected拒绝晚writer复活。
使用既有secure storage与真实durability barrier；串行read/CAS/write/flush/readback+同key lease。普通正文存储不适用于受保护资料解锁正文。prefix需接44/退出维护后才可宣称实际闭环。
大字单ListView；确认dialog捕获controller+record，异步返回freshguard。当前纯外部未工具链/Native验证。

## v2 冷启动目录（图先于UI）
prototype/cold-directory-v2.png在目录页面代码前落盘。主题列表新增“创建恢复记录”工具栏入口，不依赖原主题/目标仍存在。Native只列有界keys（4096/1MiB），Dart只读取当前scope的slot/record，最多16项/累计8MiB；不readAll其他正文或凭据。列表状态必须来自实际当前记录，键名不证明phase。目标不可用时核对报错但仍可明确结束记录，不伪称服务器未执行。损坏/超限不显示假空、不修改。
