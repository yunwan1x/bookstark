package models

import (
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"

	_ "modernc.org/sqlite"

	"bookstark/conf"
)

var DB *sql.DB

func InitDB(dbPath string) error {
	var err error
	DB, err = sql.Open("sqlite", sqliteDSN(dbPath))
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}

	// 启用 WAL 模式，提升并发读性能
	if _, err := DB.Exec("PRAGMA journal_mode=WAL"); err != nil {
		return fmt.Errorf("set WAL mode: %w", err)
	}
	// WAL 模式下设置 synchronous=NORMAL 大幅提升写入性能
	if _, err := DB.Exec("PRAGMA synchronous=NORMAL"); err != nil {
		return fmt.Errorf("set synchronous: %w", err)
	}
	// 设置 busy_timeout 避免并发写入时立即返回锁错误
	if _, err := DB.Exec("PRAGMA busy_timeout=5000"); err != nil {
		return fmt.Errorf("set busy_timeout: %w", err)
	}
	// 启用外键约束
	if _, err := DB.Exec("PRAGMA foreign_keys=ON"); err != nil {
		return fmt.Errorf("set foreign_keys: %w", err)
	}

	// WAL 模式下读取可并发，放宽连接池限制
	DB.SetMaxOpenConns(5)
	DB.SetMaxIdleConns(5)

	if err := createTables(); err != nil {
		return fmt.Errorf("create tables: %w", err)
	}

	if err := ensureAdmin(); err != nil {
		return fmt.Errorf("ensure admin: %w", err)
	}

	if err := InitDefaultSettings(); err != nil {
		return fmt.Errorf("init settings: %w", err)
	}

	return nil
}

func sqliteDSN(dbPath string) string {
	sep := "?"
	if strings.Contains(dbPath, "?") {
		sep = "&"
	}
	if strings.HasPrefix(dbPath, "file:") || dbPath == ":memory:" {
		return dbPath + sep + "_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)"
	}
	return "file:" + dbPath + sep + "_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)"
}

