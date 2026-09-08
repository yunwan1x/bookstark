#!/usr/bin/env python3
"""Data migration script for bookstark.

Imports data from:
1. memos_prod.db  -> md_blogs (notes) + md_label + md_label_relation
2. mindoc.db      -> md_books + md_documents + md_blogs + md_label + md_label_relation
3. db.sqlite3     -> md_bookmark + md_label + md_label_relation

Usage:
    python3 scripts/migrate_data.py
    python3 scripts/migrate_data.py --dry-run
    python3 scripts/migrate_data.py --skip-memos --skip-mindoc --skip-linkding
    python3 scripts/migrate_data.py --source-dir /custom/path

All source databases default to the project root directory.
The target database is always bookstark.db in the project root.
"""

import sqlite3
import json
import re
import os
import sys
import shutil
import argparse
import hashlib
import base64
import secrets
from datetime import datetime

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.join(SCRIPT_DIR, '..')

DEFAULT_MEMOS_DB = os.path.join(PROJECT_DIR, 'memos_prod.db')
DEFAULT_MINDOC_DB = os.path.join(PROJECT_DIR, 'mindoc.db')
DEFAULT_LINKDING_DB = os.path.join(PROJECT_DIR, 'db.sqlite3')
DEFAULT_TARGET_DB = os.path.join(PROJECT_DIR, 'bookstark.db')
DEFAULT_BACKUP = os.path.join(PROJECT_DIR, 'bookstark.db.bak')

BATCH_SIZE = 1000

# ---------------------------------------------------------------------------
# Encryption helpers (matching Go backend: AES-256-GCM + PBKDF2)
# ---------------------------------------------------------------------------

ENC_PREFIX = "ENC:v1:"
PBKDF2_ITERS = 100000
KEY_LEN = 32      # AES-256
SALT_LEN = 16
NONCE_LEN = 12    # GCM standard nonce


def encrypt_content(password: str, plaintext: str) -> str:
    """Encrypt plaintext with password using AES-256-GCM.

    Matches the Go EncryptContent function exactly:
    PBKDF2-SHA256, 100000 iterations, 32-byte key.
    Output format: ENC:v1:<base64(salt)>:<base64(nonce)>:<base64(ciphertext)>
    """
    if not password or not plaintext:
        return plaintext
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes
    except ImportError:
        print("  [ERROR] cryptography package required for password encryption.")
        print("         Install with: pip install cryptography")
        sys.exit(1)

    salt = secrets.token_bytes(SALT_LEN)
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=KEY_LEN,
        salt=salt,
        iterations=PBKDF2_ITERS,
    )
    key = kdf.derive(password.encode('utf-8'))
    nonce = secrets.token_bytes(NONCE_LEN)
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, plaintext.encode('utf-8'), None)
    return ENC_PREFIX + base64.b64encode(salt).decode() + ":" + \
        base64.b64encode(nonce).decode() + ":" + \
        base64.b64encode(ciphertext).decode()


def hash_password(password: str) -> str:
    """Hash a password with bcrypt, matching the Go backend's HashPassword."""
    if not password:
        return ""
    try:
        import bcrypt
    except ImportError:
        print("  [ERROR] bcrypt package required for password hashing.")
        print("         Install with: pip install bcrypt")
        sys.exit(1)
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def strip_images(text: str) -> str:
    """Remove markdown image syntax and HTML <img> tags from text.

    - Remove: ![alt](url) and ![alt](url "title")
    - Remove: <img ...> and <img .../>  (including multi-line)
    - Clean up blank lines left behind
    """
    if not text:
        return text
    # Remove markdown images: ![alt](url) or ![alt](url "title")
    text = re.sub(r'!\[([^\]]*)\]\([^)]*\)', '', text)
    # Remove HTML images: <img ...> or <img .../> (handles attributes across lines)
    text = re.sub(r'<img\b[^>]*/?>', '', text, flags=re.IGNORECASE | re.DOTALL)
    # Collapse 3+ consecutive blank lines into 2
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text


def epoch_to_datetime(ts) -> str:
    """Convert Unix epoch seconds to 'YYYY-MM-DD HH:MM:SS' string."""
    if not ts:
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        return datetime.fromtimestamp(int(ts)).strftime('%Y-%m-%d %H:%M:%S')
    except (ValueError, OSError, OverflowError):
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')


