# 测试目录

## 分层

- `ui/`：Go 编写的模板、样式、交互约束测试。测试入口自动定位仓库根目录，原有模板和静态资源引用保持不变。
- `browser/`：JavaScript 单元测试与 Playwright 浏览器回归。`repo-root.cjs` 统一定位资源路径，支持从仓库根目录或其他目录调用。
- 根目录的 `browser_integration_test.go`：使用主程序 `EmbedFS` 的端到端测试入口，继续与 `main` 包同目录，保证测试的仍是生产嵌入资源。
- `models/`、`controllers/`、`middleware/` 等包中的 Go 测试继续与对应代码放在一起。
- `tools/ssh-terminal/` 是独立的 Go 模块，带有 WASM 构建、一次性本地 SSH 夹具和 `tests/*.cjs` 浏览器验证。根目录的 `go test ./...` 不跨入该模块；构建、测试顺序与可选真实服务器验证见 [SSH 工具说明](../tools/ssh-terminal/README.md#验证)。常规 CI 另行构建该工具，并执行安装 ZIP 导出回归。

## Go 测试

```bash
# 全部包，包括 tests/ui
GOMAXPROCS=2 GOMEMLIMIT=400MiB go test -p=1 ./...

# 仅 UI 约束
GOMAXPROCS=2 GOMEMLIMIT=400MiB go test ./tests/ui

# 编译全部测试但不执行，适合先检查移动后的包与引用
go test -run '^$' ./...
```

## JavaScript 与浏览器测试

先准备 Node.js、Playwright 及 Chromium。脚本对浏览器路径、测试服务、HTML 快照或媒体样本的要求各不相同，运行前查看对应文件。旧测试中的 `/tmp/*.html` 快照不是仓库提供的固定夹具。

```bash
# 无浏览器的客户端逻辑测试
node --test tests/browser/csrf_client_test.cjs tests/browser/editor_error_test.cjs

# 接入完整 Go 服务与嵌入资源的隔离浏览器测试
# Node 需可解析 playwright；可使用 NODE_PATH 指向本机依赖目录。
BOOKSTARK_BROWSER_TEST=1 go test . -run '^TestHomeBrowser$' -count=1

# HUD 两套主题的独立浏览器回归
node tests/browser/hud_theme_browser_test.cjs
HUD_VARIANT=hud-light node tests/browser/hud_theme_browser_test.cjs
```

只运行根目录的 `go test .` 不再包含 UI 约束测试；主程序的 Go 回归应运行 `go test ./...`，独立 SSH 工具还需按上述说明单独验证。

### 广场工具 AJAX 回归

```sh
BOOKSTARK_BROWSER_TEST=1 NODE_PATH=/path/to/playwright/node_modules \
  go test -p=1 . -run 'TestPublicToolsAJAXBrowser|TestClientToolsMarketNavigationBrowser' -count=1
```

使用隔离的临时工作区与真实页面片段，验证工具和其他标签切换保留右侧栏/播放器、历史筛选恢复、迟到请求和会话隔离、弹窗与事件清理、BFCache 重新挂载，以及原生客户端的本地安装入口。市场目录使用固定测试数据，原市场发布、安装、更新和资源操作另由 `TestToolMarketBrowser` 回归。
