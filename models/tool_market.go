package models

import (
	"database/sql"
	"encoding/json"
	"errors"
)

var ErrBlogUsedByTool = errors.New("blog_in_tool_market")

func toolSourceInUse(tx *sql.Tx, id int64) (bool, error) {
	var used bool
	err := tx.QueryRow(`SELECT EXISTS(SELECT 1 FROM md_tool_releases WHERE blog_id=?) OR EXISTS(SELECT 1 FROM md_tool_versions WHERE blog_id=? AND status='pending')`, id, id).Scan(&used)
	return used, err
}

type ToolPermissions struct {
	ReadFiles bool `json:"read_files"`
	SaveFiles bool `json:"save_files"`
	Network   bool `json:"network"`
}
type ToolMetadata struct {
	Distribution string          `json:"distribution,omitempty"`
	Title        string          `json:"title,omitempty"`
	Description  string          `json:"description,omitempty"`
	Version      string          `json:"version"`
	Category     string          `json:"category"`
	Size         int64           `json:"size"`
	AssetCount   int             `json:"asset_count"`
	Offline      bool            `json:"offline"`
	Access       string          `json:"access"`
	Members      []int64         `json:"members,omitempty"`
	Permissions  ToolPermissions `json:"permissions"`
	Notes        string          `json:"notes"`
	Status       string          `json:"status"`
	Hash         string          `json:"hash"`
	DataRoot     string          `json:"data_root,omitempty"`
}

func initToolMarketTables() error {
	for _, q := range []string{
		`CREATE TABLE IF NOT EXISTS md_tool_versions(blog_id INTEGER NOT NULL REFERENCES md_blogs(blog_id) ON DELETE CASCADE,version TEXT NOT NULL,revision TEXT NOT NULL UNIQUE,metadata TEXT NOT NULL,content TEXT NOT NULL,resource_base TEXT NOT NULL,status TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(blog_id,version))`,
		`CREATE TABLE IF NOT EXISTS md_tool_retained(member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,tool_id INTEGER NOT NULL,root TEXT NOT NULL,values_json TEXT NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE IF NOT EXISTS md_tool_install_metadata(member_id INTEGER NOT NULL,tool_id INTEGER NOT NULL,metadata TEXT NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE IF NOT EXISTS md_tool_market_clients(member_id INTEGER PRIMARY KEY REFERENCES md_members(member_id) ON DELETE CASCADE,url TEXT NOT NULL DEFAULT '',check_updates INTEGER NOT NULL DEFAULT 1,auto_update INTEGER NOT NULL DEFAULT 0)`,
		`CREATE TABLE IF NOT EXISTS md_tool_market_credentials(member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,url TEXT NOT NULL,account TEXT NOT NULL,token TEXT NOT NULL,PRIMARY KEY(member_id,url))`,
		`CREATE TABLE IF NOT EXISTS md_tool_market_sessions(token_hash TEXT PRIMARY KEY,member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,expires INTEGER NOT NULL,auth_version INTEGER NOT NULL DEFAULT 0)`,
	} {
		if _, err := DB.Exec(q); err != nil {
			return err
		}
	}
	_, err := DB.Exec(`CREATE TRIGGER IF NOT EXISTS md_tool_source_delete_guard
	BEFORE DELETE ON md_blogs
	WHEN EXISTS(SELECT 1 FROM md_tool_releases WHERE blog_id=OLD.blog_id)
	  OR EXISTS(SELECT 1 FROM md_tool_versions WHERE blog_id=OLD.blog_id AND status='pending')
	BEGIN SELECT RAISE(ABORT, 'blog_in_tool_market'); END`)
	return err
}
func ReadToolMetadata(member, id int64) ToolMetadata {
	var raw string
	var m ToolMetadata
	if DB.QueryRow("SELECT metadata FROM md_tool_install_metadata WHERE member_id=? AND tool_id=?", member, id).Scan(&raw) == nil {
		json.Unmarshal([]byte(raw), &m)
	}
	return m
}
func SaveToolMetadata(tx *sql.Tx, member, id int64, m ToolMetadata) error {
	raw, err := json.Marshal(m)
	if err != nil {
		return err
	}
	_, err = tx.Exec(`INSERT INTO md_tool_install_metadata(member_id,tool_id,metadata) VALUES(?,?,?) ON CONFLICT(member_id,tool_id) DO UPDATE SET metadata=excluded.metadata`, member, id, string(raw))
	return err
}