def random_hex(n: int = 8) -> str:
    """Generate n random hex characters."""
    import secrets
    return secrets.token_hex(n // 2 + 1)[:n]


def generate_identify(prefix: str, existing: set, length: int = 8) -> str:
    """Generate a unique identify string like 'note-abcd1234'.

    Args:
        prefix: e.g. 'note-', 'blog-', 'doc-'
        existing: set of already-used identify values
        length: number of hex chars
    """
    for _ in range(100):
        ident = f"{prefix}{random_hex(length)}"
        if ident not in existing:
            existing.add(ident)
            return ident
    raise RuntimeError(f"Cannot generate unique identify with prefix '{prefix}'")


def truncate(s: str, max_len: int) -> str:
    """Truncate string to max_len characters."""
    if not s:
        return ''
    return s[:max_len] if len(s) > max_len else s


def generate_favicon_url(raw_url: str) -> str:
    """Generate a favicon URL from a bookmark URL."""
    from urllib.parse import urlparse
    try:
        u = urlparse(raw_url)
        host = u.hostname
        if not host:
            return ''
        scheme = u.scheme or 'https'
        return f"{scheme}://{host}/favicon.ico"
    except Exception:
        return ''


def ensure_admin(conn) -> int:
    """Ensure an admin user exists in md_members and return its member_id.

    Looks for role=0 (admin). Creates one if not found.
    """
    row = conn.execute(
        "SELECT member_id FROM md_members WHERE role = 0 LIMIT 1"
    ).fetchone()
    if row:
        return row[0]

    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    cur = conn.execute(
        "INSERT INTO md_members (account, password, email, role, status, create_time, create_at) "
        "VALUES ('admin', '', 'admin@bookstark.local', 0, 1, ?, 0)",
        (now,)
    )
    conn.commit()
    return cur.lastrowid


_ALLOWED_TABLES = {'md_blogs', 'md_books', 'md_documents'}
_ALLOWED_COLUMNS = {'identify', 'blog_identify'}


def get_existing_identifies(conn, table: str, column: str = 'identify') -> set:
    """Get all existing identify values from a table."""
    assert table in _ALLOWED_TABLES, f"Invalid table: {table}"
    assert column in _ALLOWED_COLUMNS, f"Invalid column: {column}"
    rows = conn.execute(f"SELECT {column} FROM {table} WHERE {column} != ''").fetchall()
    return {r[0] for r in rows}


def get_existing_labels(conn) -> dict:
    """Get existing label_id by label_name mapping."""
    rows = conn.execute("SELECT label_id, label_name FROM md_label").fetchall()
    return {r[1]: r[0] for r in rows}


# ---------------------------------------------------------------------------
# 1. Memos -> Notes (md_blogs + md_label + md_label_relation)
# ---------------------------------------------------------------------------

def migrate_memos(target_db: str, memos_db: str, admin_id: int, dry_run: bool) -> dict:
    """Import memos as notes into md_blogs.

    Returns a dict with statistics.
    """
    stats = {'memos_total': 0, 'memos_imported': 0, 'memos_skipped_archived': 0,
             'memos_skipped_dup': 0, 'memos_skipped_empty': 0,
             'labels_created': 0, 'relations_created': 0}

    if not os.path.exists(memos_db):
        print(f"  [SKIP] memos_prod.db not found: {memos_db}")
        return stats

    src = sqlite3.connect(memos_db)
    tgt = sqlite3.connect(target_db)
    tgt.execute("PRAGMA journal_mode=WAL")
    tgt.execute("PRAGMA busy_timeout=5000")

    # Get all NORMAL memos ordered by created_ts
    memos = src.execute(
        "SELECT id, content, payload, created_ts, updated_ts, pinned, visibility "
        "FROM memo WHERE row_status = 'NORMAL' ORDER BY created_ts"
    ).fetchall()
    stats['memos_total'] = len(memos)

    # Count archived memos
    archived = src.execute(
        "SELECT COUNT(*) FROM memo WHERE row_status = 'ARCHIVED'"
    ).fetchone()[0]
    stats['memos_skipped_archived'] = archived

    # Idempotency: find already-imported memos by their memo_id marker in blog_content
    # We embed a hidden marker "<!-- memo-id:XXX -->" at the end of each imported note
    existing_memo_ids = set()
    for row in tgt.execute(
        "SELECT blog_content FROM md_blogs WHERE blog_type = 'note' AND member_id = ?",
        (admin_id,)
    ).fetchall():
        m = re.search(r'<!-- memo-id:(\d+) -->', row[0] or '')
        if m:
            existing_memo_ids.add(int(m.group(1)))

    # Get existing blog_identify values (both from memos notes and mindoc blogs)
    existing_identifies = get_existing_identifies(tgt, 'md_blogs', 'blog_identify')

    # Get existing labels
    label_name_to_id = get_existing_labels(tgt)

    # Determine pin_order for pinned items
    pinned_count = tgt.execute(
        "SELECT COALESCE(MAX(pin_order), 0) FROM md_blogs WHERE is_pinned = 1"
    ).fetchone()[0]

    imported = 0
    labels_created = 0
    relations_created = 0

    try:
        for memo_id, content, payload_str, created_ts, updated_ts, pinned, visibility in memos:
            # Idempotency check: skip already-imported memos
            if memo_id in existing_memo_ids:
                stats['memos_skipped_dup'] += 1
                continue

            # Strip images from content
            blog_content = strip_images(content or '')
            if not blog_content.strip():
                stats['memos_skipped_empty'] += 1
                continue

            # Embed memo_id marker for idempotency
            blog_content += f"\n<!-- memo-id:{memo_id} -->"

            # Generate blog_identify
            blog_identify = generate_identify('note-', existing_identifies)

            # Parse tags from payload JSON
            tags = []
            if payload_str:
                try:
                    payload = json.loads(payload_str)
                    tags = payload.get('tags', [])
                except (json.JSONDecodeError, TypeError):
                    pass

            # Determine visibility
            vis = 1 if visibility == 'PUBLIC' else 0

            # Determine pinned
            is_pinned = 1 if pinned else 0
            pin_order = 0
            if is_pinned:
                pinned_count += 1
                pin_order = pinned_count

            # Timestamps
            create_time = epoch_to_datetime(created_ts)
            modify_time = epoch_to_datetime(updated_ts)

            # Derive blog_title from first line of content
            first_line = blog_content.strip().split('\n')[0][:200]
            # Strip leading markdown headers
            blog_title = re.sub(r'^#{1,6}\s+', '', first_line).strip()

            if not dry_run:
                tgt.execute(
                    "INSERT INTO md_blogs "
                    "(blog_title, blog_identify, member_id, blog_content, password, "
                    " modify_time, modify_at, create_time, version, blog_type, "
                    " visibility, is_pinned, pin_order) "
                    "VALUES (?, ?, ?, ?, '', ?, 0, ?, 0, 'note', ?, ?, ?)",
                    (blog_title, blog_identify, admin_id, blog_content,
                     modify_time, create_time, vis, is_pinned, pin_order)
                )
                # Query by identify instead of last_insert_rowid for reliability
                row = tgt.execute(
                    "SELECT blog_id FROM md_blogs WHERE blog_identify = ?",
                    (blog_identify,)
                ).fetchone()
                blog_id = row[0] if row else 0

                # Create labels and relations
                for tag_name in tags:
                    tag_name = tag_name.strip()
                    if not tag_name:
                        continue
                    tag_name = truncate(tag_name, 50)

                    # Ensure label exists
                    if tag_name not in label_name_to_id:
                        tgt.execute("INSERT OR IGNORE INTO md_label (label_name) VALUES (?)", (tag_name,))
                        lid = tgt.execute(
                            "SELECT label_id FROM md_label WHERE label_name = ?", (tag_name,)
                        ).fetchone()[0]
                        label_name_to_id[tag_name] = lid
                        labels_created += 1

                    label_id = label_name_to_id[tag_name]

                    # Create relation
                    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    tgt.execute(
                        "INSERT OR IGNORE INTO md_label_relation "
                        "(label_id, resource_id, relation_type, created_at) "
                        "VALUES (?, ?, 'blog', ?)",
                        (label_id, blog_id, now)
                    )
                    relations_created += 1

            imported += 1
            if imported % BATCH_SIZE == 0:
                if not dry_run:
                    tgt.commit()
                print(f"    已导入 {imported} 条笔记...")

        if not dry_run:
            tgt.commit()

    except Exception as e:
        if not dry_run:
            tgt.rollback()
        raise
    finally:
        src.close()
        tgt.close()

    stats['memos_imported'] = imported
    stats['labels_created'] = labels_created
    stats['relations_created'] = relations_created
    return stats


# ---------------------------------------------------------------------------
# 2. Mindoc -> Books/Documents/Blogs/Labels
# ---------------------------------------------------------------------------

def migrate_mindoc(target_db: str, mindoc_db: str, admin_id: int, dry_run: bool) -> dict:
    """Import mindoc data into bookstark.

    Preserves original IDs for referential integrity (books, documents).
    Returns a dict with statistics.
    """
    stats = {'books_imported': 0, 'books_skipped': 0, 'documents_imported': 0, 'blogs_imported': 0,
             'blogs_skipped': 0, 'labels_created': 0, 'labels_reused': 0, 'relations_imported': 0,
             'relations_skipped': 0, 'docs_skipped': 0}

    if not os.path.exists(mindoc_db):
        print(f"  [SKIP] mindoc.db not found: {mindoc_db}")
        return stats

    src = sqlite3.connect(mindoc_db)
    tgt = sqlite3.connect(target_db)
    tgt.execute("PRAGMA journal_mode=WAL")
    tgt.execute("PRAGMA busy_timeout=5000")

    # ID mapping: old_id -> new_id
    label_id_map = {}   # mindoc label_id -> bookstark label_id
    book_id_map = {}    # should be 1:1 since we preserve IDs
    blog_id_map = {}    # mindoc blog_id -> bookstark blog_id

    try:
        # --- Labels ---
        print("    迁移标签...")
        label_name_to_id = get_existing_labels(tgt)

        mindoc_labels = src.execute(
            "SELECT label_id, label_name FROM md_label ORDER BY label_id"
        ).fetchall()

        for old_id, name in mindoc_labels:
            name = name.strip()
            if not name:
                continue
            if name in label_name_to_id:
                label_id_map[old_id] = label_name_to_id[name]
                stats['labels_reused'] += 1
            else:
                if not dry_run:
                    tgt.execute("INSERT OR IGNORE INTO md_label (label_name) VALUES (?)", (name,))
                    lid = tgt.execute(
                        "SELECT label_id FROM md_label WHERE label_name = ?", (name,)
                    ).fetchone()[0]
                    label_name_to_id[name] = lid
                    label_id_map[old_id] = lid
                else:
                    # In dry-run, use old_id as placeholder so relation counting works
                    label_id_map[old_id] = -old_id
                stats['labels_created'] += 1

        # --- Books (preserve IDs) ---
        print("    迁移书籍...")
        existing_identifies = get_existing_identifies(tgt, 'md_books', 'identify')

        books = src.execute("""
            SELECT book_id, book_name, identify, order_index, description,
                   label, doc_count, is_use_first_document, create_time, modify_time
            FROM md_books ORDER BY book_id
        """).fetchall()

        for book_id, name, identify, order_index, desc, label, doc_count, \
            use_first, ctime, mtime in books:

            # Idempotency: skip if book already exists (by book_id)
            existing_book = tgt.execute(
                "SELECT book_id FROM md_books WHERE book_id = ?", (book_id,)
            ).fetchone() if not dry_run else None
            if existing_book:
                book_id_map[book_id] = book_id
                stats['books_skipped'] += 1
                continue

            # Handle identify uniqueness
            if not identify or identify.strip() == '':
                identify = generate_identify('book-', existing_identifies)
            elif identify in existing_identifies:
                # Append suffix
                base = identify
                i = 2
                while identify in existing_identifies:
                    identify = f"{base}-{i}"
                    i += 1
            existing_identifies.add(identify)

            if not dry_run:
                tgt.execute(
                    "INSERT OR IGNORE INTO md_books "
                    "(book_id, book_name, item_id, identify, order_index, description, "
                    " label, doc_count, member_id, create_time, modify_time, is_use_first_document) "
                    "VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (book_id, name, identify, order_index or 0, desc or '',
                     label or '', doc_count or 0, admin_id, ctime, mtime, use_first or 0)
                )
                book_id_map[book_id] = book_id

                # Create label relations from the denormalized label field
                if label and label.strip():
                    label_names = [l.strip() for l in label.split(',') if l.strip()]
                    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    for ln in label_names:
                        ln = truncate(ln, 50)
                        if ln not in label_name_to_id:
                            tgt.execute("INSERT OR IGNORE INTO md_label (label_name) VALUES (?)", (ln,))
                            lid = tgt.execute(
                                "SELECT label_id FROM md_label WHERE label_name = ?", (ln,)
                            ).fetchone()[0]
                            label_name_to_id[ln] = lid
                            stats['labels_created'] += 1
                        lid = label_name_to_id[ln]
                        tgt.execute(
                            "INSERT OR IGNORE INTO md_label_relation "
                            "(label_id, resource_id, relation_type, created_at) "
                            "VALUES (?, ?, 'book', ?)",
                            (lid, book_id, now)
                        )
            else:
                book_id_map[book_id] = book_id

            stats['books_imported'] += 1

        # --- Documents (preserve IDs) ---
        print("    迁移文档...")
        docs = src.execute("""
            SELECT document_id, document_name, identify, book_id, parent_id,
                   order_sort, markdown, create_time, modify_time, modify_at,
                   is_open, view_count
            FROM md_documents ORDER BY parent_id, order_sort, document_id
        """).fetchall()

        # Collect all document IDs for parent_id validation
        all_doc_ids = {d[0] for d in docs}

        # Existing identifies per book
        existing_doc_identifies = {}  # book_id -> set of identifies

        for doc_id, name, identify, book_id, parent_id, order_sort, markdown, \
            ctime, mtime, modify_at, is_open, view_count in docs:

            # Idempotency: skip if document already exists (by document_id)
            if not dry_run:
                existing_doc = tgt.execute(
                    "SELECT document_id FROM md_documents WHERE document_id = ?", (doc_id,)
                ).fetchone()
                if existing_doc:
                    continue

            # Skip if book doesn't exist in our mapping
            if book_id not in book_id_map:
                stats['docs_skipped'] += 1
                continue

            # Handle identify: if NULL or 'null' string, generate one
            if not identify or identify.lower() == 'null' or not identify.strip():
                book_key = book_id
                if book_key not in existing_doc_identifies:
                    # Load existing identifies for this book
                    rows = tgt.execute(
                        "SELECT identify FROM md_documents WHERE book_id = ?", (book_id,)
                    ).fetchall()
                    existing_doc_identifies[book_key] = {r[0] for r in rows if r[0]}
                identify = generate_identify('doc-', existing_doc_identifies.get(book_key, set()))
            else:
                identify = identify.strip()

            # Ensure identify is unique within book_id
            book_key = book_id
            if book_key not in existing_doc_identifies:
                rows = tgt.execute(
                    "SELECT identify FROM md_documents WHERE book_id = ?", (book_id,)
                ).fetchall()
                existing_doc_identifies[book_key] = {r[0] for r in rows if r[0]}

            if identify in existing_doc_identifies.get(book_key, set()):
                base = identify
                i = 2
                while identify in existing_doc_identifies.get(book_key, set()):
                    identify = f"{base}-{i}"
                    i += 1

            existing_doc_identifies.setdefault(book_key, set()).add(identify)

            # Strip images from markdown
            clean_markdown = strip_images(markdown or '')

            # parent_id: keep if it references an existing doc, else 0
            if parent_id and parent_id not in all_doc_ids:
                parent_id = 0

            if not dry_run:
                tgt.execute(
                    "INSERT OR IGNORE INTO md_documents "
                    "(document_id, document_name, identify, book_id, parent_id, "
                    " order_sort, markdown, member_id, create_time, modify_time, "
                    " modify_at, is_open, view_count) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (doc_id, name, identify, book_id, parent_id,
                     order_sort or 0, clean_markdown, admin_id, ctime, mtime,
                     modify_at or 0, is_open or 0, view_count or 0)
                )

            stats['documents_imported'] += 1
            if stats['documents_imported'] % BATCH_SIZE == 0:
                if not dry_run:
                    tgt.commit()
                print(f"    已导入 {stats['documents_imported']} 篇文档...")

        # --- Blogs ---
        print("    迁移博客...")
        existing_blog_identifies = get_existing_identifies(tgt, 'md_blogs', 'blog_identify')

        blogs = src.execute("""
            SELECT blog_id, blog_title, blog_identify, member_id, blog_content,
                   password, modify_time, modify_at, create_time, version, blog_type
            FROM md_blogs ORDER BY blog_id
        """).fetchall()

        for blog_id, title, identify, _member_id, content, pwd, mtime, modify_at, \
            ctime, version, blog_type_int in blogs:

            # blog_type: 0 -> 'article', 1 -> 'note'
            blog_type = 'article' if blog_type_int == 0 else 'note'

            # Handle blog_identify - check if already imported
            original_identify = (identify or '').strip()
            if original_identify and original_identify in existing_blog_identifies:
                # Already imported - skip (idempotency)
                if not dry_run:
                    row = tgt.execute(
                        "SELECT blog_id FROM md_blogs WHERE blog_identify = ?",
                        (original_identify,)
                    ).fetchone()
                    blog_id_map[blog_id] = row[0] if row else 0
                else:
                    blog_id_map[blog_id] = blog_id
                stats['blogs_skipped'] += 1
                continue

            # Handle blog_identify uniqueness
            if not identify or not identify.strip():
                identify = generate_identify('blog-', existing_blog_identifies)
            else:
                identify = identify.strip()
                if identify in existing_blog_identifies:
                    base = identify
                    i = 2
                    while identify in existing_blog_identifies:
                        identify = f"{base}-{i}"
                        i += 1
            existing_blog_identifies.add(identify)

            # Strip images from content
            clean_content = strip_images(content or '')

            # Encrypt content and hash password for password-protected blogs
            stored_content = clean_content
            stored_pwd = pwd or ''
            if pwd and pwd.strip():
                encrypted = encrypt_content(pwd, clean_content)
                if encrypted and encrypted.startswith(ENC_PREFIX):
                    stored_content = encrypted
                    stored_pwd = hash_password(pwd)
                else:
                    # Encryption failed, keep plaintext (should not happen)
                    print(f"    [WARN] 加密博客 '{title}' 内容失败，保留明文")

            if not dry_run:
                tgt.execute(
                    "INSERT OR IGNORE INTO md_blogs "
                    "(blog_title, blog_identify, member_id, blog_content, password, "
                    " modify_time, modify_at, create_time, version, blog_type, "
                    " visibility, is_pinned, pin_order) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0)",
                    (title, identify, admin_id, stored_content, stored_pwd,
                     mtime, modify_at or 0, ctime, version or 0, blog_type)
                )
                # Always query by identify instead of relying on last_insert_rowid
                # which is unreliable with INSERT OR IGNORE
                row = tgt.execute(
                    "SELECT blog_id FROM md_blogs WHERE blog_identify = ?",
                    (identify,)
                ).fetchone()
                new_blog_id = row[0] if row else 0
                blog_id_map[blog_id] = new_blog_id

            stats['blogs_imported'] += 1

            # In dry-run mode, populate blog_id_map with a placeholder so
            # label relation counting works (relations will still report 0 since
            # dry-run doesn't write them, but at least skipped count is accurate)
            if dry_run:
                blog_id_map[blog_id] = blog_id  # placeholder with old ID

        # --- Label Relations ---
        print("    迁移标签关联...")
        relations = src.execute(
            "SELECT label_id, resource_id, relation_type FROM md_label_relation ORDER BY id"
        ).fetchall()

        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        for old_label_id, old_resource_id, relation_type in relations:
            new_label_id = label_id_map.get(old_label_id)
            if not new_label_id:
                stats['relations_skipped'] += 1
                continue

            # Map resource_id based on relation_type
            if relation_type == 'blog':
                new_resource_id = blog_id_map.get(old_resource_id)
            elif relation_type == 'book':
                new_resource_id = book_id_map.get(old_resource_id)
            else:
                stats['relations_skipped'] += 1
                continue

            if not new_resource_id:
                stats['relations_skipped'] += 1
                continue

            if not dry_run:
                cur = tgt.execute(
                    "INSERT OR IGNORE INTO md_label_relation "
                    "(label_id, resource_id, relation_type, created_at) "
                    "VALUES (?, ?, ?, ?)",
                    (new_label_id, new_resource_id, relation_type, now)
                )
                if cur.rowcount > 0:
                    stats['relations_imported'] += 1
                else:
                    stats['relations_skipped'] += 1
            else:
                stats['relations_imported'] += 1

        if not dry_run:
            tgt.commit()

    except Exception as e:
        if not dry_run:
            tgt.rollback()
        raise
    finally:
        src.close()
        tgt.close()

    return stats


