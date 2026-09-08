# 声音画笔核心测试计划

## 1. 文档目的

本文档定义声音画笔单页 HTML 的核心回归契约。后续修改
`tmp/sound-brush.html` 时，应根据影响范围执行对应章节；若产品主流程发生变化，
应先更新本测试计划，再修改实现。

测试环境默认使用：

- 本地地址：`http://127.0.0.1:8771/sound-brush.html`
- 自动化入口：`node tmp/sound-brush-qa.js`
- 桌面基线：Chromium，`1440 x 900`
- 小屏基线：Android Chrome 等效视口，`390 x 844`，并补测横屏
- WebGL 参数：ANGLE + SwiftShader，必要时使用真实 GPU 浏览器复测
- 麦克风自动化：Chromium fake media stream；权限和设备中断使用真实浏览器补测

## 2. Task 1 TDD 记录

### 2.1 RED：壳层缺失

执行条件：本地服务已启动，`tmp/sound-brush.html` 尚不存在。

执行命令：

```bash
node tmp/sound-brush-qa.js
```

观察结果：退出码为 `1`，测试准确报告七个稳定节点缺失，而不是 Playwright
启动或网络连接错误。

```text
FAIL 工作台壳层完整 - {"app":false,"topbar":false,"left":false,"stage":false,"canvas":false,"right":false,"monitor":false,"title":"Error response"}
```

### 2.2 GREEN：最小壳层建立

执行条件：只加入 Task 1 规定的离线 HTML 壳层。

观察结果：初始壳层退出码为 `0`；审查增强后同时验证 HTTP 与 `file://`
入口、HTMLCanvasElement 类型、语义标签、非零布局和零外部 HTTP 请求。

```text
PASS HTTP 工作台壳层、语义与布局完整
PASS HTTP 入口无外部网络依赖 - 仅加载主 HTML 文档
PASS file 协议工作台壳层可用且离线
PASS_COUNT=3
```

## 3. Task 2 TDD 记录

### 3.1 RED：音频分析与生命周期缺失

在只存在 Task 1 壳层时，先加入确定性 RMS、频谱、220Hz 音高、
`AudioEngine` 接口、点击前权限、fake media 启停、异常状态和恢复测试，再执行：

```bash
node tmp/sound-brush-qa.js
```

观察结果：壳层与离线测试保持通过，新增六项按预期失败；失败原因是
`computeRms`、`AudioEngine` 和音频 UI 尚未定义，不是浏览器、服务器或测试数据错误。

```text
PASS_COUNT=4
FAIL_COUNT=6
ReferenceError: computeRms is not defined
ReferenceError: AudioEngine is not defined
```

### 3.2 GREEN：AudioEngine 与确定性特征提取

最小实现加入纯 RMS/频谱/归一化自相关音高函数、AudioEngine 生命周期、
麦克风按钮、输入设备选择、可见状态和实时 meter。Chromium fake media 回归结果：

```text
PASS 音频特征计算稳定
PASS AudioEngine 接口完整且点击前不请求权限
PASS fake 麦克风启停后没有存活轨道
PASS 麦克风按钮是唯一权限入口并更新状态
PASS 权限拒绝和 mediaDevices 缺失可恢复
PASS 轨道结束和 AudioContext 暂停状态可恢复
PASS 音频入口保持离线且无运行错误
PASS_COUNT=10
FAIL_COUNT=0
```

确定性基线：220Hz 正弦输入识别约 `220Hz`，置信度大于 `0.99`；静音返回
`{ hz: 0, confidence: 0 }`。停止引擎后旧 stream 的 live track 数必须为 `0`。

### 3.3 RED：后台生命周期与持久连接审计缺失

在保留音高、事务式设备切换和 generation token 修复的基线上，先加入
`visibilitychange` 单例监听、meter RAF/分析计数，以及 WebSocket、WebTransport、
EventSource、`sendBeacon` 审计契约。实现前观察到两项确定性失败：

```text
PASS_COUNT=13
FAIL_COUNT=2
FAIL 页面隐藏暂停音频分析，恢复后只有一个 meter 循环
  listenerCount=0, contextState=running, pendingFrames=1, updateCount=9
FAIL 离线审计覆盖持久连接与 beacon 通道
  auditInstalled=false
```

### 3.4 GREEN：单例可见性生命周期与全通道离线守卫

加入唯一的 `visibilitychange` handler：hidden 时同步取消 meter RAF 并暂停
AudioContext，visible 时按代次恢复同一 AudioContext；meter 启动函数保持幂等，
重复 hidden/visible 事件不会创建重复 RAF。QA 初始化脚本阻止并记录四类持久连接与
beacon 通道，同时监听 Playwright WebSocket 事件。

```text
PASS 页面隐藏暂停音频分析，恢复后只有一个 meter 循环
  listenerCount=1, hidden pendingFrames=0, visible pendingFrames=1
PASS 离线审计覆盖持久连接与 beacon 通道
  attempts=[], guardedChannels=WebSocket/WebTransport/EventSource/sendBeacon
PASS_COUNT=15
FAIL_COUNT=0
```

## 4. Task 3 TDD：工程模型、验证与历史

### 4.1 RED：工程 API 缺失

在 Task 2 基线上先加入默认工程、图层、序列化、严格解析、签名、历史栈、
参数命令合并和 ProjectEngine 控制器测试。实现前预期新增测试因
`createDefaultProject`、`HistoryManager` 等接口未定义而失败；已有壳层和音频测试
继续通过。

实际观察结果：已有 16 项通过，新增 7 项全部按预期失败，首个失败为
`ReferenceError: createDefaultProject is not defined`，控制器测试为
`ReferenceError: ProjectEngine is not defined`；不是测试服务器、浏览器或既有音频链路错误。

```text
PASS_COUNT=16
FAIL_COUNT=7
```

### 4.2 数据与安全契约

- 工程根格式固定为 `sound-brush-project@1`，高版本拒绝导入。
- Canvas 只接受 `64..8192` 的整数尺寸；图层最多 64、笔触最多 20000、控制点
  总计最多 1000000，工程和图层名称最长 120 字符，编码后的工程 JSON 最多
  `16 MiB`（按 UTF-8 字节计数）。
