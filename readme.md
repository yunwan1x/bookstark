# BookStark

BookStark 是一个支持自托管的个人知识管理与工作台应用，将笔记、文章、待办、书籍文档、书签和服务器资产集中管理。后端使用 Go，数据存储使用 SQLite，支持桌面端、手机端及 PWA 安装使用。

## 主要功能

| 模块 | 功能 |
| --- | --- |
| 个人首页 | 汇总各模块最新 10 条记录，按创建或更新时间查看，点击直达对应内容；支持板块显隐、排序和宽度调整，布局按账号保存 |
| 笔记与文章 | 记录日常想法、撰写文章，支持 Markdown、HTML 内容编辑、标签和分享 |
| 待办 | 管理任务、完成状态与提醒设置 |
| 书籍 | 以书籍和文档树组织内容，适合知识手册、教程和长期资料整理 |
| 书签与导航 | 收藏链接、标签分类、书签导入和导航展示 |
| 专题与标签 | 聚合相关内容，按主题组织知识 |
| 分享 | 分享书籍和文章，提供分享管理与评论功能 |
| 资产管理 | 管理 SSH 主机、凭据和 WebDAV 服务，使用网页终端、远程文件管理和 Docker 管理；仅管理员可访问 |
| 文件与图片 | 上传管理、图片浏览、本地 WebDAV 文件服务 |
| AI 辅助 | 配置 OpenAI 兼容接口或 Anthropic 接口，支持编辑器内容辅助；首页助手可检索当前账号文字资料、总结，以及确认后创建私有笔记和待办 |
| 系统管理 | 用户管理、系统设置、数据导入导出、回收站和管理看板 |

界面支持中文与英文、明暗主题、响应式布局和全局搜索。PWA 支持静态资源缓存及部分离线能力；个人首页和需要实时权限校验的操作仍依赖网络，并非所有功能都能离线使用。

### 首页 AI 助手（第一版）

在系统设置中启用 AI，填写现有的服务地址、API Key 和**支持工具调用**的模型，首页将出现「AI 助手」按钮。沿用 OpenAI 兼容的 `/chat/completions` 或 Anthropic 的 `/v1/messages` 接口，无需额外向量数据库。仅能聊天、不支持工具调用的服务无法完成资源操作。

首页使用 SSE 流式响应，实时显示检索/读取/起草进度和回答文字；服务端每 10 秒发送心跳。工具参数全部接收并校验后才执行，草稿在完整回答保存成功后才展示确认按钮。中断的回答标记为未完成，不作为执行结果，也不自动重试。关闭窗口或点击停止会取消当前请求；若完成事件在网络中丢失，应先刷新核对状态。请求头不带 `Accept: text/event-stream` 的 API 客户端仍使用原 JSON 响应。反向代理需允许长连接并关闭响应缓冲，接口会发送 `X-Accel-Buffering: no`。

流式事件为 `round`（开始本轮回答）、`progress`（工具执行阶段）、`delta`（文字增量）、`ping`（心跳）、`error` 或 `done`。HTTP 200 或连接关闭不代表成功；只有 `done` 表示会话已保存，其 `session_id` 用于随后通过 `GET /api/ai/assistant` 获取完整记录。流式正文是临时预览，不发送工具参数或模型内部思考。两种模型协议均要求完整结束标记，截断、异常结束和超限响应会拒绝提交。