# ---------------------------------------------------------------------------
# 3. Linkding -> Bookmarks (md_bookmark + md_label + md_label_relation)
# ---------------------------------------------------------------------------

def migrate_linkding(target_db: str, linkding_db: str, admin_id: int, dry_run: bool) -> dict:
    """Import linkding bookmarks into md_bookmark.

    Returns a dict with statistics.
    """
    stats = {'bookmarks_total': 0, 'bookmarks_imported': 0, 'bookmarks_skipped_deleted': 0,
             'bookmarks_skipped_archived': 0, 'bookmarks_skipped_dup': 0,
             'labels_created': 0, 'relations_created': 0, 'labels_backfilled': 0}

    if not os.path.exists(linkding_db):
        print(f"  [SKIP] db.sqlite3 not found: {linkding_db}")
        return stats

    src = sqlite3.connect(linkding_db)
    tgt = sqlite3.connect(target_db)
    tgt.execute("PRAGMA journal_mode=WAL")
    tgt.execute("PRAGMA busy_timeout=5000")

    # Get total count
    stats['bookmarks_total'] = src.execute(
        "SELECT COUNT(*) FROM bookmarks_bookmark"
    ).fetchone()[0]

    # Count deleted and archived
    deleted_count = src.execute(
        "SELECT COUNT(*) FROM bookmarks_bookmark WHERE is_deleted = 1"
    ).fetchone()[0]
    archived_count = src.execute(
        "SELECT COUNT(*) FROM bookmarks_bookmark WHERE is_deleted = 0 AND is_archived = 1"
    ).fetchone()[0]
    stats['bookmarks_skipped_deleted'] = deleted_count
    stats['bookmarks_skipped_archived'] = archived_count

    # Get existing URLs for dedup
    existing_urls = set()
    for r in tgt.execute("SELECT url FROM md_bookmark WHERE member_id = ?", (admin_id,)):
        existing_urls.add(r[0])

    # Get existing labels
    label_name_to_id = get_existing_labels(tgt)

    # Load all tags from linkding
    tag_map = {}  # old_tag_id -> tag_name
    for tid, name in src.execute("SELECT id, name FROM bookmarks_tag ORDER BY id"):
        tag_map[tid] = name

    # Load bookmark-tag associations
    bookmark_tags = {}  # old_bookmark_id -> list of tag_names
    for bid, tid in src.execute("SELECT bookmark_id, tag_id FROM bookmarks_bookmark_tags"):
        tag_name = tag_map.get(tid)
        if tag_name:
            bookmark_tags.setdefault(bid, []).append(tag_name)

    # Get current max order_sort
    max_sort = tgt.execute(
        "SELECT COALESCE(MAX(order_sort), 0) FROM md_bookmark WHERE member_id = ?",
        (admin_id,)
    ).fetchone()[0]

    # Bookmark mapping: old_id -> new_id
    bookmark_id_map = {}

    # Query non-deleted, non-archived bookmarks
    bookmarks = src.execute("""
        SELECT id, url, title, description, website_title, website_description,
               favicon_file, date_added, date_modified, notes
        FROM bookmarks_bookmark
        WHERE is_deleted = 0 AND is_archived = 0
        ORDER BY date_added
    """).fetchall()

    imported = 0
    skipped_dup = 0
    labels_created = 0
    relations_created = 0

    try:
        for b_id, url, title, description, website_title, website_description, \
            favicon_file, date_added, date_modified, notes in bookmarks:

            # Title: use title, fallback to website_title
            if not title or not title.strip():
                title = website_title or ''
            title = truncate(title.strip(), 200)

            # Skip if no URL or empty URL or empty title
            if not url or not url.strip():
                continue
            if not title:
                continue

            # URL dedup
            if url in existing_urls:
                skipped_dup += 1
                continue

            # Description: fallback chain: description -> website_description -> notes
            desc = description or ''
            if not desc.strip():
                desc = website_description or ''
            if not desc.strip():
                desc = notes or ''
            desc = truncate(desc.strip(), 500)

            # Favicon: empty → generate from URL (same as Go backend)
            favicon = generate_favicon_url(url)

            # Timestamps
            epoch = '1970-01-01 00:00:00'
            default_time = '2015-01-01 00:00:00'
            create_time = date_added if (date_added and date_added != epoch) else default_time
            modify_time = date_modified if (date_modified and date_modified != epoch) else create_time

            max_sort += 1

            if not dry_run:
                cur = tgt.execute(
                    "INSERT OR IGNORE INTO md_bookmark "
                    "(title, url, description, favicon, order_sort, label, "
                    " member_id, is_public, is_pinned, nav_visible, create_time, modify_time) "
                    "VALUES (?, ?, ?, ?, ?, '', ?, 0, 0, 0, ?, ?)",
                    (title, url, desc, favicon, max_sort, admin_id, create_time, modify_time)
                )
                new_id = cur.lastrowid
                if new_id:
                    bookmark_id_map[b_id] = new_id
                    existing_urls.add(url)
                else:
                    # INSERT OR IGNORE skipped (url+member_id duplicate)
                    skipped_dup += 1
                    continue

                # Create labels and relations for this bookmark
                tag_names = bookmark_tags.get(b_id, [])
                label_names_for_bookmark = []
                for tag_name in tag_names:
                    tag_name = tag_name.strip()
                    if not tag_name:
                        continue
                    tag_name = truncate(tag_name, 50)

                    # Ensure label exists
                    if tag_name not in label_name_to_id:
                        tgt.execute(
                            "INSERT OR IGNORE INTO md_label (label_name) VALUES (?)", (tag_name,))
                        lid = tgt.execute(
                            "SELECT label_id FROM md_label WHERE label_name = ?", (tag_name,)
                        ).fetchone()[0]
                        label_name_to_id[tag_name] = lid
                        labels_created += 1

                    label_id = label_name_to_id[tag_name]
                    label_names_for_bookmark.append(tag_name)

                    # Create relation
                    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    tgt.execute(
                        "INSERT OR IGNORE INTO md_label_relation "
                        "(label_id, resource_id, relation_type, created_at) "
                        "VALUES (?, ?, 'bookmark', ?)",
                        (label_id, new_id, now)
                    )
                    relations_created += 1

                # Update the denormalized label field
                if label_names_for_bookmark:
                    label_str = ','.join(label_names_for_bookmark)
                    tgt.execute(
                        "UPDATE md_bookmark SET label = ? WHERE bookmark_id = ?",
                        (label_str, new_id)
                    )

            imported += 1
            if imported % 5000 == 0:
                if not dry_run:
                    tgt.commit()
                print(f"    已导入 {imported} 条书签...")

        if not dry_run:
            tgt.commit()

    except Exception as e:
        if not dry_run:
            tgt.rollback()
        raise
    finally:
        src.close()
        tgt.close()

    stats['bookmarks_imported'] = imported
    stats['bookmarks_skipped_dup'] = skipped_dup
    stats['labels_created'] = labels_created
    stats['relations_created'] = relations_created
    return stats


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="数据迁移脚本：从 memos/mindoc/linkding 导入数据到 bookstark.db"
    )
    parser.add_argument('--source-dir', default=PROJECT_DIR,
                        help='源数据库所在目录 (默认: 项目根目录)')
    parser.add_argument('--target', default=DEFAULT_TARGET_DB,
                        help='目标数据库路径 (默认: 项目根目录/bookstark.db)')
    parser.add_argument('--dry-run', action='store_true',
                        help='只统计不写入')
    parser.add_argument('--skip-memos', action='store_true',
                        help='跳过 memos 导入')
    parser.add_argument('--skip-mindoc', action='store_true',
                        help='跳过 mindoc 导入')
    parser.add_argument('--skip-linkding', action='store_true',
                        help='跳过 linkding 导入')
    parser.add_argument('--no-backup', action='store_true',
                        help='不创建备份')
    args = parser.parse_args()

    memos_db = os.path.join(args.source_dir, 'memos_prod.db')
    mindoc_db = os.path.join(args.source_dir, 'mindoc.db')
    linkding_db = os.path.join(args.source_dir, 'db.sqlite3')
    target_db = args.target
    backup_path = target_db + '.bak'

    print("=" * 60)
    print("Bookstark 数据迁移")
    print("=" * 60)
    print(f"源目录:        {args.source_dir}")
    print(f"目标数据库:    {target_db}")
    print(f"Memos 数据库:  {memos_db}")
    print(f"Mindoc 数据库: {mindoc_db}")
    print(f"Linkding 数据库: {linkding_db}")
    if args.dry_run:
        print("*** DRY RUN 模式 - 不写入数据 ***")
    print()

    # Check target DB exists
    if not os.path.exists(target_db):
        print(f"[ERROR] 目标数据库不存在: {target_db}")
        sys.exit(1)

    # Backup
    if not args.no_backup and not args.dry_run:
        print(f"备份 {target_db} -> {backup_path}")
        shutil.copy2(target_db, backup_path)
        print()

    # Get or create admin
    conn = sqlite3.connect(target_db)
    admin_id = ensure_admin(conn)
    conn.close()
    print(f"管理员用户: member_id={admin_id}")
    print()

    all_stats = {}

    # --- Step 1: Memos ---
    if not args.skip_memos:
        print("[Step 1] 导入 Memos -> md_blogs (笔记)")
        print("-" * 40)
        stats = migrate_memos(target_db, memos_db, admin_id, args.dry_run)
        all_stats['memos'] = stats
        print(f"  源笔记总数:     {stats['memos_total']}")
        print(f"  跳过(已归档):   {stats['memos_skipped_archived']}")
        print(f"  跳过(已导入):   {stats['memos_skipped_dup']}")
        print(f"  跳过(内容为空): {stats['memos_skipped_empty']}")
        print(f"  导入笔记数:     {stats['memos_imported']}")
        print(f"  新增标签数:     {stats['labels_created']}")
        print(f"  新增标签关联:   {stats['relations_created']}")
        print()

    # --- Step 2: Mindoc ---
    if not args.skip_mindoc:
        print("[Step 2] 导入 Mindoc -> md_books + md_documents + md_blogs + md_label")
        print("-" * 40)
        stats = migrate_mindoc(target_db, mindoc_db, admin_id, args.dry_run)
        all_stats['mindoc'] = stats
        print(f"  导入书籍数:     {stats['books_imported']}")
        print(f"  跳过书籍数:     {stats['books_skipped']}")
        print(f"  导入文档数:     {stats['documents_imported']}")
        print(f"  跳过文档数:     {stats['docs_skipped']}")
        print(f"  导入博客数:     {stats['blogs_imported']}")
        print(f"  跳过博客数:     {stats['blogs_skipped']}")
        print(f"  新增标签数:     {stats['labels_created']}")
        print(f"  复用标签数:     {stats['labels_reused']}")
        print(f"  导入标签关联:   {stats['relations_imported']}")
        print(f"  跳过标签关联:   {stats['relations_skipped']}")
        print()

    # --- Step 3: Linkding ---
    if not args.skip_linkding:
        print("[Step 3] 导入 Linkding -> md_bookmark")
        print("-" * 40)
        stats = migrate_linkding(target_db, linkding_db, admin_id, args.dry_run)
        all_stats['linkding'] = stats
        print(f"  源书签总数:       {stats['bookmarks_total']}")
        print(f"  跳过(已删除):     {stats['bookmarks_skipped_deleted']}")
        print(f"  跳过(已归档):     {stats['bookmarks_skipped_archived']}")
        print(f"  跳过(URL重复):    {stats['bookmarks_skipped_dup']}")
        print(f"  导入书签数:       {stats['bookmarks_imported']}")
        print(f"  新增标签数:       {stats['labels_created']}")
        print(f"  新增标签关联:     {stats['relations_created']}")
        print()

    # --- Final summary ---
    print("=" * 60)
    print("迁移完成，目标数据库统计:")
    print("=" * 60)

    if not args.dry_run:
        conn = sqlite3.connect(target_db)
        for table in ['md_members', 'md_blogs', 'md_books', 'md_documents',
                       'md_bookmark', 'md_label', 'md_label_relation']:
            count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            print(f"  {table:25s} {count:>6d} 条记录")
        conn.close()
    else:
        print("  (DRY RUN 模式，无数据写入)")

    print()
    if not args.no_backup and not args.dry_run:
        print(f"备份文件: {backup_path}")
        print("如需回滚，请: cp {0} {1}".format(backup_path, target_db))


if __name__ == '__main__':
    main()