- `parseProject` 必须在调用 `JSON.parse` 前完成字节检查；文件选择入口必须先通过
  `assertProjectPayloadSize(File)` 检查 `File.size`，避免读取超限文件。
- 解析必须构造新对象并忽略未知字段；数值型视觉参数按已知范围收敛。
- 控制点只保存归一化坐标、经过时间、有限的声音特征、段模式和确定性 seed。
- JSON 中不得出现原始音频、频谱帧、粒子位置或 framebuffer 数据。
- 无效工程不得部分替换 ProjectEngine 当前工程。

### 4.3 历史与控制器契约

- 每条命令只执行一次；撤销和重做到栈边界时返回 `false`。
- 撤销后执行新命令必须清空 redo。
- 同一 slider 手势产生的连续参数命令按 merge key 合并为一次历史操作，保留手势
  开始值和最终值。
- 后续 StrokeEngine 通过 `ProjectEngine.execute(new AddStrokeCommand(...))` 写入完整笔触，
  不直接替换工程根对象。
- ProjectEngine 统一产生 `saved/command/undo/redo/replace` 变更事件，并用稳定工程签名
  判断 dirty 状态。

### 4.4 Reviewer 修复回归：事务与引用边界

五项 Important 均按独立 RED → GREEN 实施：

1. **解析前载荷限制**
   - RED：新增测试因 `assertProjectPayloadSize` 不存在而失败；既有 23 项通过，新增 1 项失败。
   - GREEN：`PROJECT_LIMITS.maxEncodedBytes=16777216`；超限 UTF-8 字符串在
     `JSON.parse` 调用计数仍为 0 时抛出 `ProjectValidationError`，Blob/File-like 的
     `size` 同样先行拒绝。结果 `24/24`。
2. **HistoryManager 异常原子性**
   - RED：校验失败被接受并破坏工程/双栈；`do`、`undo`、`redo` 抛错均留下部分工程，
     后两者还提前移动历史项。结果既有 24 项通过，新增 1 项失败。
   - GREEN：命令在工程副本执行，通过 `validateProject` 后才整体提交；失败恢复命令状态，
     工程 JSON、undo 栈和 redo 栈的对象顺序完全不变。结果 `25/25`。
3. **参数路径与值边界**
   - RED：明确的 `SetParameterCommand` 契约缺失。结果既有 25 项通过，新增 1 项失败。
   - GREEN：危险键段在构造阶段拒绝；仅允许工程名、画布、渲染、映射及图层视觉参数
     白名单；命令本身在副本赋值并验证，`canvas.width=1` 抛错且原工程不变。结果 `26/26`。
4. **新增图层活动状态恢复**
   - RED：原活动层与插入位置不相邻时，undo 错误选择插入点的前一层。结果既有 26 项
     通过，新增 1 项失败。
   - GREEN：首次 do 保存 `previousActiveLayerId`，redo 不覆盖，undo 精确恢复。结果
     `27/27`。
5. **ProjectEngine 防御性引用**
   - RED：change 监听器可清空内部 `layers`，导致后续合法命令失败。结果既有 27 项通过，
     新增 1 项失败。
   - GREEN：内部根对象改为私有 `#current`；project getter、change event 和
     `replaceProject` 返回值均为防御性 clone，外部篡改不影响内部。结果 `28/28`。

### 4.5 Task3 复审补充：命令回滚与注入边界

复审问题继续按独立 RED -> GREEN 实施：

1. **merge 失败恢复 previous 和 incoming 命令**
   - RED：`merge` 抛错后 previous 已恢复，但 incoming 保留 `do`、`canMerge` 和
     `merge` 写入的状态及新增属性。既有 28 项通过，新增 1 项失败。
   - GREEN：`execute` 在运行 incoming 前保存命令快照；merge 阶段失败时同时恢复
     previous 和 incoming。使用同一个 incoming 重试可成功合并，undo/redo 保持手势
     初始值和最终值。结果 `29/29`。
2. **ProjectEngine 注入历史可信边界**
   - RED：自定义 HistoryManager 可保留 execute/undo/redo 收到的 `#current` 根引用，
     事后篡改可修改工程名并清空内部图层。既有 29 项通过，新增 1 项失败。
   - GREEN：ProjectEngine 仅把独立工作副本交给 history；history 返回成功后重新验证，
     再以新 clone 交换 `#current`。注入历史仍可提交、撤销和重做，但捕获的三个根对象
     均与内部状态隔离。结果 `30/30`。
3. **ProjectEngine 与注入历史原子提交**
   - RED：注入 history 先提交命令、再返回非法工作工程时，Engine 拒绝工程但 history
     从 `undo=0/redo=1` 变为 `undo=1/redo=0`，incoming command 也残留执行状态。
     既有 30 项通过，新增 1 项失败。
   - GREEN：HistoryManager 提供包含双栈顺序和命令状态的 checkpoint/restore；Engine
     仅接受实现完整事务协议的 history，并在操作返回失败或工程验证抛错时恢复检查点。
     合规包装器可继续代理历史操作，同一 incoming command 可在失败后重试。结果 `31/31`。

最终完整回归必须保持：

```text
PASS_COUNT=31
FAIL_COUNT=0
```

## 5. Task 4 TDD：WebGL2 渲染器与 Canvas2D 降级

### 5.1 RED：渲染 API 缺失

在 Task 3 基线上先加入 SwiftShader WebGL2 像素、framebuffer 能力、强制
Canvas2D、导出尺寸、暂停/恢复/销毁和 context lost/restored 测试。启动本地服务后，
原有 31 项继续通过，新增两项都因 `createRenderer is not defined` 按预期失败。

```text
PASS_COUNT=31
FAIL_COUNT=2
```

### 5.2 GREEN：多阶段渲染与恢复

