# 第43组 Docker 管理主原型 V1（实施前）
2026-11-08。使用 imagegen 技能的内置生成工具；主图43-docker-v1.png和完整提示词保存本目录及本地output/bookstark-prototypes。主图SHA256：4994d0c058bf458ccd1ff576a1b43eaead4a17e4b44bcdcedb20041fd573af8c。已在会话内展示。当前第42组仍在V2回归，43尚未实施，尚需补充创建/维护/未知回执原型。

## 视觉与布局
白色背景，56高顶栏，primary#0b57ee、ink#0c192e、card#eaf2ff；圆角12、外边距16、至少48触控区域。明确各推入路由都使用本组局部主题，不能遗漏表单/核对页并继承全局色值。320窄屏/两倍字/780横屏采用滚动、换行与纵向操作，不缩小字体。日志/终端暗色正文分别处理内容和生命周期，不拿浏览器截图当原生证明。

## 主图四屏
1. 容器列表：绑定已核对SSH host；容器/网络/数据卷/镜像四资源，查询只筛选已读取列表；卡片显示真实name/image/state/ports，查看/日志/终端/更多；创建容器与重新读取。接口无资源统计，不能编造CPU/内存/守护进程版本或持续SSH连接状态。
2. 容器详情：实际inspect提供id/name/image/status/running/exit_code/created/started_at/finished_at/hostname/ip_address/restart_policy/command[]。主图展示其中部分；没有inspect环境变量表。操作仅start/stop/restart/delete与restart-policy。API删除不是force；运行容器必须先停止，不能静默升级强制删除。
3. 日志：tail默认200、合法1–10000；当前截图有真实格式示例所以显示跟随中。手动跟随/停止、自动滚动、清空当前显示；清空不删除远端日志。后台、换账号/host/容器或离开立即取消和清敏感内容，不自动重连。所有示例纯合成。
4. 容器终端：明确目标和未连接/连接；复用xterm WebView正文，未连接时键盘/粘贴/断开禁用。与主机PTY分别核对容器exec、resize和取消握手。粘贴明确确认；后台/离开断开并清正文。

## 契约和实施边界
- Go接口在/api/admin/assets/ssh-hosts/:id/docker-*，管理员scope+完整host/credential绑定；操作始终使用当前已核对容器ID与必要元数据，不能把列表名称或短显示ID随便当目标。
- 真实Go SSE日志事件为status{state:connecting}、log{data}、log-error{message}，不是WebSocket。Docker终端是WebSocket；不能混用两种协议。服务器没有明确ready事件，不能只见connecting就显示已连接。
- 创建请求的基本、端口、挂载、环境变量、network/privileged/memory/cpus全部按已存在Go DTO设计。Env值仅表单/提交短期持有，不写日志或恢复缓存；检查并确认后发送一次。创建+启动可能部分成功，未知回执不自动重放。
- 网络、卷、镜像及prune必须先补字段/语义调查和原型；不编造拉取百分比、原子回滚或可撤销删除。prune是整台选定主机相应资源的清理，不只影响当前筛选行。
- 只用隔离Go/SSH和独立Docker测试环境，不能把NAS生产Docker.sock挂入测试去删除/清理。真实daemon与HTTP协议假体的证据明确区分。


## 创建流程补充图（仍在实施前）
43-docker-create-v1.png 主图sha dfbd89032d87a9cf528c4b5fd0fb2d2c412e6ba45d27ea64b404ce6c6c3ebef0；初稿与“只把三页顶栏改成白色/深蓝文字，其他保持”编辑提示均保存.prompt.json，生成默认路径原图保留。最终选用白色顶栏版，并已向用户展示。
基本页包含name/image/command/restart_policy/start_after_create；配置页包含ports/volumes/env与network/privileged/memory/cpus；核对页列真实目标和所有设置，环境变量可只显示项数并明确临时展开值，禁止把秘密写日志/恢复缓存。图片中的示例不是默认将挂载NAS路径或自动发布端口的指令。CLI/API对command与资源限制的实际解析需核对后实现，不按示例猜测。

## 资源维护与未知结果补充图（实施前）
43-docker-maintenance-v1.png 已生成并保存NAS/本地。五屏包含网络name/driver/scope与创建name/driver、数据卷name/driver/mountpoint及创建name/driver、镜像repository/tag/id与拉取image引用、整主机已停止容器清理核对、拉取结果未确认只读观察。无子网/IPAM/配额/虚假使用中状态；无registry登录、拉取百分比、自动重发或假回执。
清理目标是所选主机的对应Docker资源，不局限筛选行。图片示例选择containers，实际images默认prune与volume的远端版本规则需另行核对，不能把空过滤器说成删除所有未使用的带标签镜像或所有命名卷。
三张原型及文档均早于任何43应用代码；尚未复制进当前冻结的42仓库输入。

## 创建命令的实际限制（实施前补充）
services/asset_docker_client.go的API config.Cmd = []string{command}；CLI fallback也把整个command作为一个shellQuote参数。故字段是“单个命令参数/可执行文件”，不进行shell解析，不支持把“nginx -g …”当多个argv输入。界面须明示“完整文字作为一个参数传递；需要复杂参数时使用镜像默认命令或镜像入口”，默认留空；不能替用户加sh -c或静默拆分空格。网络/挂载/端口与环境变量使用各自结构化字段，不能放在command里伪装支持。
内存units.RAMInBytes、CPU有限非负float×1e9；客户端需拒绝NaN/Infinity/负数和无效大小，而不是传给Go后声称有限制。start_after_create始终明确发送bool，UI不依赖服务端默认true。

## 目标ID补充（实施前）
真实容器/网络/镜像列表将ID截成12字符（API主路和CLI均可能短ID），不能把列表值称完整ID。容器动作/终端/日志先POST inspect取得完整ID，核对列表ID前缀/名字/镜像并绑定完整inspect身份，提交前再次inspect与主机/凭据核对。最终请求使用inspect返回完整ID。外壳列表可显示短ID，但确认页明确完整ID。
镜像/网络/卷没有对应inspect API：保留实际列表身份与精确name或repository:tag，重新读取确认同一条目；不得伪造完整ID或把所有同ID标签当选中单一tag。镜像删除以所选精确tag（无tag时原始ID）为目标，不声称删除同镜像所有tag。不能提供服务端没有的CAS/原子目标保护。

## 端口配置兼容性复核（实现中的明确修订）
实际Go API主路在host_port空时只声明ExposedPorts；CLI回退却执行-p container_port/protocol，会随机发布主机端口。为保证用户核对与两条路径一致，本版端口行要求明确主机端口和IPv4绑定地址，新增行默认127.0.0.1，不以“留空”的同一表单暗含两种结果。0.0.0.0在核对页明确显示绑定所有IPv4接口。当前兼容表单不接收IPv6绑定，不能声称所有地址语法均已支持；后端两条路径的IPv6序列化仍需单独核对，不静默添加括号改变请求。原型仍用127.0.0.1显式端口示例。

## 已实测日志边界
真实Go的4096字节SSE边界可能将中文片段替换为U+FFFD，正文与提示需明确这不是可逆恢复；用户可停止跟随，明确读取同样tail行数的新快照核对。已在独立daemon证明JSON快照完整、SSE含替换字符时可识别。日志缓冲仍只保留最近1MiB，并明确告知移除较早内容，不把局部显示说成全部日志。
