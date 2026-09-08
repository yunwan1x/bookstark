# 数据迁移脚本

将数据从 Memos、Mindoc、Linkding 三个源数据库导入到 bookstark.db。

## 用法

```bash
# 完整迁移（默认导入全部三个源）
python3 scripts/migrate_data.py

# 只统计不写入（dry-run）
python3 scripts/migrate_data.py --dry-run

# 只导入 memos
python3 scripts/migrate_data.py --skip-mindoc --skip-linkding

# 只导入 mindoc
python3 scripts/migrate_data.py --skip-memos --skip-linkding

# 只导入 linkding
python3 scripts/migrate_data.py --skip-memos --skip-mindoc

# 指定源数据库目录
python3 scripts/migrate_data.py --source-dir /path/to/databases

# 指定目标数据库路径
python3 scripts/migrate_data.py --target /path/to/bookstark.db

# 不创建备份
python3 scripts/migrate_data.py --no-backup
```

## 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--source-dir` | 源数据库所在目录 | 项目根目录 |
| `--target` | 目标数据库路径 | `bookstark.db` |
| `--dry-run` | 只统计不写入 | 否 |
| `--skip-memos` | 跳过 memos 导入 | 否 |
| `--skip-mindoc` | 跳过 mindoc 导入 | 否 |
| `--skip-linkding` | 跳过 linkding 导入 | 否 |
| `--no-backup` | 不创建备份 | 否 |

## 迁移规则

### 1. Memos -> md_blogs (笔记)

| 源字段 | 目标字段 | 说明 |
|--------|----------|------|
| content | blog_content | 去除图片语法 |
| payload.tags | md_label + md_label_relation | relation_type='blog' |
| created_ts | create_time | Unix 时间戳转 datetime |
| updated_ts | modify_time | Unix 时间戳转 datetime |
| pinned | is_pinned + pin_order | 置顶 |
| visibility | visibility | PUBLIC->1, 其他->0 |
| - | blog_type | 固定为 'note' |
| - | blog_identify | 自动生成 'note-xxxxxxxx' |

- 跳过 row_status='ARCHIVED' 的 memo
- 从内容第一行提取 blog_title（去除 markdown 标题标记）

### 2. Mindoc -> md_books + md_documents + md_blogs

| 源表 | 目标表 | 说明 |
|------|--------|------|
| md_books | md_books | 保留原始 book_id，映射部分字段 |
| md_documents | md_documents | 保留原始 document_id，markdown 去除图片 |
| md_blogs | md_blogs | blog_type: 0->'article', 1->'note' |
| md_label | md_label | 去除 book_number 列 |
| md_label_relation | md_label_relation | 重新映射 label_id 和 resource_id |

- 所有数据归属 admin 用户
- identify 冲突时追加后缀
- 文档 identify 为空或 'null' 时自动生成
- 博客 blog_identify 为空时自动生成

### 3. Linkding -> md_bookmark

| 源字段 | 目标字段 | 说明 |
|--------|----------|------|
| title / website_title | title | 优先 title，回退 website_title |
| url | url | 唯一约束 (url, member_id) |
| description / website_description / notes | description | 回退链，截断 500 字符 |
| favicon_file | favicon | 为空时从 URL 生成 |
| date_added | create_time | |
| date_modified | modify_time | |
| - | nav_visible | 固定为 0 |
| - | is_public | 固定为 0 |
| bookmarks_tag + bookmarks_bookmark_tags | md_label + md_label_relation | relation_type='bookmark' |

- 跳过 is_deleted=true 的书签
- 跳过 is_archived=true 的书签
- URL+member_id 相同时跳过（去重）

## 备份与回滚

迁移前自动创建 `bookstark.db.bak` 备份文件。如需回滚：

```bash
cp bookstark.db.bak bookstark.db
```

## 旧脚本

- `import_linkding.py` -- 仅导入 linkding 书签（已被本脚本替代）
- `migrate_mindoc.py` -- 仅导入 mindoc 数据（含密码加密逻辑，已被本脚本替代）

注意：旧的 `migrate_mindoc.py` 包含博客密码的 bcrypt 哈希和 AES-256-GCM 内容加密逻辑，
本脚本不包含该功能，直接导入原始密码和内容。如需加密迁移，请使用旧脚本。

## 依赖

仅使用 Python 标准库 (`sqlite3`, `json`, `re`, `os`, `sys`, `shutil`, `argparse`, `datetime`, `secrets`, `urllib.parse`)，无需安装第三方包。