- WebGL2 建立 scene、trail ping-pong、半分辨率 glow 和 composition framebuffer。
- SwiftShader 提供 `EXT_color_buffer_float` 时使用 `RGBA16F`，否则使用 `RGBA8`。
- 轨迹、辉光和最终合成输出到默认 framebuffer；`renderExport` 使用独立尺寸读取像素。
- 强制 Canvas2D 使用 `lighter`、平滑路径和径向辉光，输出明确为 `canvas2d` 模式。
- context lost 阻止默认释放、暂停渲染并阻止录制；恢复后资源 generation 增加并重放末帧。

确定性基线：WebGL 中央 `32 x 32` 样本有 1024 个非空像素，Canvas2D 有
2524 个非空像素；恢复后的 `24 x 24` 样本有 576 个非空像素。

```text
PASS_COUNT=33
FAIL_COUNT=0
```

## 6. Task 5 TDD：手动、自动与混合笔触

### 6.1 RED：StrokeEngine 缺失

先加入手动距离重采样、ribbon/point buffer、确定性流场、速度和转角边界、
1.6 秒静音、混合无跳变交接、Pointer Events 和单历史命令测试。既有 33 项通过，
新增三项均因 `StrokeEngine is not defined` 失败。

### 6.2 GREEN：确定性笔触控制

- 手动输入收敛到 `0..1`，控制点最大间距约 `0.012`，音频快照与段模式随点保存。
- 自动流场只由 seed、归一化位置和时间决定；连续自动位置与离散采样位置分离，避免
  未达到采样间距时丢失位移。
- 90 个固定 16ms 帧产生 26 个相同控制点，最大步长约 `0.012`，最大转角约
  `0.202 rad`；静音 1.6 秒后速度为 0 且不新增点。
- 混合模式 pointerdown 在自动段末端接管，交接跳变为 0；pointerup 可续画或通过一次
  `AddStrokeCommand` 完成整笔。
- 浏览器真实 Pointer Events 使用 pointer capture，完成后工程笔触和 undo 深度各增加 1。

```text
PASS_COUNT=36
FAIL_COUNT=0
```

## 7. Task 6 TDD：预设、粒子与声音映射

### 7.1 RED：视觉注册表和粒子池缺失

先加入六预设精确 ID、默认映射目标、映射边界、实时像素签名、固定粒子缓冲区和
reduced-motion 测试。既有 36 项继续通过，新增三项分别因预设注册表缺失、六种签名
完全相同和粒子快照 API 缺失而失败。

### 7.2 GREEN：极光默认视觉与实时映射

- 六预设提供调色板、核心宽度、辉光、粒子倍率、残影、流速、爆发和背景密度。
- `evaluateMapping` 支持 enabled、intensity、min/max 和 inverted，输出始终有界。
- 固定容量粒子池使用 stride 9 的交错 Float32 buffer，按笔触 seed 和点序确定性发射，
  每帧复用同一缓冲区并受容量限制。
- WebGL 轨迹、粒子、残影、半分辨率辉光和爆发实时读取当前预设与工程映射；Canvas2D
  降级路径使用同一视觉参数。
- 六种像素签名全部不同；默认极光具有明显颜色方差；单色预设连背景一起去色，平均
  饱和度约 `0.055`，低于 `0.08`。
- reduced-motion 同时响应工程设置和媒体查询，降低粒子速度/数量和爆发并缩短残影，
  不停止绘画。

```text
PASS_COUNT=39
FAIL_COUNT=0
```

## 8. Task 4-6 复审修复：渲染生命周期与默认静音

### 8.1 RED：六个 Important 故障探针

在 39 项基线上先加入六项测试：恢复失败主舞台接管、部分初始化后的替换 canvas
降级、全类 GL 资源事务清理、独立离屏导出、lost 期间延迟 resize，以及未开启
麦克风时的静音累计。新增六项全部按预期失败，既有 39 项继续通过。

```text
PASS_COUNT=39
FAIL_COUNT=6
```

### 8.2 GREEN：原子接管、资源事务和静音时钟

- WebGL 恢复失败时以保留属性的替换 canvas 创建 Canvas2D renderer，原子更新工作台
  renderer/canvas、Pointer Events 和渲染函数引用，并销毁旧 renderer。
- WebGL 已取得 context 后的任意初始化失败不再尝试复用同一 canvas 获取 2D context。
- shader、program、texture、framebuffer、buffer 和 VAO 均在创建后立即登记；编译、链接、
  FBO 完整性和 buffer/VAO 配置任一阶段失败时，created/deleted 计数完全平衡。
- `renderExport` 使用独立离屏 renderer 和 framebuffer，不调用主 renderer 的 resize，
  不改变主 canvas、FBO identity、trail index、resource generation 或 last frame。
- context lost 期间 resize 只记录最后请求；恢复后再按 DPR 创建目标 framebuffer。
- 默认静音快照的 `silentForMs=0` 时，StrokeEngine 使用帧 elapsed 累计静音；达到
  1500ms 后自动速度归零且控制点不再增长。

```text
PASS_COUNT=45
FAIL_COUNT=0
```

## 9. 启动与工作台壳层

步骤：

1. 通过本地 HTTP 服务打开页面。
2. 等待 `DOMContentLoaded`。
3. 检查标题、顶栏、左侧参数面板、中央舞台、画布、右侧图层面板和底部声音监视器。
4. 断开网络后重新加载已保存的单文件。

预期结果：

- 页面标题为“声音画笔”。
- `#app`、`#topbar`、`#leftPanel`、`#stage`、`#artCanvas`、
  `#rightPanel` 和 `#audioMonitor` 均存在。
- 页面不请求 CDN、字体、脚本、样式或后端资源。
- 工作台占满视口，不产生页面级意外滚动条，不出现未处理脚本错误。

## 10. 麦克风与音频分析

步骤：

1. 首次打开页面，不执行任何操作。
2. 点击“开启麦克风”，分别测试允许和拒绝权限。
3. 说话、哼唱、拍手并观察音量、音高、频谱和节拍反馈。
4. 切换输入设备，再拔出当前设备或停止媒体轨道。
5. 将页面切到后台后恢复。
6. 使用固定数组分别计算静音 RMS、正弦 RMS、低频/高频频谱与 220Hz 音高。
7. 使用 Chromium fake media 启动独立 AudioEngine，保留旧 stream 引用后停止。
8. 分别模拟 `NotAllowedError`、`mediaDevices` 缺失、track `ended` 和
   `AudioContext.suspended`。