func createTables() error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS md_members (
			member_id INTEGER PRIMARY KEY AUTOINCREMENT,
			account VARCHAR(100) NOT NULL DEFAULT '' UNIQUE,
			password VARCHAR(1000) NOT NULL DEFAULT '',
			email VARCHAR(100) NOT NULL DEFAULT '' UNIQUE,
			role INTEGER NOT NULL DEFAULT 1,
			status INTEGER NOT NULL DEFAULT 0,
			default_home VARCHAR(30) NOT NULL DEFAULT 'home',
			create_time DATETIME NOT NULL,
			create_at INTEGER NOT NULL DEFAULT 0,
			last_login_time DATETIME
		)`,
		`CREATE TABLE IF NOT EXISTS md_books (
			book_id INTEGER PRIMARY KEY AUTOINCREMENT,
			book_name VARCHAR(500) NOT NULL DEFAULT '',
			item_id INTEGER NOT NULL DEFAULT 1,
			identify VARCHAR(100) NOT NULL DEFAULT '' UNIQUE,
			order_index INTEGER NOT NULL DEFAULT 0,
			description VARCHAR(2000) NOT NULL DEFAULT '',
			label VARCHAR(500) NOT NULL DEFAULT '',
			doc_count INTEGER NOT NULL DEFAULT 0,
			member_id INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME,
			is_use_first_document INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS md_documents (
			document_id INTEGER PRIMARY KEY AUTOINCREMENT,
			document_name VARCHAR(500) NOT NULL DEFAULT '',
			identify VARCHAR(100) NOT NULL DEFAULT '',
			book_id INTEGER NOT NULL DEFAULT 0,
			parent_id INTEGER NOT NULL DEFAULT 0,
			order_sort INTEGER NOT NULL DEFAULT 0,
			markdown TEXT,
			member_id INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME,
			modify_at INTEGER NOT NULL DEFAULT 0,
			doc_type VARCHAR(20) NOT NULL DEFAULT 'markdown',
			is_open INTEGER NOT NULL DEFAULT 0,
			view_count INTEGER NOT NULL DEFAULT 0,
			UNIQUE(book_id, identify)
		)`,
		`CREATE TABLE IF NOT EXISTS md_blogs (
			blog_id INTEGER PRIMARY KEY AUTOINCREMENT,
			blog_title VARCHAR(500) NOT NULL DEFAULT '',
			blog_identify VARCHAR(100) NOT NULL DEFAULT '' UNIQUE,
			member_id INTEGER NOT NULL DEFAULT 0,
			blog_content TEXT,
			blog_desc VARCHAR(500) NOT NULL DEFAULT '',
			password VARCHAR(100) NOT NULL DEFAULT '',
			modify_time DATETIME NOT NULL,
			modify_at INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			version INTEGER NOT NULL DEFAULT 0,
			blog_type VARCHAR(20) NOT NULL DEFAULT 'article',
			editor_type VARCHAR(20) NOT NULL DEFAULT 'markdown',
			visibility INTEGER NOT NULL DEFAULT 0,
			is_pinned INTEGER NOT NULL DEFAULT 0,
			pin_order INTEGER NOT NULL DEFAULT 0,
			location_name VARCHAR(200) NOT NULL DEFAULT '',
			latitude REAL,
			longitude REAL,
			location_accuracy REAL
		)`,
		`CREATE TABLE IF NOT EXISTS md_label (
			label_id INTEGER PRIMARY KEY AUTOINCREMENT,
			label_name VARCHAR(50) NOT NULL DEFAULT '' UNIQUE
		)`,
		`CREATE TABLE IF NOT EXISTS md_label_relation (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			label_id INTEGER NOT NULL DEFAULT 0,
			resource_id INTEGER NOT NULL DEFAULT 0,
			relation_type VARCHAR(24) NOT NULL DEFAULT '',
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS md_bookmark (
			bookmark_id INTEGER PRIMARY KEY AUTOINCREMENT,
			title VARCHAR(200) NOT NULL DEFAULT '',
			url VARCHAR(500) NOT NULL DEFAULT '',
			description VARCHAR(500) NOT NULL DEFAULT '',
			favicon VARCHAR(500) NOT NULL DEFAULT '',
			order_sort INTEGER NOT NULL DEFAULT 0,
			label VARCHAR(200) NOT NULL DEFAULT '',
			member_id INTEGER NOT NULL DEFAULT 0,
			is_public INTEGER NOT NULL DEFAULT 0,
			is_pinned INTEGER NOT NULL DEFAULT 0,
			nav_visible INTEGER NOT NULL DEFAULT 1,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_tasks (
			task_id INTEGER PRIMARY KEY AUTOINCREMENT,
			content TEXT NOT NULL DEFAULT '',
			due_date VARCHAR(10) NOT NULL DEFAULT '',
			done INTEGER NOT NULL DEFAULT 0,
			parent_id INTEGER NOT NULL DEFAULT 0,
			topic_id INTEGER NOT NULL DEFAULT 0,
			member_id INTEGER NOT NULL DEFAULT 0,
			complete_time DATETIME,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_topics (
			topic_id INTEGER PRIMARY KEY AUTOINCREMENT,
			title VARCHAR(200) NOT NULL DEFAULT '',
			question TEXT NOT NULL DEFAULT '',
			member_id INTEGER NOT NULL DEFAULT 0,
			is_pinned INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_topic_summaries (
			summary_id INTEGER PRIMARY KEY AUTOINCREMENT,
			topic_id INTEGER NOT NULL DEFAULT 0,
			content TEXT NOT NULL DEFAULT '',
			summary_type VARCHAR(20) NOT NULL DEFAULT 'manual',
			order_sort INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_topic_resources (
			topic_resource_id INTEGER PRIMARY KEY AUTOINCREMENT,
			topic_id INTEGER NOT NULL DEFAULT 0,
			resource_type VARCHAR(20) NOT NULL DEFAULT '',
			target_id INTEGER NOT NULL DEFAULT 0,
			title_snapshot VARCHAR(500) NOT NULL DEFAULT '',
			desc_snapshot TEXT NOT NULL DEFAULT '',
			order_sort INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			UNIQUE(topic_id, resource_type, target_id)
		)`,
		`CREATE TABLE IF NOT EXISTS md_topic_comments (
			comment_id INTEGER PRIMARY KEY AUTOINCREMENT,
			topic_id INTEGER NOT NULL DEFAULT 0,
			target_type VARCHAR(20) NOT NULL DEFAULT '',
			target_id INTEGER NOT NULL DEFAULT 0,
			member_id INTEGER NOT NULL DEFAULT 0,
			parent_comment_id INTEGER NOT NULL DEFAULT 0,
			content TEXT NOT NULL DEFAULT '',
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_friend_links (
			link_id INTEGER PRIMARY KEY AUTOINCREMENT,
			link_name VARCHAR(100) NOT NULL DEFAULT '',
			link_url VARCHAR(1000) NOT NULL DEFAULT '',
			sort_weight INTEGER NOT NULL DEFAULT 0,
			is_enabled INTEGER NOT NULL DEFAULT 1,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL,
			created_by INTEGER NOT NULL DEFAULT 0,
			updated_by INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS md_shares (
			share_id INTEGER PRIMARY KEY AUTOINCREMENT,
			share_type VARCHAR(10) NOT NULL DEFAULT '',
			share_identify VARCHAR(100) NOT NULL DEFAULT '' UNIQUE,
			target_id INTEGER NOT NULL DEFAULT 0,
			member_id INTEGER NOT NULL DEFAULT 0,
			share_time DATETIME NOT NULL,
			is_pinned INTEGER NOT NULL DEFAULT 0,
			edit_token VARCHAR(100) NOT NULL DEFAULT '',
			UNIQUE(share_type, target_id)
		)`,
		`CREATE TABLE IF NOT EXISTS md_api_tokens (
			token_id INTEGER PRIMARY KEY AUTOINCREMENT,
			member_id INTEGER NOT NULL DEFAULT 0,
			token VARCHAR(64) NOT NULL DEFAULT "" UNIQUE,
			name VARCHAR(50) NOT NULL DEFAULT "default",
			create_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_member_auth_versions (
			member_id INTEGER PRIMARY KEY,
			auth_version INTEGER NOT NULL DEFAULT 1,
			update_time DATETIME NOT NULL,
			FOREIGN KEY(member_id) REFERENCES md_members(member_id) ON DELETE CASCADE
		)`,
		`CREATE TABLE IF NOT EXISTS md_password_reset_tokens (
			reset_id INTEGER PRIMARY KEY AUTOINCREMENT,
			member_id INTEGER NOT NULL,
			token_hash VARCHAR(64) NOT NULL UNIQUE,
			expires_at DATETIME NOT NULL,
			used_at DATETIME,
			created_at DATETIME NOT NULL,
			created_ip VARCHAR(45) NOT NULL DEFAULT '',
			FOREIGN KEY(member_id) REFERENCES md_members(member_id) ON DELETE CASCADE
		)`,
		`CREATE TABLE IF NOT EXISTS md_settings (
			key VARCHAR(100) PRIMARY KEY,
			value VARCHAR(500) NOT NULL DEFAULT '',
			description VARCHAR(200) NOT NULL DEFAULT '',
			update_time DATETIME
		)`,
		`CREATE TABLE IF NOT EXISTS md_home_layouts (
			member_id INTEGER PRIMARY KEY,
			layout TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_assistant_sessions (
			member_id INTEGER PRIMARY KEY, session_id TEXT NOT NULL,
			messages TEXT NOT NULL DEFAULT '[]', lease TEXT NOT NULL DEFAULT '', busy_until INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS md_assistant_drafts (
			id TEXT PRIMARY KEY, member_id INTEGER NOT NULL, session_id TEXT NOT NULL,
			payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', result_url TEXT NOT NULL DEFAULT '',
			created_at INTEGER NOT NULL, finished_at INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE INDEX IF NOT EXISTS idx_assistant_drafts_owner ON md_assistant_drafts(member_id, session_id)`,
		`CREATE TABLE IF NOT EXISTS md_task_reminder_preferences (
			member_id INTEGER PRIMARY KEY,
			enabled INTEGER NOT NULL DEFAULT 0,
			send_time VARCHAR(5) NOT NULL DEFAULT '09:00',
			remind_before_days INTEGER NOT NULL DEFAULT 0,
			include_overdue INTEGER NOT NULL DEFAULT 0,
			last_processed_date VARCHAR(10) NOT NULL DEFAULT '',
			update_time DATETIME NOT NULL,
			FOREIGN KEY(member_id) REFERENCES md_members(member_id) ON DELETE CASCADE
		)`,
		`CREATE TABLE IF NOT EXISTS md_mail_outbox (
			mail_id INTEGER PRIMARY KEY AUTOINCREMENT,
			kind VARCHAR(50) NOT NULL DEFAULT '',
			member_id INTEGER NOT NULL DEFAULT 0,
			to_email VARCHAR(200) NOT NULL DEFAULT '',
			subject VARCHAR(500) NOT NULL DEFAULT '',
			text_body TEXT NOT NULL DEFAULT '',
			html_body TEXT NOT NULL DEFAULT '',
			dedupe_key VARCHAR(200) NOT NULL DEFAULT '' UNIQUE,
			status VARCHAR(20) NOT NULL DEFAULT 'pending',
			attempts INTEGER NOT NULL DEFAULT 0,
			next_attempt_at DATETIME NOT NULL,
			sent_at DATETIME,
			last_error VARCHAR(1000) NOT NULL DEFAULT '',
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_trash (
			trash_id INTEGER PRIMARY KEY AUTOINCREMENT,
			resource_type VARCHAR(24) NOT NULL,
			resource_name VARCHAR(500) NOT NULL DEFAULT '',
			snapshot TEXT NOT NULL,
			member_id INTEGER NOT NULL DEFAULT 0,
			delete_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_asset_credentials (
			credential_id INTEGER PRIMARY KEY AUTOINCREMENT,
			name VARCHAR(100) NOT NULL DEFAULT '',
			username VARCHAR(100) NOT NULL DEFAULT '',
			auth_type VARCHAR(20) NOT NULL DEFAULT 'password',
			credential_cipher TEXT NOT NULL DEFAULT '',
			credential_hint VARCHAR(100) NOT NULL DEFAULT '',
			created_by INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_asset_ssh_hosts (
			host_id INTEGER PRIMARY KEY AUTOINCREMENT,
			name VARCHAR(100) NOT NULL DEFAULT '',
			host VARCHAR(255) NOT NULL DEFAULT '',
			port INTEGER NOT NULL DEFAULT 22,
			shell VARCHAR(255) NOT NULL DEFAULT '/bin/sh',
			cwd VARCHAR(500) NOT NULL DEFAULT '',
			docker_socket_path VARCHAR(500) NOT NULL DEFAULT '/var/run/docker.sock',
			credential_id INTEGER NOT NULL DEFAULT 0,
			username VARCHAR(100) NOT NULL DEFAULT '',
			auth_type VARCHAR(20) NOT NULL DEFAULT 'password',
			credential_cipher TEXT NOT NULL DEFAULT '',
			credential_hint VARCHAR(100) NOT NULL DEFAULT '',
			status VARCHAR(20) NOT NULL DEFAULT 'unknown',
			last_check_time DATETIME,
			created_by INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS md_asset_webdav_servers (
			server_id INTEGER PRIMARY KEY AUTOINCREMENT,
			name VARCHAR(100) NOT NULL DEFAULT '',
			url VARCHAR(1000) NOT NULL DEFAULT '',
			root_path VARCHAR(500) NOT NULL DEFAULT '/',
			credential_id INTEGER NOT NULL DEFAULT 0,
			status VARCHAR(20) NOT NULL DEFAULT 'unknown',
			last_check_time DATETIME,
			created_by INTEGER NOT NULL DEFAULT 0,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL
		)`,
		// 索引
		`CREATE INDEX IF NOT EXISTS idx_books_member ON md_books(member_id)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_books_name_member ON md_books(book_name, member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_docs_book ON md_documents(book_id)`,
		`CREATE INDEX IF NOT EXISTS idx_docs_parent ON md_documents(parent_id)`,
		`CREATE INDEX IF NOT EXISTS idx_docs_type ON md_documents(doc_type)`,
		`CREATE INDEX IF NOT EXISTS idx_blogs_member ON md_blogs(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_blogs_type ON md_blogs(blog_type)`,
		`CREATE INDEX IF NOT EXISTS idx_blogs_visibility ON md_blogs(visibility)`,
		`CREATE INDEX IF NOT EXISTS idx_bookmark_member ON md_bookmark(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_tasks_member ON md_tasks(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_tasks_parent ON md_tasks(parent_id)`,
		`CREATE INDEX IF NOT EXISTS idx_tasks_topic ON md_tasks(topic_id)`,
		`CREATE INDEX IF NOT EXISTS idx_tasks_done ON md_tasks(done)`,
		`CREATE INDEX IF NOT EXISTS idx_tasks_due ON md_tasks(due_date)`,
		`CREATE INDEX IF NOT EXISTS idx_tasks_modify ON md_tasks(modify_time)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_bookmark_url_member ON md_bookmark(url, member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_api_tokens_member ON md_api_tokens(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_password_reset_member ON md_password_reset_tokens(member_id, created_at)`,
		`CREATE INDEX IF NOT EXISTS idx_password_reset_expiry ON md_password_reset_tokens(expires_at, used_at)`,
		`CREATE INDEX IF NOT EXISTS idx_task_reminder_enabled ON md_task_reminder_preferences(enabled, send_time)`,
		`CREATE INDEX IF NOT EXISTS idx_mail_outbox_ready ON md_mail_outbox(status, next_attempt_at)`,
		`CREATE INDEX IF NOT EXISTS idx_mail_outbox_member ON md_mail_outbox(member_id, create_time)`,
		`CREATE INDEX IF NOT EXISTS idx_shares_member ON md_shares(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_shares_identify ON md_shares(share_identify)`,
		`CREATE INDEX IF NOT EXISTS idx_topics_member ON md_topics(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_topics_modify ON md_topics(modify_time)`,
		`CREATE INDEX IF NOT EXISTS idx_topic_summaries_topic ON md_topic_summaries(topic_id, order_sort, summary_id)`,
		`CREATE INDEX IF NOT EXISTS idx_topic_resources_topic ON md_topic_resources(topic_id, order_sort, topic_resource_id)`,
		`CREATE INDEX IF NOT EXISTS idx_topic_resources_resource ON md_topic_resources(resource_type, target_id)`,
		`CREATE INDEX IF NOT EXISTS idx_topic_comments_target ON md_topic_comments(topic_id, target_type, target_id, create_time, comment_id)`,
		`CREATE INDEX IF NOT EXISTS idx_topic_comments_member ON md_topic_comments(member_id, modify_time)`,
		`CREATE INDEX IF NOT EXISTS idx_topic_comments_parent ON md_topic_comments(parent_comment_id, create_time, comment_id)`,
		`CREATE INDEX IF NOT EXISTS idx_label_relation_label ON md_label_relation(label_id)`,
		`CREATE INDEX IF NOT EXISTS idx_label_relation_resource ON md_label_relation(resource_id, relation_type)`,
		`CREATE INDEX IF NOT EXISTS idx_trash_member ON md_trash(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_trash_type ON md_trash(resource_type)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_label_relation_unique ON md_label_relation(label_id, resource_id, relation_type)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_credentials_created_by ON md_asset_credentials(created_by)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_credentials_auth ON md_asset_credentials(auth_type)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_ssh_hosts_credential ON md_asset_ssh_hosts(credential_id)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_ssh_hosts_created_by ON md_asset_ssh_hosts(created_by)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_ssh_hosts_status ON md_asset_ssh_hosts(status)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_webdav_servers_credential ON md_asset_webdav_servers(credential_id)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_webdav_servers_created_by ON md_asset_webdav_servers(created_by)`,
		`CREATE INDEX IF NOT EXISTS idx_asset_webdav_servers_status ON md_asset_webdav_servers(status)`,
		`CREATE TABLE IF NOT EXISTS md_visit_log (
			visit_id   INTEGER PRIMARY KEY AUTOINCREMENT,
			ip         VARCHAR(45)  NOT NULL DEFAULT '',
			path       VARCHAR(500) NOT NULL DEFAULT '',
			member_id  INTEGER      NOT NULL DEFAULT 0,
			visit_time DATETIME     NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_visit_log_time ON md_visit_log(visit_time)`,
		`CREATE INDEX IF NOT EXISTS idx_visit_log_path ON md_visit_log(path)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_visit_log_ip_member ON md_visit_log(ip, member_id)`,
		`CREATE TABLE IF NOT EXISTS md_visit_daily (
			date        TEXT    NOT NULL PRIMARY KEY,
			page_views  INTEGER NOT NULL DEFAULT 0,
			unique_ips  INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS md_visit_daily_ip (
			date TEXT NOT NULL,
			ip   TEXT NOT NULL,
			PRIMARY KEY (date, ip)
		)`,
		`CREATE TABLE IF NOT EXISTS md_uploads (
			upload_id    INTEGER PRIMARY KEY AUTOINCREMENT,
			file_name    VARCHAR(500) NOT NULL DEFAULT '',
			storage_path VARCHAR(500) NOT NULL DEFAULT '',
			file_hash    VARCHAR(64) NOT NULL DEFAULT '',
			file_size    INTEGER NOT NULL DEFAULT 0,
			mime_type    VARCHAR(100) NOT NULL DEFAULT '',
			width        INTEGER NOT NULL DEFAULT 0,
			height       INTEGER NOT NULL DEFAULT 0,
			thumb_path   VARCHAR(500) NOT NULL DEFAULT '',
			thumb_size   INTEGER NOT NULL DEFAULT 0,
			category     VARCHAR(50) NOT NULL DEFAULT 'editor',
			member_id    INTEGER NOT NULL DEFAULT 0,
			create_time  DATETIME NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_uploads_member ON md_uploads(member_id)`,
		`CREATE INDEX IF NOT EXISTS idx_uploads_category ON md_uploads(category)`,
		`CREATE INDEX IF NOT EXISTS idx_uploads_time ON md_uploads(create_time)`,
		`CREATE INDEX IF NOT EXISTS idx_uploads_hash ON md_uploads(file_hash)`,
	}

	for _, s := range statements {
		if _, err := DB.Exec(s); err != nil {
			return fmt.Errorf("exec %q: %w", s[:50], err)
		}
	}

	return nil
}

func ensureAdmin() error {
	// Ensure the configured admin account exists with correct role
	var role int
	err := DB.QueryRow("SELECT role FROM md_members WHERE account = ?", conf.App.AdminAccount).Scan(&role)
	if err == nil {
		// Account exists — fix role if wrong
		if role != 0 {
			log.Printf("Fixing role for admin account %q (was %d)", conf.App.AdminAccount, role)
			_, err = DB.Exec("UPDATE md_members SET role = 0 WHERE account = ?", conf.App.AdminAccount)
		}
		return err
	}

	// Account doesn't exist — create it
	log.Println("Creating default admin account...")
	m := Member{
		Account:    conf.App.AdminAccount,
		Password:   conf.App.AdminPassword,
		Email:      "admin@bookstark.com",
		Role:       0,
		Status:     1,
		CreateTime: time.Now(),
	}
	return m.Insert()
}