- 可以搜索笔记、文章、待办、书签描述、书籍介绍、书籍章节和专题问题，并按需读取、总结。当前正文读取仅支持 Markdown，不读取网页、附件、HTML/脑图等编辑器内容；每次检索最多 20 条，单条读取最多 12,000 字符，会标明截断。
- 可以起草私有 Markdown 笔记或顶层待办。核对草稿内容与日期，点击「确认创建」才会落库；聊天中说“确认”不会直接执行。草稿有效期 24 小时，重复确认不会重复创建。
- 每个账号有一个共享会话，多标签页不能同时处理。对话最多 20 轮，超限后新建会话；新会话会清空对话并取消未确认草稿，不删除已创建记录。旧草稿及操作结果在该账号新建会话时清理超过 30 天的记录。
- 管理员也只能让助手读取自己的内容。密码保护内容、服务器凭据、SSH/WebDAV 资产不提供给模型；第一版不支持修改、删除、批量操作或执行服务器命令。
- 提问、历史对话和工具检索的内容会发送给已配置的 AI 服务，请按自身隐私需求选择服务。回答可能有误，关键结论应核对原文。对话保存在服务器，不写入浏览器持久缓存；助手必须联网，失败操作不会进入离线队列。
- 单次请求最多 7 轮模型调用、每轮最多 5 个工具调用，最多生成 5 个草稿，服务端超时 150 秒；调用会消耗所配置服务的额度。界面提供停止等待、刷新、来源链接和确认结果。