9. 连续派发两次 hidden 与两次 visible 的 `visibilitychange`，记录监听器数量、
   meter RAF、分析调用次数和 AudioContext 状态。
10. 审计 WebSocket、WebTransport、EventSource 与 `sendBeacon`，并监听浏览器
    WebSocket 事件。

预期结果：

- 用户点击前不得请求麦克风权限。
- 授权成功后显示当前设备和实时、稳定的音频特征；静音时数值平滑归零。
- 拒绝权限时允许继续无声绘画，并提供清楚的重新授权说明。
- 设备切换释放旧轨道；设备中断后作品保留，并提示重新选择输入设备。
- 页面进入后台时暂停不必要分析，恢复后不重复创建音频链路。
- 页面隐藏后 meter RAF 为零、AudioContext 为 suspended 且不再调用分析；恢复后
  AudioContext 回到 running，并且全页仅注册一个可见性监听器、仅存在一个 meter RAF。
- 原始麦克风数据不上传，也不写入工程文件。
- HTTP(S)、WebSocket、WebTransport、EventSource 和 `sendBeacon` 外传尝试均为零；
  测试审计器应主动阻止并记录持久连接和 beacon 通道。
- `listInputs()` 只枚举设备，不触发 `getUserMedia()`；只有用户点击麦克风按钮才请求权限。
- RMS、频谱重心、高频占比和音高函数对相同输入产生相同结果；无可信音高时返回零值。
- `stop()`、轨道结束和切换输入设备都释放旧 MediaStreamTrack、AudioNode 和 AudioContext。
- AudioContext 暂停时只提供一次恢复动作；恢复不重新请求 MediaStream。

## 11. 手动绘画

步骤：

1. 选择手动模式，在画布上使用鼠标、触控和触控笔绘制。
2. 以不同速度移动，越过画布边缘后重新进入。
3. 在有声和静音状态分别绘制。
4. 执行一次撤销和重做。

预期结果：

- 轨迹跟随指针，不发生坐标偏移，触控操作不触发页面滚动。
- 控制点按距离重采样，快速移动不产生明显断线。
- 音量、音高、高频和节拍按当前映射影响笔触，但静音仍允许基础绘画。
- 一次完整绘制作为一个可撤销动作；重做恢复相同笔触和参数。

## 12. 自动巡游

步骤：

1. 切换自动模式并开始巡游。
2. 持续发声、静音，再恢复发声。
3. 调整流速、对称和预设。
4. 暂停并重新启动自动巡游。

预期结果：

- 自动轨迹沿平滑低频流场移动，不高频随机抖动或瞬移。
- 静音超过阈值后逐步减速并停止制造新粒子，恢复声音后平滑继续。
- 参数变更不重置现有作品，不造成布局跳动或渲染资源泄漏。
- 暂停后不再产生新控制点，再次启动从有效位置继续。

## 13. 混合模式交接

步骤：

1. 选择混合模式并开启“自动续画”。
2. 按下指针手动画一段，抬起后观察自动续画。
3. 自动运行期间再次按下并改变方向。
4. 关闭自动续画，重复一次。

预期结果：

- 指针按下时用户立即取得控制权，自动推进停止。
- 抬起后自动画笔从当前切线平滑续画，不跳到其他位置。
- 手动与自动段保留同一笔触标识，但一次创作可整体撤销。
- 关闭自动续画后，抬起指针不会继续生成轨迹。

## 14. 图层与历史

步骤：

1. 新建多个图层并分别绘制。
2. 隐藏、锁定、复制、删除和调整图层顺序。
3. 修改混合模式和透明度。
4. 连续执行撤销和重做。

预期结果：

- 当前图层状态明确，锁定图层不能写入或移动。
- 隐藏、排序、混合和透明度立即反映在画布，数据本身不丢失。
- 删除需要可恢复的历史记录；复制生成独立标识，不共享可变数据。
- 撤销和重做只回滚对应命令，不复制整个 framebuffer。

## 15. 自动保存与恢复

步骤：

1. 创建包含多个图层和笔触的工程。
2. 停止操作，等待防抖保存完成。
3. 刷新页面并选择恢复最近工程。
4. 模拟 IndexedDB 不可用或写入失败。

预期结果：

- 自动保存不在每一渲染帧执行，保存状态有清楚反馈。
- 恢复后的图层、笔触、预设、映射和画布设置一致。
- 未保存变更存在时关闭页面才显示确认；无变更时不打扰用户。
- 存储不可用时工程仍可继续编辑，并提示使用 JSON 导出备份。

## 16. JSON 工程导入与导出

步骤：

1. 导出当前工程 JSON。
2. 新建空工程，再导入刚导出的文件。
3. 导入旧版本、非法 JSON、异常尺寸和超大控制点数组。

预期结果：

- JSON 包含显式版本、元数据、图层、控制点、视觉参数和画布设置。
- JSON 不包含原始麦克风录音或无界二进制帧数据。
- 合法工程往返后可见结果和可编辑结构一致。
- 旧版本按定义迁移；非法或危险数据被拒绝，并显示可理解的错误。

## 17. PNG 导出

步骤：

1. 分别导出 `1x`、`2x`、透明背景和不透明背景 PNG。
2. 比较导出尺寸、透明通道和当前画面构图。
3. 在高分辨率和低性能模式下重复导出。

预期结果：

- PNG 来自独立高分辨率 framebuffer，不是模糊的 CSS 放大截图。
- 像素尺寸、透明选项和文件名符合用户选择。
- 导出不改变当前视口、画布质量、图层状态或历史记录。
- 资源不足时给出错误并保留工程。

## 18. WebM 录制

步骤：

1. 选择 `1080p / 30fps`，分别开启和关闭麦克风音轨后录制。
2. 录制期间绘画并切换手动、自动和混合模式。
3. 手动停止一次，再录满 120 秒。
4. 测试 VP9 不可用但 VP8 可用的浏览器能力组合。

