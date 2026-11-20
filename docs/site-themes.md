# BookStark 独立网站主题

主题列表只包含四个独立选项：

1. 默认（light）：原有蓝色浅色主题，不改它的配色、字体和组件外观。
2. NVIDIA（nvidia）：黑色与石墨色背景、绿色主操作、硬朗小圆角、粗体标题和小型绿色标记，无磨砂模糊。
3. Apple（apple）：浅灰白色背景、Action Blue 操作色、系统字体、600 字重标题、柔和圆角与轻量磨砂导航。手机端关闭模糊以节省资源。

NVIDIA 与 Apple 不融合，两个选项可以分别选择，切换后分别显示各自风格。
默认选择仍然为 light。旧主题及未发布的融合主题值回退至默认。
选择保存在当前浏览器，通过 storage 事件同步其他标签页。
不改变用户背景设置、内容、权限、布局和功能；HTML 文章内部独立样式不覆盖。
绿色实心按钮使用黑色文字，Apple 蓝色按钮使用白色文字。
字体使用系统回退，不分发专有字体或品牌 Logo，不增加外部字体依赖。
为适应控制台的信息密度，保留原有行高，不照搬营销官网的大标题与大留白；
NVIDIA 使用系统最小 4px 圆角，Apple 卡片使用系统 10px 圆角。

## 参考来源

下载仓库：<https://github.com/yunwan1x/awesome-design-md>

参考版本：`3b605329240ce735b510037cca322f1831fdd7f8`。
完整下载：`/root/github/awesome-design-md`。
这些是第三方网站设计分析，不是 NVIDIA / Apple 官方规范。

- [NVIDIA DESIGN.md](https://github.com/yunwan1x/awesome-design-md/blob/3b605329240ce735b510037cca322f1831fdd7f8/design-md/nvidia/DESIGN.md)
- [Apple DESIGN.md](https://github.com/yunwan1x/awesome-design-md/blob/3b605329240ce735b510037cca322f1831fdd7f8/design-md/apple/DESIGN.md)

## 实现

- `static/css/variables.css`：默认令牌及两个独立主题的作用域样式。
- `static/js/theme.js`：三个选项、回退、跨标签页同步与编辑器明暗同步。
- 各模板首屏初始化：三个选项使用与运行时一致的映射，避免闪烁。
- `templates/profile.html`：默认、NVIDIA、Apple 三个选择项。
- `static/css/cherry-theme-dark.css`：仅 NVIDIA 的深色 Markdown 适配；Apple 走现有浅色编辑器。

## 玻璃主题（glass）

个人设置 → 用户主题 → 玻璃（Glass）。默认主题仍为 light。玻璃主题使用 dark 明暗模式，刷新、跨标签页与编辑器均同步。

`static/css/glass.css` 在独立作用域内覆盖材质，不改变布局尺寸：深蓝背景、紫蓝弧形光带、半透明烟色面板、模糊背景、细高光边缘、浅紫选中按钮。背景 SVG 为本地资源；可选科学背景仍保留设置。手机端列表降低模糊开销，减少透明度偏好下提高表面不透明度。

登录/注册/密码页、主站、独立编辑器均在首屏初始化中识别 glass。`glass-tools.js` 仅为两个第一方 Short / 协作会议分享 iframe 注入可撤销的材质层，不修改文章正文或其他用户 HTML。切换其他主题会禁用该层。

设计参照：工作区 `artifacts/glass-imagegen/all-pages/` 的 38 张原型。审核截图和结果位于 `artifacts/glass-implementation/`。原型中的日期、文字和个别 AI 生成的布局偏差不用于改动真实内容或页面布局。