模型只提供受限工具的参数，服务端校验账号和参数；资源创建复用现有模型方法，与确认结果在同一数据库事务提交。操作结果持久化，stdout 仅输出账号、草稿 ID 和状态，不输出对话、正文或密钥。协议参考：[OpenAI 工具调用](https://developers.openai.com/api/docs/guides/function-calling)、[Anthropic 工具定义](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools)。

## 技术栈

- 后端：Go 1.25.4、Gin、Go HTML Templates。
- 数据：SQLite（`modernc.org/sqlite`，无需独立数据库服务）。
- 前端：JavaScript、Tailwind CSS、CSS 变量及项目共享组件。
- 认证：JWT、Cookie、API Token；写操作包含相应的权限与 CSRF 校验。
- 分发：生产构建将静态资源和模板嵌入二进制，支持 Docker 部署。

## 本地运行

准备 Go（以 [go.mod](go.mod) 为准）、Python 3 和 Git。以下命令适用于 Linux 开发环境。

```bash
git clone https://github.com/yunwan1x/bookstark.git
cd bookstark
go mod download

# 请替换为自己的随机密钥和管理员密码，不要提交到 Git。
export JWT_SECRET='replace-with-a-long-random-secret'
export ADMIN_ACCOUNT='admin'
export ADMIN_PASSWORD='replace-with-a-strong-password'
export TZ='Asia/Shanghai'

python3 build.py
```

启动后访问 **http://localhost:8089**。首次启动会初始化数据库并创建管理员账号，登录信息由上述环境变量指定。已有管理员账号的密码不会因修改 `ADMIN_PASSWORD` 自动改变。

注意：`build.py` 默认会先编译，再通过 `pkill -f bookstark` 停止匹配进程并启动程序。请在独立开发环境中使用，不要在承载其他 BookStark 实例的机器上直接执行默认启动命令。

仅构建、不启动或停止进程：

```bash
python3 build.py --build --tags timetzdata
```

需要从磁盘读取模板和静态资源进行开发时：

```bash
python3 build.py --tags dev
```

交叉编译示例：

```bash
python3 build.py --build --tags timetzdata \
  --goos linux --goarch arm64 --output dist/bookstark-linux-arm64
```

构建脚本会更新资源哈希及 Service Worker 缓存版本。默认使用单并发编译和 `GOMEMLIMIT=300MiB`；该值是 Go 的软内存目标，不是整个编译进程的硬上限。

## Docker 部署

GitHub Release 工作流会将 Linux amd64/arm64 多架构镜像发布到 `ghcr.io/yunwan1x/bookstark`：

```bash
docker pull ghcr.io/yunwan1x/bookstark:latest
# 生产部署也可以固定到具体版本，例如 :v0.1.1。
```

推送 `v*` 版本标签，或在 GitHub Actions 的 `release` 工作流中手动填写版本号即可触发。版本格式为 `v主版本.次版本.修订号`，也支持 `-rc.1` 等预发布后缀。正式版本提供带 `v`、不带 `v` 和 `latest` 标签；预发布版本不更新 `latest`。手动发布已有标签时，所选分支/引用必须与标签指向相同提交。

镜像发布使用 `GITHUB_TOKEN` 和工作流的 `packages: write` 权限，无需维护额外仓库密码。GHCR 新包的可见性需在 GitHub Packages 设置中确认：私有包拉取需要登录，设为 Public 后可匿名拉取。

仓库根目录现有的 [docker-compose.yml](docker-compose.yml) 只包含 Mihomo 服务，**不是 BookStark 的启动配置**。可在仓库根目录另建 `compose.bookstark.yml`，使用下面的独立示例：

```yaml
services:
  bookstark:
    build:
      context: .
      dockerfile: Dockerfile
    image: bookstark:local
    restart: unless-stopped
    ports:
      - "127.0.0.1:8089:8089"
    environment:
      PORT: "8089"
      MODE: release
      TZ: Asia/Shanghai
      DB_PATH: /data/bookstark.db
      WEBDAV_DB_PATH: /data/bookstark-webdav.db
      JWT_SECRET: "${JWT_SECRET:?请设置 JWT_SECRET}"
      ADMIN_ACCOUNT: admin
      ADMIN_PASSWORD: "${ADMIN_PASSWORD:?请设置 ADMIN_PASSWORD}"
      BOOKSTARK_ASSET_SECRET: "${BOOKSTARK_ASSET_SECRET:?请设置资产加密密钥}"
    volumes:
      - ./data:/data
    logging:
      driver: json-file
      options:
        max-size: "3m"
        max-file: "1"
```

设置好环境变量后启动：

```bash
export JWT_SECRET='replace-with-a-long-random-secret'
export ADMIN_PASSWORD='replace-with-a-strong-password'
export BOOKSTARK_ASSET_SECRET='replace-with-a-separate-long-random-secret'
docker compose -f compose.bookstark.yml up -d --build
docker compose -f compose.bookstark.yml logs --tail=100 bookstark
```

示例端口仅绑定本机；对外使用时应配置 HTTPS 反向代理，并支持 WebSocket 与 SSE。不要直接向公网暴露未经保护的管理入口。手机安装 PWA 通常需要 HTTPS（本机 `localhost` 开发环境除外）。

上面的源码镜像构建需要启用 BuildKit（工作流已配置 Buildx），不具备 `deploy.sh` 的 systemd 硬资源限制。小内存机器可直接拉取 GHCR 镜像，或在构建机生成镜像再传输到运行服务器。

## 配置说明

配置优先级为：**已提供的命令行参数 > 环境变量 > 配置文件 > 内置默认值**。只有部分配置提供命令行参数。

开发模式读取 `conf/app.conf`；生产模式读取构建时嵌入的配置，运行时调整应优先使用环境变量。没有配置文件时会使用环境变量与默认值。

| 环境变量 | 用途 / 默认行为 |
| --- | --- |
| `PORT` | HTTP 服务端口，默认 `8089` |
| `MODE` | 运行模式，默认 `release` |
| `DB_PATH` | 主数据库路径，默认 `./bookstark.db` |
| `WEBDAV_DB_PATH` | WebDAV 文件数据库，默认位于主数据库同目录，名为 `bookstark-webdav.db` |
| `JWT_SECRET` | 登录令牌签名密钥；生产环境必须设置独立随机值 |
| `JWT_EXPIRE` | 登录令牌有效期的默认配置，默认 `168h`（7 天）；实际会话策略还需结合系统设置 |
| `ADMIN_ACCOUNT` | 初始化管理员账号，默认 `admin` |
| `ADMIN_PASSWORD` | 初始化管理员密码，必须自行设置强密码 |
| `BOOKSTARK_ASSET_SECRET` | 资产凭据加密密钥，应固定保存并与备份一同妥善保管 |
| `TZ` | 时区，例如 `Asia/Shanghai` |

不要把真实账号密码、API Key、SSH 私钥、生产配置或数据库提交到仓库。特别注意：生产构建会嵌入 `conf/`，即使本地 `conf/app.conf` 已被 Git 忽略，也不应把生产秘密写入它后分发构建产物。使用额外的环境变量文件时，同样应放在仓库外或明确加入忽略规则。

## 现有远程部署流程

[deploy.sh](deploy.sh) 用于本项目现有服务器的发布流程，**不是开箱即用的通用部署脚本**。首次用于其他环境时，请先检查并修改脚本中的镜像名、远程主机、SSH 端口、远程目录和 Compose 文件名。

```bash
# 默认：通过镜像仓库推送和拉取
./deploy.sh <版本号>

# 备选：通过 SSH 传输镜像
DEPLOY_TRANSPORT=ssh ./deploy.sh <版本号>
```

脚本依次执行：受限编译 → 构建并传输镜像 → 提交并推送 Git → 更新远端 Compose 服务。它不再创建或上传源码压缩包。

运行需要 Linux/systemd、Go、Python 3、Docker、Git、SSH，以及对应权限和凭据。默认编译限制为单核、850 MiB 内存上限、700 MiB 内存压力阈值和 1 GiB swap 上限；swap 上限不代表会自动创建 swap。

发布前务必检查 `git status` 和 `git diff`：脚本使用 `git add -A` 提交所有未忽略的变更，并推送当前分支。Git 推送失败时不会进入远程重启阶段。部署期间不要并行运行测试或其他编译任务。

## 数据与备份

完整备份至少应覆盖：

- `DB_PATH` 指定的主数据库。
- `WEBDAV_DB_PATH` 指定的 WebDAV 数据库。
- 工作目录下的 `data/`，包括上传文件 `data/uploads/` 和分享评论数据库 `data/share_comments.db`。
- 运行配置与资产加密密钥；不要将秘密放入公开备份。

Docker 示例将 `/data` 持久化到宿主机 `./data`。本地运行时，默认主数据库位于项目根目录，不能只备份 `data/`。

建议停服务后复制完整数据，或采用 SQLite 一致性备份方式；不要只复制正在写入的 `.db` 文件而忽略 WAL 状态。系统提供的数据导出用于内容迁移，不应直接等同于包含所有运行数据和密钥的完整灾难恢复备份。升级前备份，并定期验证恢复流程。

## 开发与测试

```bash
# 小内存环境使用单并发测试；测试结果取决于本机依赖与运行环境。
GOMAXPROCS=1 GOMEMLIMIT=300MiB go test -p=1 ./...

# 首页相关后端回归
GOMAXPROCS=1 GOMEMLIMIT=300MiB go test -p=1 ./controllers \
  -run 'TestHome|TestPersonalHomeEnglish' -count=1

# 首页助手：账号隔离、模型协议、草稿确认、事务回滚、重复提交
GOMAXPROCS=1 GOMEMLIMIT=220MiB go test -p=1 ./models ./controllers -run TestAssistant -count=1
# 安装 Playwright 并指定 Chromium 路径后运行（模拟网络，不访问线上数据）
CHROMIUM_PATH=/path/to/chromium node home_assistant_browser_test.cjs
```

仓库还包含 `*_browser_test.cjs` 等浏览器回归脚本，需要单独准备 Playwright/Chromium，运行前查看相应脚本的依赖与环境变量。

```text
conf/         配置加载
controllers/  页面与 API 控制器
middleware/   登录、权限、语言等中间件
models/       SQLite 数据模型与初始化
routers/      路由注册
services/     后台服务
templates/    Go HTML 模板
static/       前端脚本、样式及静态资源
i18n/         中英文翻译
docs/         设计与测试文档
scripts/      辅助脚本
build.py      构建、资源版本生成与本地启动
deploy.sh     现有环境的远程发布脚本
```

新增界面应复用现有组件、兼容手机布局，并同时补充中英文文案。项目约定见 [CLAUDE.md](CLAUDE.md)，辅助工具说明见 [scripts/README.md](scripts/README.md)。

## 许可证

项目采用 [Apache License 2.0](LICENSE)。随附的第三方组件遵循各自许可证，分发时请保留对应声明。
