# 14 EdgeTTS真流式听书与后台播放（实施前设计）

参考14-streaming-audio.png：听书标题栏、真实文档名和书籍名、音色与倍速、当前段落/真实分段数量、上一段/暂停继续/下一段/停止。无已知总时长时不造进度条和分钟数。窄屏、大字体按Wrap换行，内容整体滚动。后台通知提供相同操作；返回阅读器可继续播放，切换账号/空间或退出登录必须停止并释放HTTP及播放器。

现有Go协议：GET /api/ai/tts/voices 返回顶层 voices；POST /api/ai/tts/stream {text,voice}，登录Cookie/CSRF和同源约束。每请求1—800 Unicode码点、16KiB请求体；成功是 application/x-ndjson。audio帧base64内容每帧≤16KiB；done帧bytes必须等于已收MP3字节且非零；error或缺done不算完成。单段最多1MiB、服务25秒超时、单用户最多2并发，客户端只保持当前段及受控预取，不并发预加载整本书。

必须边收audio帧边交给MP3解码播放，不等done后转完整文件，也不用系统语音合成冒充EdgeTTS。分段按Markdown AST可读文本提取，跳过代码/图片URL/HTML脚本，保留段落与句读；每段控制在约200码点并不拆Unicode字符。对超长内容分页/明确提示，不静默截断。停止、换段、换音色实际中断请求，旧generation不能继续出声；断流停止并显示可重试，不假装正常结束。

音频仅受限内存缓冲，不建立音频磁盘缓存；选择StreamAudioSource而非LockCachingAudioSource，完整缓存只在用户未来明确要求离线下载时单独设计。系统解码器内部缓存不等同应用主动写音频文件。just_audio文档说明流源走本机HTTP代理，Android需允许localhost；凭据仅由BookstarkClient请求真实服务器，不能泄漏到播放器URL或日志。[just_audio官方文档](https://pub.dev/documentation/just_audio/latest/)；[StreamAudioResponse](https://pub.dev/documentation/just_audio/latest/just_audio/StreamAudioResponse-class.html)。未知总长的MP3流须实测首次音频早于done、分段连续、停止释放、失败处理，不能只证明字节解码。

后台使用平台媒体会话/前台mediaPlayback服务，音频焦点、耳机拔出、电话中断、通知权限与锁屏暂停继续必须处理；依照[audio_service官方文档](https://pub.dev/documentation/audio_service/latest/index.html)及[Android前台服务声明](https://developer.android.com/develop/background-work/services/fgs/declare)。前后台播放必须真机验收，无设备时保留“实现中/回归中”，不能用单元测试或浏览器替代。

初始只接服务器支持的四个音色，从真实voices接口读取，不假造离线音色。本地空间AI/朗读适配器另需实现，不能用灰按钮计为完成。AI回复朗读应复用同一控制器和流解码，避免双播放器同时朗读。

测试：NDJSON任意UTF8分片/CRLF/空行/帧上限/错误/bytes不符/无done/取消；首块先于done到播放器；慢消费者内存上限与背压；200/800码点及emoji；真实无敏感内容MP3解码、前后台/锁屏/切换空间、文件系统无新增音频缓存、320dp英文200%键盘与视觉对照。当前为设计，尚未接入播放器依赖或实现14。
