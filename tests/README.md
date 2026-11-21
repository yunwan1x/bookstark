# 测试目录

## 分层

- `ui/`：Go 编写的模板、样式、交互约束测试。测试入口自动定位仓库根目录，原有模板和静态资源引用保持不变。
- `browser/`：JavaScript 单元测试与 Playwright 浏览器回归。`repo-root.cjs` 统一定位资源路径，支持从仓库根目录或其他目录调用。
- 根目录的五个 `*_browser*_test.go`：使用主程序 `EmbedFS` 的端到端测试入口，继续与 `main` 包同目录，保证测试的仍是生产嵌入资源。
- `models/`、`controllers/`、`middleware/` 等包中的 Go 测试继续与对应代码放在一起。

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

只运行根目录的 `go test .` 不再包含 UI 约束测试；完整回归应运行 `go test ./...`。
