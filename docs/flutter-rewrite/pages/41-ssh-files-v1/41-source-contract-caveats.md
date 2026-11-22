# 41 实施接口核对补充（源码推断，尚非实测）
2026-11-07；40冻结期只写隔离设计目录，不修改应用。

- services/asset_files.go fileInfoEntry只返回mode.Perm()，SFTP清单不含特殊位。Chmod将八进制直接转fs.FileMode，没有把04000/02000/01000转换为Go高位ModeSetuid/ModeSetgid/ModeSticky；不得在客户端宣称特殊位可往返保留。第一版权限矩阵只处理普通rwx，并明确已有接口的特殊位观察限制，实际SFTP与shell契约必须覆盖。
- Remove先Stat而非Lstat，目标若为指向目录的链接会按目录处理；递归可能遍历链接目标。客户端不得为symlink/other提供递归删除，普通目录也需明确递归确认和目标核对；这不是服务端竞态防护或沙箱。
- Copy的文件目标使用Create，Rename/shell mv和cp可能覆盖既有目标。新目标必须fresh父目录读取，已有目标不静默覆盖。检查后仍有并发窗口，UI不能承诺原子不覆盖。
- Download在写出二进制后出错可能追加JSON，HTTP200/Content-Type不足以证明成功。按fresh清单size精确核对已收到字节，超长/短缺都不得完成导出；无服务端摘要不宣称内容身份原子核对。
- withSFTPOrShell已建立SFTP后的操作错误直接返回，不会重复shell执行同一操作；仅连接/子系统失败进入fallback。需要真实无SFTP容器验证，不把mock当fallback。
- shell目录清单通过find NUL分隔，应覆盖引号、美元、反引号、换行及前导短横文件名。路径不经shell本地插值。
- 上传path.Join会规范化目录/文件名，必须约束单一非空文件名、拒绝点段/斜线/反斜线/NUL及被TrimSpace改变的路径，校验成功回执的实际路径；不能把网络已发送进度当已保存。
- Go正文读取保留UTF8字节/BOM/CRLF；WebView textarea默认规范化换行，不能直接把textarea.value作为原始字节保存。编辑器桥必须显式保留原始换行策略；混合换行需要映射或直接拒绝破坏性转换，并回归未改动保存逐字节一致。

## 权限推断修正（优先于上文最初源码推断）
核对与生产go.sum一致的pkg/sftp v1.13.10模块源码后，toChmodPerm明确保留低位POSIX setuid/setgid/sticky。因此“Go fs.FileMode转换导致特殊位写入被丢弃”这一最初推断撤回。真实契约r1因该错误预期而失败，未计通过且资源已清理；新r2在断言前记录实际stat值，要求两种协议均能写入4640。SFTP列表只用mode.Perm()而省略特殊位的观察仍成立，普通0640设置会清除特殊位，客户端矩阵明确提示这一影响，不承诺保留未观察到的特殊位。权限矩阵第一版仍只提供普通rwx。