预期结果：

- 开始前显示最终编码、分辨率、帧率和是否包含音频。
- 录制期间画布尺寸和质量锁定，计时及累计体积稳定更新。
- 手动停止和 120 秒自动停止都正确关闭 MediaRecorder 和临时轨道。
- 编码不支持时在开始前降级并明确显示，不生成损坏文件。
- 录制失败不破坏当前工程，用户仍可导出 JSON。

## 19. 响应式 UI 与软键盘

步骤：

1. 在 `390 x 844` 竖屏打开页面，再切换横屏。
2. 打开左侧参数、右侧图层和更多面板。
3. 聚焦工程名或数值输入，弹出软键盘并改变可视视口高度。
4. 返回桌面宽度。

预期结果：

- 小屏以画布为主体，顶栏只保留关键命令，监视器默认紧凑。
- 参数面板从顶部出现，保持全宽并响应 `visualViewport` 高度变化。
- 文本、按钮和数值不重叠，最长标签不溢出控件。
- 横竖屏切换不清空画布、不偏移坐标，返回桌面后恢复三栏工作台。

## 20. 全屏演出模式

步骤：

1. 从桌面和小屏分别进入全屏演出模式。
2. 绘画、自动巡游和录制期间退出全屏。
3. 使用浏览器或系统手势强制退出全屏。
4. 进入前分别滚动左右面板，在全屏中停止操作并等待工具条、鼠标自动隐藏。
5. 通过移动鼠标和单次触摸恢复工具条，再退出全屏。

预期结果：

- 全屏主画布无多余面板间距，关键录制和退出控件仍可访问。
- 进入或退出全屏不拉伸作品、不改变画布宽高比和控制点坐标。
- 工具条和鼠标在无操作后自动隐藏；鼠标移动或触摸立即恢复，恢复操作不在画布留下误触笔画。
- 系统强制退出后 UI 状态同步恢复，不留下遮罩或不可点击区域。
- 退出后左右面板恢复进入前的展开状态和各自滚动位置。

## 21. Canvas 2D 兼容降级

步骤：

1. 禁用 WebGL2 或模拟 `getContext("webgl2")` 返回空值。
2. 启动页面并进行麦克风分析、手动绘画和工程导入导出。
3. 尝试使用仅 WebGL 支持的视觉参数。

预期结果：

- 页面明确显示 Canvas 2D 兼容模式，不出现空白舞台。
- 基础光带、声音映射、工程、PNG 和必要编辑功能仍可使用。
- 不支持的高级辉光或大规模粒子控件禁用并给出原因。
- 同一工程可在 WebGL2 恢复后重新打开，不丢失数据。

## 22. WebGL Context 恢复

步骤：

1. 创建作品后触发 `WEBGL_lose_context`。
2. 在丢失期间尝试绘制、录制和导出。
3. 恢复 context；再模拟无法恢复的情况。

预期结果：

- Context 丢失后暂停绘制和录制，显示单一恢复状态，不清空工程。
- 恢复时重建 shader、buffer 和 framebuffer，并从工程数据重绘作品。
- 无法恢复时仍允许导出 JSON，并提供切换兼容模式的路径。

## 23. 性能与资源释放

步骤：

1. 分别运行高质量、平衡、节能和自动质量。
2. 持续绘制并运行自动巡游，观察帧率、内存和粒子数量。
3. 切换后台、停止麦克风、停止录制并关闭工程。

预期结果：

- 自动质量依据连续帧率调整，不因单帧波动频繁切换。
- 中端桌面默认目标不低于 50fps，常见 Android Chrome 保持可用的 30fps。
- 页面后台停止渲染循环和音频读取；恢复后只存在一套循环。
- 停止操作后释放媒体轨道、URL、MediaRecorder、AudioNode 和 GPU 资源。

## 24. 隐私与离线边界

步骤：

1. 监控页面加载、麦克风启动、绘画、保存和导出期间的网络请求。
2. 检查 IndexedDB、导出 JSON 和 WebM 的内容范围。
3. 在无网络环境完成一次完整创作与导出。

预期结果：

- 单 HTML 不加载任何外部依赖，不向网络发送音频或作品。
- IndexedDB 和 JSON 只保存工程结构及声音特征快照，不保存原始录音。
- 只有用户明确启用录制音频时，麦克风音轨才进入本地 WebM。
- 无网络时除浏览器自身权限限制外，绘画、保存和导出完整可用。

## 25. 六种视觉预设的可观察差异

统一步骤：使用相同画布、同一条固定轨迹和确定性的音频特征输入，依次选择六个预设；
每次等待残影稳定后保存截图，并记录平均亮度、色相分布、可见粒子数量和尾迹长度。

| 预设 | 操作 | 必须观察到的差异 |
| --- | --- | --- |
| `aurora` | 使用中等音量和连续音高绘制 S 形轨迹 | 青绿与蓝紫双层宽光带、清晰高亮核心和柔和辉光同时存在 |
| `stardust` | 沿同一轨迹绘制并保持高频输入 | 核心比 aurora 更细，独立微粒明显更多，扩散范围更大但宽光带更弱 |
| `comet` | 快速绘制同一轨迹后静音 | 头部亮度最高，粒子主要沿切线方向形成明显长尾，尾迹长于其他预设 |
| `deep-sea` | 使用低频、低音量输入绘制 | 整体亮度和运动速度最低，蓝青软光与柔和颗粒为主，不出现高频闪烁 |
| `pulse` | 先输入稳定声音，再触发一次确定性节拍 | 节拍时出现短时冲击波和粒子爆发；无节拍对照帧不得持续产生冲击波 |
| `monochrome` | 扫过不同音高并保持音量变化 | 只通过亮度、宽度和密度变化表达声音，色相方差显著低于其他五种预设 |

预期结果：六种预设在相同输入下具有可辨识、可重复的视觉差异；切换预设不删除
现有笔触，不重置图层，也不制造非预期历史操作。

## 26. 六类声音映射及参数契约

