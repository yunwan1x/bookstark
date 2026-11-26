# BookStark 密码箱 & 2FA 验证码 (`vault-2fa`)

零知识前端主密码加密的个人密码箱与离线 TOTP 动态验证码工具包，面向 BookStark 工具市场设计。

## 安全模型（双层加密）

1. **前端主密码锁（零知识端到端加密）**：
   - 使用浏览器原生 Web Crypto API：`PBKDF2-HMAC-SHA256`（600,000 次迭代 + 随机 16 字节 Salt）派生 256 位密钥，每次写入使用新的随机 12 字节 IV 进行 `AES-256-GCM` 认证加密。
   - 主密码与派生密钥仅存在于当前页面内存中，绝不写入 `localStorage`、数据库或网络日志。
   - 支持手动「立即锁定」（`Ctrl/Cmd + Shift + L`）、可配置空闲自动锁定，以及重新生成 Salt/IV 更换主密码。
2. **工作区加密存储与备份**：
   - 密文信封通过 `BookStark.secrets` 存入当前工作区加密凭据目录（服务端额外执行 AES-256-GCM 加密，多端自动同步）。
   - 支持通过 `BookStark.files` 在 `backups/` 保存加密快照，以及导出/恢复 `.bsvault.json` 加密文件（始终保留前端主密码密文）。

## 核心功能

- **离线 TOTP 动态验证码（RFC 6238 / RFC 4226）**：支持 SHA-1 / SHA-256 / SHA-512、6/8 位、自定义周期、倒计时圆环与一键复制。
- **密码本与强密码生成器**：按网站账号、服务器/云、API Token、仅 2FA、其他分类管理，支持星标收藏、即时搜索与无偏差随机强密码生成。
- **多方式兼容导入**：
  - 截图 `Ctrl+V` 粘贴 / 拖拽 / 选图 / 摄像头扫码识别二维码（离线 `jsQR`）
  - 标准 `otpauth://totp/...` 链接与 **Google Authenticator 批量导出二维码（`otpauth-migration://` Protobuf 解码）**
  - Chrome / Edge / Bitwarden / 1Password / KeePass / iCloud 导出的 CSV 批量导入（带重复项检测）
  - `.bsvault.json` 加密备份恢复
- **标准二维码导出**：单条 2FA 离线生成标准 `otpauth://` SVG 二维码（`qrcode-generator`），随时扫回手机验证器。

## 构建与测试

```bash
# 运行核心加密 / TOTP / Protobuf / CSV 单元测试
node --test tools/vault-2fa/tests/vault_core_test.cjs

# 构建可上传到 BookStark 工具市场的 ZIP 包
python3 tools/vault-2fa/build.py --output ../artifacts/vault-2fa
```
