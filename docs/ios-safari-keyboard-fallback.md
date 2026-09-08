# iOS Safari 软键盘适配方案

## Context

BookStark 编辑器使用 Cherry Markdown（内嵌 CodeMirror 6），采用全屏布局（`height: 100dvh`）。已配置 `interactive-widget=resizes-content` 让浏览器在软键盘弹出时自动缩小布局视口。

**问题**：iOS Safari 不支持 `interactive-widget=resizes-content`（全版本忽略该属性）。键盘弹出时：
- `window.innerHeight` 和 `100dvh` 保持不变（~844px）
- `visualViewport.height` 正确缩小（~500px）
- 结果：编辑器内容被键盘遮挡

**Chrome Android 正常**：`interactive-widget` 生效，`window.innerHeight` 和 `visualViewport.height` 同步缩小，`100dvh` 自动适配。

**目标**：为不支持 `interactive-widget` 的浏览器（主要是 iOS Safari）添加 `visualViewport` API 降级方案，同时不干扰已支持的浏览器。

## 实现方案

### 检测策略

比较 `window.innerHeight` 和 `visualViewport.height`：
- **键盘打开 且 `interactive-widget` 不生效**：`window.innerHeight - visualViewport.height > 100`
- **键盘打开 且 `interactive-widget` 生效**：两者同步缩小，差值保持很小
- **键盘关闭**：两者近似相等

这样在支持 `interactive-widget` 的浏览器上，降级代码自动成为空操作（no-op），无需浏览器嗅探。

### 代码修改

**文件**：`static/js/editor.js`

**位置**：`window.addEventListener('resize', ...)` 块结束后，`// ======== Book-Only: Document Tree ========` 注释前

**插入代码**：
```javascript
if (window.visualViewport) {
  var _kbBody = document.body;
  function _handleVVResize() {
    var vv = window.visualViewport;
    var diff = window.innerHeight - vv.height;
    if (diff > 100) {
      _kbBody.style.height = vv.height + 'px';
    } else {
      _kbBody.style.height = '';
    }
  }
  window.visualViewport.addEventListener('resize', _handleVVResize);
}
```

### 工作原理

1. **监听 `visualViewport` resize 事件**：键盘打开/关闭时触发
2. **计算差值**：`window.innerHeight - visualViewport.height`
3. **键盘打开时**（差值 > 100px）：设置 `body.style.height = visualViewport.height + 'px'`，覆盖 CSS 的 `100dvh`
4. **键盘关闭时**（差值 ≤ 100px）：清除 `body.style.height`，恢复 CSS 规则
5. **Chrome Android 上**：`window.innerHeight` 同步缩小，差值始终 < 100，`else` 分支清除空的 inline style，零成本

### 为什么这样设计

- **目标元素是 `body`**：body 是最外层 flex 容器（`editor-full-height` class），设置其高度会通过 flex 布局传递到所有子元素，包括 Cherry/CM6 容器。CM6 自带 `ResizeObserver` 会自动检测容器尺寸变化并重排。
- **不用 debounce**：设置 `body.style.height` 是单次 DOM 属性写入，浏览器会批处理到下一帧。CM6 的 `ResizeObserver` 在同一帧周期内捕获变化。
- **100px 阈值**：避免浏览器 chrome（地址栏）显隐导致的误判
- **不比较 `window.outerHeight`**：`outerHeight` 包含浏览器 UI，不可靠
- **不用 `window.resize` 事件**：iOS Safari 键盘弹出时不触发 `window.resize`，只有 `visualViewport.resize` 可靠

## 关键文件

- `static/js/editor.js` - 插入 visualViewport 监听器
- `templates/editor_common.html` - 现有 viewport meta tag（第 8 行）和 `.editor-full-height` CSS，无需修改
- `templates/editor.html` - body 元素结构，无需修改

## 验证方案

### 手动测试

1. **iOS Safari 测试**（iPhone 真机或模拟器）：
   - 运行 `./build.py` 启动开发服务器
   - 在 iOS Safari 中打开编辑器页面（书籍文档或博客）
   - 点击编辑器输入区域，软键盘弹出
   - **预期**：编辑器容器高度缩小，光标和输入区域保持可见，不被键盘遮挡
   - 关闭键盘（点击"完成"或页面其他区域）
   - **预期**：编辑器恢复全屏高度

2. **Chrome Android 测试**（Android 真机或模拟器）：
   - 同样步骤
   - **预期**：行为与之前一致（`interactive-widget` 已生效），降级代码不干扰

3. **桌面浏览器测试**（Chrome/Safari/Firefox）：
   - 同样步骤
   - **预期**：无影响（`visualViewport` 在桌面上不触发或差值始终 < 100）

### 调试验证

在浏览器控制台运行：
```javascript
// 监听 resize 事件，打印差值
window.visualViewport.addEventListener('resize', () => {
  const diff = window.innerHeight - window.visualViewport.height;
  console.log('innerHeight:', window.innerHeight, 'vv.height:', window.visualViewport.height, 'diff:', diff);
});
```

键盘弹出时，iOS Safari 应显示 `diff > 100`，Chrome Android 应显示 `diff ≈ 0`。

### 回归测试

- 测试侧边栏折叠/展开（书籍模式）
- 测试移动端抽屉打开/关闭
- 测试编辑/预览切换（移动端 pager）
- 测试窗口 resize（桌面 ↔ 移动断点切换）
- 测试横屏/竖屏切换（移动端）