对每类映射使用可重复的低值和高值输入，逐项执行：关闭映射、重新开启、设置
`25%` 与 `100%` 强度、收窄最小/最大范围、开启反向、点击恢复默认。每次只改变
一个变量，并与映射关闭时的基线截图或数值记录比较。

| 映射 | 默认可观察目标 | 开关、强度、范围、反向和恢复默认的预期 |
| --- | --- | --- |
| 音量 | 笔触宽度、核心亮度、辉光半径 | 关闭后高低音量不再改变目标；强度控制变化幅度；范围限制最细/最粗与最暗/最亮；反向后低音量产生更强效果；恢复后回到预设默认值 |
| 音高 | 极光色相 | 关闭后跨音高保持最近有效色相；强度控制色相跨度；范围限定色域；反向后高低音高的色相方向互换；恢复后回到默认色域和方向 |
| 高频占比 | 粒子数量、扩散范围 | 关闭后高低频输入的粒子结果一致；强度控制数量差；范围限制密度和扩散上下限；反向后低高频效果互换；恢复后回到默认密度映射 |
| 频谱重心 | 粒子速度、极光锐度 | 关闭后重心变化不影响速度和锐度；强度控制差异幅度；范围限制速度/锐度边界；反向后低重心更快更锐；恢复后回到默认方向与边界 |
| 节拍 | 冲击波、短时粒子爆发 | 关闭后瞬态不产生爆发；强度控制冲击波和粒子幅度；范围限制最小/最大爆发；反向后弱瞬态响应更强；恢复后恢复默认阈值、冷却和幅度 |
| 静音 | 自动画笔速度、残影释放 | 关闭后静音不主动减速收束；强度控制减速/释放速率；范围限制最终速度与残影时长；反向测试必须明确警告其反直觉结果；恢复后回到默认静音阈值和收束行为 |

通用预期结果：控件状态立即反映到画面且不造成布局跳动；最小值不得高于最大值；
无效范围被校正并说明；“恢复默认”只恢复当前映射，不覆盖其他映射、预设或作品；
导出并重新导入工程后，所有映射开关、强度、范围和反向状态保持一致。

## 27. Task 7 TDD：专业工作台与图层工作流

### 27.1 RED：专业控件和图层交互缺失

在 Task 1-6 的 45 项基线上先加入两种桌面视口、完整控件、范围/数值输入配对、
图标可访问名称、图层增删改排序显隐锁定复制、快捷键输入保护和真实渲染循环测试。
三项新增检查中，既有壳层已满足桌面三栏尺寸检查；其余两项分别因专业控件节点和
图层行为缺失而失败。

```text
PASS_COUNT=46
FAIL_COUNT=2
```

### 27.2 GREEN：紧凑工作台、统一循环和图层命令

- `1440x900` 与 `1366x768` 均保持 `44px` 单行顶栏、左右 `286px` 面板、中央舞台和
  `82px` 监视器，无页面级横向溢出。
- 左栏提供工程/声音、手动/自动/混合、自动续画、六预设、画笔参数和六类声音映射；
  右栏提供图层列表、增删改排序显隐锁定复制、混合/透明度及画布设置。
- 所有 range 都配对固定 `60px` 可编辑 number 输入；10 个图标按钮均具有 `title`、
  `data-tip` 和 `aria-label`。
- ProjectEngine、StrokeEngine、AudioEngine 与 renderer 接入同一 RAF；页面隐藏时 RAF
  归零，恢复后只保留一个工作台循环。关闭麦克风后循环继续渲染无声作品。
- 锁定活动层不能写入；快捷键在输入、选择和可编辑焦点内不执行撤销或录制。

```text
PASS_COUNT=48
FAIL_COUNT=0
```

## 28. Task 8 TDD：IndexedDB、JSON 与 PNG

### 28.1 RED：持久化和导出 API 缺失

先加入 `sound-brush-db@1`、`recent/snapshot`、800ms autosave、刷新恢复、dirty/status、
原子 JSON 导入、非法/高版本拒绝和独立 PNG 像素测试。实现前新增三项分别因
`clearRecentProject`、恢复入口和 `exportProjectJson` 不存在而失败。

```text
PASS_COUNT=48
FAIL_COUNT=3
```

### 28.2 GREEN：版本化恢复、工程 I/O 状态机和独立图像编码

- IndexedDB 固定为 `sound-brush-db` version `1`、object store `projects`，记录包含
  schema version、工程签名、保存时间和已验证工程副本。
- 工程变更后 800ms 防抖写入 `recent`；稳定写入后清除 dirty，失败时保留内存工程并
  显示持久错误状态。刷新后由恢复对话框原子替换工程。
- JSON 导入在读取前检查 File 大小、解析后再整体替换；非法 JSON 和 version `999`
  均保持当前工程签名不变。JSON、PNG 共用本地下载与 URL 回收流程。
- PNG 使用 renderer 的独立导出路径；`320x180` 基线 PNG 大于 20KB，非空像素 11000+
  且不改变主画布尺寸、trail index 或 lastFrame。

```text
PASS_COUNT=51
FAIL_COUNT=0
```

## 29. Task 9 TDD：WebM 录制

### 29.1 RED：CaptureEngine、配置和真实媒体缺失

在 56 项基线上先加入状态机、codec 顺序、120 秒硬上限、录制专用轨道释放、
720/1080 与 30/60 配置、固定宽监视器及 3 秒 fake-media WebM 测试。原有 56 项保持
通过，新增三项分别因 `CaptureEngine`、录制对话框和真实录制入口缺失而失败。

```text
PASS_COUNT=56
FAIL_COUNT=3
```

### 29.2 GREEN：独立录制画布和资源边界

- `CaptureEngine` 按 `idle/preparing/recording/stopping/ready/error` 管理状态，重复启动
  返回 `InvalidStateError`，120 秒到达后以 `limit` 原因停止。
- codec 按 VP9/Opus、VP8/Opus、通用 WebM 顺序探测；录制画布锁定 1280x720 或
  1920x1080 及 30/60 FPS。
- 仅克隆可选麦克风轨道，停止或失败后释放录制视频轨道和克隆音轨，不停止
  `AudioEngine` 正在使用的源麦克风。
