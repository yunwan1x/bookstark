# 共享 Markdown 附件接口核实 · 2026-11-10
实现时核实 controllers/share.go UploadShareEditImage：/api/shares/:identify/edit/uploads 仅接受 RichDocumentType / PresentationType，Markdown 返回400。Flutter PublicShareAttachments.add 明确拒绝上传；不能借用登录账户 DAV 或伪造支持。
本阶段纸夹入口因此采用原生对话框插入已有公开链接：名称、HTTP(S)地址、作为图片；图片限当前服务器公开附件，普通链接通过既有外链确认。打开对话框前固定正文和CM6选择范围、锁定输入；取消不改正文，返回先GET核实能力及上下文。后台/远端变化/超时拒绝插入，保留拟插入链接供复制。此入口不打开系统文件选择器，也不声称共享Markdown上传已实现。原计划文件上传需未来服务端明确支持后单独设计验证；本次不修改Go生产行为。原型纸夹入口、编辑/预览/未知/冲突/暂停主页面保持原方案；上传措辞以本勘误为准。全部45组仍未完成。
