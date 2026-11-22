# 20 图片库：实施前设计与真实协议

页面：20-images.png列表/网格与选择状态、20-image-preview.png原生缩放/元信息/复制/分享、20-image-upload.png队列/分类/逐项结果；各自先出图和文档后写对应UI。Slate/蓝色/8dp白卡/4dp网格/48dp控件，中英320dp/200%及滚动。图片内容由用户真实数据决定，不能用原型示例照片充当生产图片。无WebView。

真实服务不是私有“我的图片”：登录GET /api/uploads显示全库，未按memberID筛选且列表无owner字段；GET /upload-files/*公开，不要求登录。删除需owner或admin（checkOwnership）；普通客户端无法根据缺失字段预判owner，保留实际服务端权限校验和403错误，不默认自己拥有全部图片。上传前清楚显示公开链接范围。SQLite本地模式明确只属于本地空间，不把本地URI说成公网链接。

列表GET /api/uploads?page=&page_size=&keyword=&category=：data(id,file_name,url,thumb_url,category,mime_type,file_size,width,height,create_time)，真实total/page/page_size/total_pages；keyword是旧Go LIKE通配语义，不声称字面转义。分类editor/note/drawing。total属于当前筛选；total_size是全库SUM(file_size)，只含存储主图文件，未含缩略图/缓存/孤立文件，不是磁盘总占用，也不是筛选结果大小。使用“图片合计”并在详情说明范围。图片URL与缩略图必须归当前服务器的upload-files路径；跨主机、userinfo、反斜线、点目录不带Cookie、不当同源可信图片读取。

列表真实分页追加；页漂移/重复ID要求刷新核对。刷新已加载全部页，避免删除后跳页漏项。选择可跨已加载页保留，按钮明确“选择已加载”，不能当全库全选；清空/换筛选前处理选择，不暗中把不同查询的同名记录合并。批量删除是逐项请求、非原子事务；保留失败/未确认项及结果，停止只停止后续项，当前请求结果仍核对。不能把部分失败显示为全部成功。

上传POST /api/uploads multipart字段file、category。Go按实际文件内容检查允许格式/大小，默认10MiB但可配置，原生不伪造固定服务器上限。静态JPEG/PNG/非动画GIF等会转WebP及按配置缩放；动画GIF和SVG原样存储。mime_type记录输入探测类型，不等于存储字节格式，file_name也是原始名；file_size是存储主图大小。SVG宽高可能0，显示未知，不用原型假尺寸填0。预览按真实字节解码，而非仅凭mime或扩展名。

全局SHA256去重：GET /api/uploads/by-hash/:hash读取既有记录，POST也会复用全库相同hash，不赋予新所有权。回复仅含id/url/thumb_url/file_name/width/height/file_size，没有category/mime/time，不能用上传分类/当前时间伪造完整canonical记录。区分上传引用回复与完整列表模型；返回库页后真实刷新。已复用对象可能属于另一分类/另一个账号，不能宣称每次成功都新增一张或获得删除权限。网络未知先查hash核对，不盲目重POST；取消请求仍可能在服务器落盘，显示需核对，不能承诺回滚。字节发送进度只标“已发送”，完整确认以真实响应为准。

预览复用真实读取边界，公开图片读取不附外站登录凭据，不跟随跨站重定向。栅格按有限分辨率解码，GIF使用真实动画解码；SVG走原生Flutter矢量，无HTML/JS。将SVG解析前的大小、DOCTYPE/ENTITY、外部引用/脚本与不支持特性明确处理，内嵌栅格也检验解码尺寸；保留原文件与分享字节，不偷偷修改上传源。选用Flutter官方维护flutter_svg 2.3.2与当前兼容xml，锁文件记录版本；官方文档说明CSS并非全支持、vector compiler不支持filters，不能把局部渲染当完全还原。参考https://pub.dev/packages/flutter_svg/versions/2.3.2 与 https://pub.dev/packages/vector_graphics_compiler 。复杂SVG是实际待验收项。

复制链接/Markdown使用真实url和原名转义；本地URI仅在本空间可用，明确不能当外部分享链接。分享用现有系统分享发送实际原文件字节，失败/取消不记成功。InteractiveViewer缩放、错误/重试、尺寸未知、文件已消失等保持元信息。图片库删除可能破坏已有正文引用，服务没有使用次数/引用检测API，不伪造“未被使用”。公开文件Cache-Control一年，删除不能承诺清除所有缓存。旧Go先删DB再删磁盘，磁盘删除失败仅日志且仍返回成功；客户端不得把API确认当作全世界副本已清除。需要核对时从原始同源链接带新查询验证当前可访问性，区分库记录移除与链接仍可访问。

本地：旧附件物理文件仅32位hex ID，无扩展名/登记表，原名在Markdown的bookstark-attachment:///ID/filename中。先读真实元信息/已引用URI并识别文件字节，无法恢复原名时显示真实存储ID，不伪造原名。SQLite10新增图片元信息/哈希/分类/路径登记并保留1—9表；本地数据不会自动上传。删除使用同目录隔离重命名+DB事务，提交后清理，失败有可重试状态，不能因扫描残留自动复活已删记录。只管理实际附件目录的常规文件，跳过符号链接/目录，不走出应用目录；未知附件不冒充图片。

验收：真实Go全库范围/过滤统计/去重/转换字节/原名与MIME差异/403/删除，SQLite9→10保留/旧附件发现/事务/清理失败，队列部分成功/取消/未知结果核对/不重复、SVG/动态图/栅格尺寸/外链零请求、真实文件选择与系统分享、中英截图和Android。当前20已接入真实图片库/上传/预览/删除和本地SQLite10登记，状态为实现中，不标完成。完整快照证据见validation目录。

实施进展：图片主文件统计保留真实全局范围；懒加载网格/列表、真实分页、原生SVG/栅格/动画、系统文件选择、原图分享、Markdown转义已接入。批量删除保留失败项，未知结果只读核对；本地隔离文件清理失败后重启仍可读取待清理记录并重试。GIF原生多帧测试通过，实际Go去重、WebP转换、SVG原字节、删除后可用性探测已通过；完整测试/新APK仍在构建时不引用上一阶段APK为本阶段交付。

剩余验收：真实Android多机/系统文件选择与分享、进程终止后的上传队列恢复（45）、复杂SVG兼容、原型逐项视觉修正（统计排列、顶部控件、卡片菜单尚未逐项验收）。实际所有者权限403目前有客户端测试，跨账号Go场景待补；旧Go删除文件失败和并发去重竞态需要后端后续改造，客户端不能承诺清除所有缓存或并发恰好一次。