- UI 区分准备、录制、停止、成功和失败；只有非空 Blob 成功完成时触发下载。
- 3 秒 Chromium fake-media 样本为可加载的 `video/webm`，体积大于 10KB；停止后
  两条录制专用轨道均为 `ended`，源麦克风仍为 `live`。

```text
PASS_COUNT=59
FAIL_COUNT=0
```

## 30. Task 7-8 复审五项 TDD

### 30.1 RED：工作台控件未连接到最终渲染和输入边界

在 51 项基线上增加五项独立探针，分别覆盖图层合成、symmetry/透明 PNG、快捷键
修饰键与交互目标、控件可访问名称、单 RAF 调度。实现前五项均稳定失败：

- WebGL、Canvas2D 和 PNG 的低/高 opacity 像素签名相同，add/multiply 签名相同；
- symmetry `1 -> 4` 的渲染笔触数仍为 `[1,1]`，透明导出 alpha 全为 `255`；
- Ctrl/Meta/Alt/Shift+R 均被页面劫持，Ctrl+Space 和按钮 Space 也触发暂停；
- 33 个 range/number/select 中有 19 个缺少关联 label 或 ARIA 名称；
- RAF 停止后 pointer/strokechange/project change 仍同步完整 render 3 次。

```text
PASS_COUNT=51
FAIL_COUNT=5
```

### 30.2 GREEN：图层合成、透明导出、输入边界和统一调度

- `frameStrokes` 统一注入图层 opacity/blendMode，并按 `1..8` symmetry 做确定性径向展开；
  WebGL 使用对应 blend function，Canvas2D 使用对应 composite operation。
- 透明只作为离屏导出 frame 标志传入；WebGL compose 和 Canvas2D export 保留作品
  alpha，普通舞台仍以工程背景合成且角落 alpha 为 `255`。
- R/Space 仅在无修饰、非交互且非可编辑焦点触发；Ctrl/Cmd+R 不 preventDefault，
  按钮 Space 保留原生行为，Ctrl/Cmd+Z 继续受输入焦点保护。
- 全部 33 个 range/number/select 均可通过 label、`aria-label` 或
  `aria-labelledby` 计算可访问名称。
- pointer、strokechange 和工程 change 只置渲染 dirty；停止 RAF 后同步 render 为 0，
  启动后的第一个 RAF 恰好完整 render 1 次。

```text
PASS_COUNT=56
FAIL_COUNT=0
```

## 31. Task 10 TDD：小屏和全屏 performance mode

### 31.1 RED：移动命令入口、顶部面板和全屏工具栏缺失

先加入 `390x844`、`844x390` 的画布主体、顶栏保留、溢出/重叠/文字、触控隔离、
左右面板互斥滚动、visualViewport、聚焦字段及全屏 2.5 秒隐藏恢复测试。实现前新增
三项因移动模式/更多入口、面板和 performance toolbar 缺失而失败。

### 31.2 GREEN：可视视口驱动的单列工作台

- 860px 以下保留麦克风、三模式、录制和更多；监视器压缩为波形、音量和节拍。
- 左右面板固定从顶端滑入，header sticky、内容独立滚动且互斥；舞台可见区域点击关闭。
- `visualViewport.height/offsetTop` 写入 CSS 变量，安全区、旋转和字段聚焦均保持可见。
- canvas 使用 `touch-action:none`，面板和菜单使用 `pan-y`，页面无横向滚动。
- 全屏 stage 只保留画布、状态和紧凑工具栏；2.5 秒无操作隐藏，指针、触摸或键盘恢复；
  `prefers-reduced-motion` 下取消过渡但保留状态变化。

截图基线：

```text
/tmp/sound-brush-qa-screenshots/mobile-portrait.png
/tmp/sound-brush-qa-screenshots/mobile-landscape.png
/tmp/sound-brush-qa-screenshots/desktop-fullscreen.png
PASS_COUNT=62
FAIL_COUNT=0
```

## 32. Task 11 TDD：自适应质量和恢复

### 32.1 RED：质量 manager 和统一运行时生命周期缺失

在 62 项基线上加入三项测试：质量迟滞/录制冻结、页面隐藏恢复单循环、DPR/ResizeObserver/
WebGL 降级/卸载保存/持久错误。实现前均因 `AdaptiveQualityManager` 或运行时实例缺失失败。

### 32.2 GREEN：质量预算、暂停恢复和持久状态

- 质量等级固定为 high、balanced、saver；120 个 28ms 慢帧降一级，10 个慢帧不变，
  300 个 12ms 稳定帧可升一级。录制期间冻结等级和 1920x1080 等导出尺寸。
- 粒子比例、辉光强度、内部 renderScale 和 DPR cap 随等级变化；质量变化和
  ResizeObserver/窗口 DPR 变化统一重建尺寸。
- 页面隐藏时暂停 renderer、音频分析和唯一 RAF，清空帧统计；恢复后 renderer/audio
  恢复且只存在一个 RAF。
- WebGL lost 显示持久恢复状态，restored 清除；恢复失败切换 Canvas2D 并保留持久兼容
  状态。录制和本地存储错误共用同一持久错误区。
- dirty 或录制中的 `beforeunload` 同步写入带工程签名的本地恢复快照并阻止静默离开。

```text
PASS_COUNT=65
FAIL_COUNT=0
```

## 33. Task 9-11 最终复审七项 TDD

### 33.1 RED：资源事务、运行预算和移动输入边界不完整

在 65 项基线上增加七项独立探针。实现前原有 65 项全部通过，新增七项稳定失败：

- 音频校验失败发生在视频 capture track 纳入清理集合之前，轨道保持 `live`；
- `renderer-lost` 仅更新状态，当前录制继续运行且专用轨道未释放；
- 手动 high/balanced/energy-saving 只改变 DPR，粒子和 glow 仍读取 manager；
- DPR-only 变化没有监视器，backing size 只能等待普通 resize；
- 非零 `visualViewport.offsetTop` 下 app 仍从 layout viewport 顶部开始；
- stage 关闭面板或恢复全屏工具栏后，同一个 pointer 继续进入画笔绑定器；
- 移动和全屏关键按钮高度仅 30..40px。

