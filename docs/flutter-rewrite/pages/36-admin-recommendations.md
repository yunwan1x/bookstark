# 36 标签推荐：实现前设计
2026-11-07，内置imagegen单页原型与完整提示词已保存，数值/标签均设计示例，未实现验收。浅蓝推荐策略/数量/手动精选卡，底部保存；白底深蓝蓝色按钮、16dp边距12dp圆角48dp目标，320dp200%字体单列可滚动，键盘避让。

使用真实 GET/PUT /api/labels/recommendation-settings；GET所有登录用户可读但本管理页面仍fresh验证owner role0，PUT要求管理员。body完整为strategy（recent/total/book/bookmark/manual）、manual_labels字符串数组、page_size整数1–50。此专用端点一次保存这三项配置，服务端回执返回规范化完整配置；与admin/settings仅dirty键的其余页面区分，不把它误记为任意系统配置更新。不得提交其他未知设置键。

models/label.go 会Trim策略与手动标签，丢弃空白/重复项并保序，最多取50项，标签UTF8<=100字节，底层逗号连接存储。沿用已有LabelRecommendationSettings.writeBody的字符/分隔符保护，超过50项在客户端明确提示而不是静默裁掉；输入文案说明保存后整理、回读呈现实际规范结果。仅更改数量也必须带上reviewed策略/完整手动列表，不能把未加载值当默认。手动标签普通多行输入，无预览调用/私密标签计数。现有标签管理页与本新管理页的配置含义相同，不另建本地缓存。

会话更换/权限丢失清空并取消，保存冻结；只有实际成功receipt才已确认，成功后GET失败重试只读。结果未知显式GET核对并采用，不能通过当前值匹配断言原请求提交或自动重发。离开保存/放弃/继续。需要专用endpoint字段/CSRF/前缀/身份与未知回执fakeHTTP、真实Go隔离SQL、窄屏widget、NAS redroid；全36/45未完成。

实施中：原型后已写入受限字段数据层、Flutter表单与控制器，并接入系统设置内部导航。子页专项检查已通过（具体日志在next-stage/admin36-app-integration）；完整视觉/后端/ARM64 redroid验收待完成，不作为整组验收。确认框绑定当前设置内部Navigator，会话退出清空所有owned控制器并移除内部确认框。
