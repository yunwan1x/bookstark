# 本机代理辅助工具

这里是特定开发机使用的 Mihomo / Codex 代理工具，与 BookStark 服务启动无关。

- `compose.yml`：Mihomo 容器示例。先在本目录的 `mihomo/config.yaml` 放置自己的配置，再执行 `docker compose -f tools/dev-proxy/compose.yml up -d`（从仓库根目录运行）。相对挂载路径以 Compose 文件所在目录为基准。
- `proxy.sh`：为指定本机 Codex 后台进程设置代理。包含开发机路径与重启操作，使用前需要检查并修改，不能作为通用启动脚本。

不要将代理凭据提交到仓库；本目录的 `mihomo/config.yaml` 已加入忽略规则。