```text
PASS_COUNT=65
FAIL_COUNT=7
```

### 33.2 GREEN：事务清理、单例监视和首事件消费

- captureStream 视频轨道创建后立即纳入事务资源；音频校验、MediaStream、MediaRecorder
  构造或 start 任一阶段失败均只停止一次并进入 error。
- WebGL context lost 以 `context-lost` 中断录制，错误状态先释放录制专用资源，不生成下载。
- 手动 high/balanced/energy-saving 分别固定 high/balanced/saver 的粒子、glow、renderScale
  和 DPR cap；仅 auto 跟随 `AdaptiveQualityManager`。
- 单例 DPR monitor 同时使用 resolution media query 和 1 秒轻量检查；DPR-only 变化重建
  backing size，media query 始终只有一个活动 change listener。
- 小屏 app 固定在 `offsetTop..offsetTop+height`，顶部面板和菜单使用同一坐标系；键盘与
  visualViewport 滚动后不产生顶部移出或底部空白。
- 面板关闭和隐藏全屏工具栏恢复会消费首个 pointer；下一 pointer 才进入 StrokeEngine。

## 34. 生产工作流最终审查八项 TDD

### 34.1 RED：录制、恢复、导出、性能与交互边界缺失

在 72 项完整基线上加入八个独立自动化探针。实现前要求原有 72 项继续通过，
新增探针分别准确暴露以下问题，而不是 Playwright、fake media 或测试服务器错误：

1. 120 秒自动停止未经过与手动停止相同的 `finalized` 事件和下载入口；开始下一次
   录制会清空上一份可取的非空 Blob。
2. 启动恢复只读取 IndexedDB `recent`，未校验并比较同步
   `localStorage/sound-brush-beforeunload` 的 `savedAt`；恢复后同步备份仍残留。
3. WebM 帧直接把舞台 backing canvas 拉伸到目标尺寸，没有使用目标宽高的独立
   renderer；工程与目标宽高比不一致时没有明确的 `contain` letterbox 与 `cover`
   几何策略。
4. 主 RAF 每次通过 `ProjectEngine.project` 对完整工程执行 `structuredClone`；200 笔触
   项目在没有工程变更时仍重复重建 frame 工程快照。
5. WebGL context lost 只暂停 renderer；Pointer Events 和 StrokeEngine 自动更新仍可
   产生隐藏笔触，页面 hidden 期间直接分发 pointer 也可落笔。
6. PNG 超过纹理上限时宽高分别裁切，破坏原始比例；WebGL/Canvas2D 临时导出
   renderer 在读回或绘制异常时没有 `finally` 销毁保证。
7. slider 使用永久 merge key；两次独立 pointer 拖动被合并成一次历史操作。
8. 六类声音映射 UI 只有开关和强度，缺少 min/max、反向和单项恢复默认；全屏工具栏
   缺少模式和清场；移动面板/菜单关闭后焦点不返回触发按钮。

### 34.2 GREEN 验收契约

- CaptureEngine 对 `user` 与 `limit` 统一生成一次 `finalized` 事件；UI 只监听该事件
  下载。`getFinalizedResult()` 在下一次录制开始后仍返回上一份非空 Blob，直到新的
  录制成功完成。
- 启动时分别验证同步备份与 IndexedDB recent 的格式、版本、签名和工程内容，忽略
  无效候选并选择 `savedAt` 较新的有效记录；用户恢复或放弃后移除同步备份。
- WebM 使用固定目标像素的录制 canvas 和独立 renderer。默认 `contain`：4:3 工程
  输出到 1920x1080 时内容为 1440x1080、左右各 240px letterbox；`cover` 几何也有
  确定性结果。1080p backing size 必须真实为 1920x1080。
- ProjectEngine 提供只读、按版本稳定的 frame snapshot；未变更时主 RAF 复用同一
  工程引用，工程提交后版本递增并重建一次。200 笔触性能探针中 RAF 的
  `structuredClone` 调用数为 0。
- context lost 和 document hidden 期间 pointer 与 auto update 同时停用；已有草稿被
  取消且不提交，context restored/visible 后恢复一套交互和循环。
- PNG 按单一比例收敛到纹理上限；2000x1000 在 1000 上限下输出 1000x500。所有临时
  renderer 在成功和异常路径都恰好销毁一次。
- range 的 `pointerdown/input/pointerup` 定义一个 merge 手势；同一手势多帧只占一条
  历史，两次拖动占两条并可逐次撤销。
- 每类映射可编辑强度、min、max、反向并单项恢复默认；全屏工具栏提供三模式和清空
  活动层；关闭移动面板或菜单后焦点回到可见触发按钮。

实现完成后的完整自动化基线应提升为：

```text
PASS_COUNT=80
FAIL_COUNT=0
```
- portrait 关键触控目标至少 44px，空间受限横屏至少 40px，均保持在 viewport 内。
- 生命周期 QA 等待真实 render/audio update；显式停止工作台循环后 pending RAF 必须为 0，
  不再用固定睡眠掩盖采样抖动或泄漏。
- visualViewport 与移动面板几何 QA 不使用固定过渡时长；监听目标 `transitionend`，并以
  rect/transform/visibility 连续两次稳定作为最终条件，统一设置 2 秒总超时。无动画或
  `prefers-reduced-motion` 环境仍必须通过稳定采样验证最终状态。

最终完整回归基线：

```text
PASS_COUNT=72
FAIL_COUNT=0
```

## 34. 每次提交的最低检查

```bash
node --check tmp/sound-brush-qa.js
node tmp/sound-brush-qa.js
node -e "const fs=require('fs');const h=fs.readFileSync('tmp/sound-brush.html','utf8');if(!h.includes('<!DOCTYPE html>'))process.exit(1)"
git diff --check -- tmp/sound-brush.html tmp/sound-brush-qa.js docs/sound-brush-core-test-plan.md
```

最低通过标准：所有命令退出码为 `0`，自动化输出没有页面错误、未处理异常或失败项。
