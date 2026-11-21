# 仓库结构

[← 项目首页](../readme.md)

根目录保留项目入口、Go 模块信息、构建入口和通用说明。测试、设计稿及特定开发机工具按用途归档，业务代码遵循 Go 的包结构。

```text
bookstark/
├── main.go / embed*.go          服务入口、生产资源嵌入与开发模式
├── go.mod / go.sum              Go 模块及依赖
├── browser_integration_test.go    依赖主程序 EmbedFS 的集成测试入口
├── build.py / deploy.sh         常用构建、现有环境发布入口
├── Dockerfile                  标准源码镜像构建入口
├── readme.md / LICENSE          项目介绍与许可
├── CLAUDE.md                    项目开发约定
├── .github/                    GitHub 工作流
├── conf/                       配置加载
├── controllers/                HTTP 页面与 API 控制器
├── middleware/                 认证、权限、CSRF 等中间件
├── models/                     数据模型与 SQLite
├── routers/                    路由与模板注册
├── services/                   后台及外部服务
├── internal/                   项目内部公共代码
├── cmd/                        独立命令行工具
├── templates/                  Go HTML 模板
├── static/                     前端资源与第三方编辑器产物
├── i18n/                       中英文翻译
├── tests/
│   ├── ui/                     模板、CSS、交互约束测试
│   └── browser/                JavaScript / Playwright 测试
├── deploy/docker/              专用发布镜像 Dockerfile.release
├── docs/
│   ├── screenshots/            README 演示截图
│   ├── mockups/                静态设计稿与原型归档
│   └── ...                     部署、功能、设计与测试文档
├── scripts/                    数据迁移、图标及客户端构建辅助脚本
├── tools/                      前端组件构建与开发辅助工具
│   └── dev-proxy/              可选的本机代理配置示例与脚本
├── integrations/               外部工具接入代码
└── android/                    Android 客户端工程
```

## 为什么这些文件继续在首层？

- `main.go` 与 `embed*.go` 保留现有入口，使 `go build .`、`build.py`、Docker 和 Release 构建继续使用同一方式。`go:embed` 不能向父目录引用资源，因此 `static/`、`templates/`、`conf/` 与入口保持当前相对位置。
- `browser_integration_test.go` 中的浏览器集成测试直接使用 `main` 包的 `EmbedFS`。保留在根包可以验证生产嵌入内容；JavaScript 测试主体统一在 `tests/browser/`。
- `Dockerfile` 是常用构建工具的默认入口；仅供部署脚本使用的 `Dockerfile.release` 归入 `deploy/docker/`。
- `build.py` 和 `deploy.sh` 是已有工作流、文档约定的入口，保留路径可避免开发与发布命令发生不必要变化。
- Go 各业务包保留独立目录；与包相关的单元测试就近放置，不集中搬走。

## 不属于源码结构的本地文件

`bookstark` 可执行文件、`data/`、`*.db`、`__pycache__/`、`dist/` 等是运行数据或构建产物，已由忽略规则排除。整理源码不删除本地数据库、上传文件或运行配置。若只构建产物，可使用：

```bash
python3 build.py --build --output dist/bookstark
```

测试命令见 [测试目录说明](../tests/README.md)，服务部署见 [部署与维护手册](usage-and-deployment.md)。
