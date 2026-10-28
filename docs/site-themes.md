# BookStark 独立网站主题

主题列表只包含三个独立选项：

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
