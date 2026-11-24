package models

import (
	"bookstark/internal/toolpackage"
	"bytes"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"
	"sync"
	"time"
)

var ErrToolPermission = errors.New("tool permission denied")
var ErrToolConflict = errors.New("tool installation changed")
var ErrToolCleanupPending = errors.New("resource cleanup pending")
var toolLocks [64]sync.Mutex

func toolLock(member, id int64) *sync.Mutex {
	return &toolLocks[uint64(member+id)%uint64(len(toolLocks))]
}

type InstalledTool struct {
	ToolMetadata
	ID          int64               `json:"id"`
	Title       string              `json:"title"`
	Description string              `json:"description"`
	Author      string              `json:"author"`
	Source      string              `json:"source"`
	Revision    string              `json:"revision"`
	Instance    string              `json:"instance"`
	Pinned      bool                `json:"pinned"`
	Used        int64               `json:"used"`
	Installed   int64               `json:"installed"`
	Content     string              `json:"content,omitempty"`
	Values      map[string]string   `json:"values,omitempty"`
	AssetBase   string              `json:"asset_base,omitempty"`
	Assets      string              `json:"-"`
	Resources   []toolpackage.Asset `json:"-"`
}

func initToolTables() error {
	if err := initToolSourceTables(); err != nil {
		return err
	}
	for _, s := range []string{
		`CREATE TABLE IF NOT EXISTS md_tool_remote_sources(id INTEGER PRIMARY KEY AUTOINCREMENT,member_id INTEGER NOT NULL,origin TEXT NOT NULL,remote_id INTEGER NOT NULL,UNIQUE(member_id,origin,remote_id))`,
		`CREATE TABLE IF NOT EXISTS md_tool_installs(member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,tool_id INTEGER NOT NULL,title TEXT NOT NULL,description TEXT NOT NULL,author TEXT NOT NULL,source TEXT NOT NULL,revision TEXT NOT NULL,instance TEXT NOT NULL,content TEXT NOT NULL,values_json TEXT NOT NULL DEFAULT '{}',assets TEXT NOT NULL,pinned INTEGER NOT NULL DEFAULT 1,used INTEGER NOT NULL DEFAULT 0,installed INTEGER NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE IF NOT EXISTS md_tool_cleanup(member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,tool_id INTEGER NOT NULL,path TEXT NOT NULL,PRIMARY KEY(member_id,path))`,
	} {
		if _, err := DB.Exec(s); err != nil {
			return err
		}
	}
	return initToolMarketTables()
}

const installedToolColumns = "tool_id,title,description,author,source,revision,instance,pinned,used,installed,assets"

func scanInstalledTool(row rowScan) (*InstalledTool, error) {
	var t InstalledTool
	err := row.Scan(&t.ID, &t.Title, &t.Description, &t.Author, &t.Source, &t.Revision, &t.Instance, &t.Pinned, &t.Used, &t.Installed, &t.Assets)
	return &t, err
}
func ListInstalledTools(member int64) ([]InstalledTool, error) {
	rows, err := DB.Query("SELECT "+installedToolColumns+" FROM md_tool_installs WHERE member_id=? ORDER BY pinned DESC,used DESC,installed DESC", member)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []InstalledTool{}
	for rows.Next() {
		t, err := scanInstalledTool(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, *t)
	}
	err = rows.Err()
	rows.Close()
	for i := range result {
		result[i].ToolMetadata = ReadToolMetadata(member, result[i].ID)
	}
	return result, err
}
func GetInstalledTool(member, id int64) (*InstalledTool, error) {
	t, err := scanInstalledTool(DB.QueryRow("SELECT "+installedToolColumns+" FROM md_tool_installs WHERE member_id=? AND tool_id=?", member, id))
	if err == nil {
		t.ToolMetadata = ReadToolMetadata(member, id)
		t.AssetBase = "/api/tool-assets/" + t.Instance + "/" + path.Base(t.Assets) + "/"
	}
	return t, err
}
func GetInstalledToolContent(member, id int64) (string, error) {
	var raw string
	err := DB.QueryRow("SELECT content FROM md_tool_installs WHERE member_id=? AND tool_id=?", member, id).Scan(&raw)
	return raw, err
}
func GetInstalledToolValues(member, id int64) (map[string]string, error) {
	var raw string
	err := DB.QueryRow("SELECT values_json FROM md_tool_installs WHERE member_id=? AND tool_id=?", member, id).Scan(&raw)
	if err != nil {
		return nil, err
	}
	values := map[string]string{}
	err = json.Unmarshal([]byte(raw), &values)
	return values, err
}
func toolNonce() (string, error) {
	var b [16]byte
	_, err := rand.Read(b[:])
	return hex.EncodeToString(b[:]), err
}
func toolRoot(instance string) string { return "/BookStark/tools/" + instance }

func SaveInstalledTool(member int64, t InstalledTool, expected, instance string) error {
	lock := toolLock(member, t.ID)
	lock.Lock()
	defer lock.Unlock()

	old, err := GetInstalledTool(member, t.ID)
	if err != nil && err != sql.ErrNoRows {
		return err
	}
	if err == sql.ErrNoRows {
		if expected != "" || instance != "" {
			return ErrToolConflict
		}
		t.Instance, err = toolNonce()
		if err != nil {
			return err
		}
	} else {
		if old.Revision != expected || old.Instance != instance {
			return ErrToolConflict
		}
		if old.Revision == t.Revision {
			return ToolCleanupError(cleanupToolResources(member, t.ID))
		}
		t.Instance = old.Instance
	}
	t.DataRoot = ""
	retainedValues := "{}"
	if old != nil && old.Instance != "" {
		t.DataRoot = old.DataRoot
	} else {
		_ = DB.QueryRow("SELECT root,values_json FROM md_tool_retained WHERE member_id=? AND tool_id=?", member, t.ID).Scan(&t.DataRoot, &retainedValues)
	}
	epoch, err := toolNonce()
	if err != nil {
		return err
	}
	t.Assets = toolRoot(t.Instance) + "/assets/" + epoch
	// Journal staging before writing files, so failed or interrupted installs are collectible.
	if _, err = DB.Exec("INSERT INTO md_tool_cleanup(member_id,tool_id,path) VALUES(?,?,?)", member, t.ID, t.Assets); err != nil {
		return err
	}
	committed := false
	defer func() {
		if !committed {
			_ = cleanupToolResources(member, t.ID)
		}
	}()
	prefix := "/api/tool-assets/" + t.Instance + "/" + epoch + "/"
	names := map[string]bool{}
	for _, resource := range t.Resources {
		names[resource.Name] = true
	}
	for _, asset := range t.Resources {
		data := asset.Data
		if strings.Contains(asset.MIME, "text/") || strings.Contains(asset.MIME, "javascript") || strings.HasSuffix(asset.Name, ".js") || strings.HasSuffix(asset.Name, ".css") || strings.HasSuffix(asset.Name, ".mjs") {
			text := string(data)
			if t.Distribution == "files" {
				text = toolpackage.RewriteArchiveRoots(text, names)
			}
			data = []byte(strings.ReplaceAll(text, toolpackage.Prefix, prefix))
		}
		if err = putToolResourceAt(member, t.Assets+"/"+asset.Name, asset.MIME, bytes.NewReader(data)); err != nil {
			return err
		}
	}
	if t.Distribution == "files" {
		t.Content, err = toolpackage.StripArchiveIntegrity(t.Content, t.Entry, names)
		if err != nil {
			return err
		}
		t.Content = toolpackage.RewriteArchiveRoots(t.Content, names)
	}
	encoded, err := EncodeHTMLContent(strings.ReplaceAll(t.Content, toolpackage.Prefix, prefix))
	if err != nil {
		return err
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if old == nil || old.Instance == "" {
		_, err = tx.Exec(`INSERT INTO md_tool_installs(member_id,tool_id,title,description,author,source,revision,instance,content,assets,installed,values_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`, member, t.ID, t.Title, t.Description, t.Author, t.Source, t.Revision, t.Instance, encoded, t.Assets, time.Now().UnixMilli(), retainedValues)
	} else {
		if _, err = tx.Exec(`INSERT OR IGNORE INTO md_tool_cleanup(member_id,tool_id,path) VALUES(?,?,?)`, member, t.ID, old.Assets); err != nil {
			return err
		}
		_, err = tx.Exec(`UPDATE md_tool_installs SET title=?,description=?,author=?,source=?,revision=?,content=?,assets=? WHERE member_id=? AND tool_id=?`, t.Title, t.Description, t.Author, t.Source, t.Revision, encoded, t.Assets, member, t.ID)
	}
	if err != nil {
		return err
	}
	if _, err = tx.Exec("DELETE FROM md_tool_retained WHERE member_id=? AND tool_id=?", member, t.ID); err != nil {
		return err
	}
	if err = SaveToolMetadata(tx, member, t.ID, t.ToolMetadata); err != nil {
		return err
	}
	if _, err = tx.Exec("DELETE FROM md_tool_cleanup WHERE member_id=? AND path=?", member, t.Assets); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return err
	}
	committed = true
	return ToolCleanupError(cleanupToolResources(member, t.ID))
}

func DeleteInstalledTool(member, id int64, revision, instance string, keep ...bool) error {
	lock := toolLock(member, id)
	lock.Lock()
	defer lock.Unlock()
	metadata := ReadToolMetadata(member, id)
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	old, err := scanInstalledTool(tx.QueryRow("SELECT "+installedToolColumns+" FROM md_tool_installs WHERE member_id=? AND tool_id=?", member, id))
	if err == sql.ErrNoRows {
		return ToolCleanupError(cleanupToolResources(member, id))
	}
	if err != nil {
		return err
	}
	if old.Revision != revision || old.Instance != instance {
		return ErrToolConflict
	}
	root := toolRoot(instance)
	dataRoot := metadata.DataRoot
	if dataRoot == "" {
		dataRoot = root + "/data"
	}
	if len(keep) > 0 && keep[0] {
		var values string
		if err = tx.QueryRow("SELECT values_json FROM md_tool_installs WHERE member_id=? AND tool_id=?", member, id).Scan(&values); err != nil {
			return err
		}
		if _, err = tx.Exec(`INSERT INTO md_tool_retained(member_id,tool_id,root,values_json) VALUES(?,?,?,?) ON CONFLICT(member_id,tool_id) DO UPDATE SET root=excluded.root,values_json=excluded.values_json`, member, id, dataRoot, values); err != nil {
			return err
		}
		root = old.Assets
	} else if metadata.DataRoot != "" {
		if _, err = tx.Exec(`INSERT OR IGNORE INTO md_tool_cleanup(member_id,tool_id,path) VALUES(?,?,?)`, member, id, metadata.DataRoot); err != nil {
			return err
		}
	}
	if _, err = tx.Exec(`INSERT OR IGNORE INTO md_tool_cleanup(member_id,tool_id,path) VALUES(?,?,?)`, member, id, root); err != nil {
		return err
	}
	if _, err = tx.Exec("DELETE FROM md_tool_install_metadata WHERE member_id=? AND tool_id=?", member, id); err != nil {
		return err
	}

	if _, err = tx.Exec(`DELETE FROM md_tool_installs WHERE member_id=? AND tool_id=?`, member, id); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return err
	}
	return ToolCleanupError(cleanupToolResources(member, id))
}

// Durable cleanup entries bridge the two SQLite stores without keeping version backups.
func cleanupToolResources(member, id int64) error {
	rows, err := DB.Query("SELECT path FROM md_tool_cleanup WHERE member_id=? AND tool_id=?", member, id)
	if err != nil {
		return err
	}
	var paths []string
	for rows.Next() {
		var p string
		if err = rows.Scan(&p); err != nil {
			rows.Close()
			return err
		}
		paths = append(paths, p)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, p := range paths {
		if WebDAVDB == nil {
			return errors.New("tool resource storage unavailable")
		}
		if err = DeleteDAVNode(member, p, true); err != nil && !errors.Is(err, ErrDAVNotFound) {
			return err
		}
		if _, err = DB.Exec("DELETE FROM md_tool_cleanup WHERE member_id=? AND path=?", member, p); err != nil {
			return err
		}
	}
	return nil
}
func CleanupToolResources(member int64) error {
	rows, err := DB.Query("SELECT DISTINCT tool_id FROM md_tool_cleanup WHERE member_id=?", member)
	if err != nil {
		return err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, id := range ids {
		lock := toolLock(member, id)
		lock.Lock()
		err = cleanupToolResources(member, id)
		lock.Unlock()
		if err != nil {
			return err
		}
	}
	return nil
}
func PatchInstalledTool(member, id int64, pinned *bool, used *int64) error {
	if pinned == nil && used == nil {
		return nil
	}
	var result sql.Result
	var err error
	if pinned != nil {
		result, err = DB.Exec("UPDATE md_tool_installs SET pinned=? WHERE member_id=? AND tool_id=?", *pinned, member, id)
	} else {
		result, err = DB.Exec("UPDATE md_tool_installs SET used=? WHERE member_id=? AND tool_id=?", time.Now().UnixMilli(), member, id)
	}
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err == nil && n == 0 {
		return sql.ErrNoRows
	}
	return err
}
func WriteInstalledToolValue(member, id int64, revision, instance, op, key, value string) error {
	lock := toolLock(member, id)
	lock.Lock()
	defer lock.Unlock()
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var raw string
	if err = tx.QueryRow("SELECT values_json FROM md_tool_installs WHERE member_id=? AND tool_id=? AND revision=? AND instance=?", member, id, revision, instance).Scan(&raw); err == sql.ErrNoRows {
		return ErrToolConflict
	} else if err != nil {
		return err
	}
	values := map[string]string{}
	if err = json.Unmarshal([]byte(raw), &values); err != nil {
		return err
	}
	switch op {
	case "set":
		values[key] = value
	case "remove":
		delete(values, key)
	case "clear":
		values = map[string]string{}
	default:
		return errors.New("invalid storage operation")
	}
	data, err := json.Marshal(values)
	if err != nil {
		return err
	}
	if len(data) > 5<<20 {
		return errors.New("tool data quota exceeded")
	}
	if _, err = tx.Exec("UPDATE md_tool_installs SET values_json=? WHERE member_id=? AND tool_id=?", string(data), member, id); err != nil {
		return err
	}
	return tx.Commit()
}
func ToolResourcePath(t *InstalledTool, area, name string) (string, error) {
	if area != "assets" && area != "data" {
		return "", ErrDAVInvalidPath
	}
	name = strings.TrimPrefix(name, "/")
	for _, part := range strings.Split(name, "/") {
		if part == ".." || part == "." || part == "" {
			return "", ErrDAVInvalidPath
		}
	}
	normalized, err := NormalizeDAVPath(name)
	if err != nil || normalized == "" {
		return "", ErrDAVInvalidPath
	}
	root := t.Assets
	if area == "data" {
		root = toolRoot(t.Instance) + "/data"
		if t.DataRoot != "" {
			root = t.DataRoot
		}
	}
	return root + "/" + strings.TrimPrefix(normalized, "/"), nil
}
func PutToolResource(member, id int64, revision, instance, area, name, mime string, reader io.Reader) error {
	lock := toolLock(member, id)
	lock.Lock()
	defer lock.Unlock()
	t, err := GetInstalledTool(member, id)
	if err != nil {
		return err
	}
	if t.Revision != revision || t.Instance != instance {
		return ErrToolConflict
	}
	if area == "data" && !t.Permissions.SaveFiles {
		return ErrToolPermission
	}
	p, err := ToolResourcePath(t, area, name)
	if err != nil {
		return err
	}
	return putToolResourceAt(member, p, mime, reader)
}
func putToolResourceAt(member int64, p, mime string, reader io.Reader) error {
	var err error
	if WebDAVDB == nil {
		return errors.New("tool resource storage unavailable")
	}
	if _, err = EnsureDAVRoot(member); err != nil {
		return err
	}
	parts := strings.Split(strings.Trim(path.Dir(p), "/"), "/")
	prefix := ""
	for _, part := range parts {
		prefix += "/" + part
		if _, err = CreateDAVDirectory(member, prefix); err != nil && !errors.Is(err, ErrDAVAlreadyExists) {
			return err
		}
	}
	settings := GetWebDAVSettings()
	_, _, err = PutDAVFile(member, p, mime, reader, settings.FileMaxBytes, settings.UserQuotaBytes)
	return err
}
func ToolCleanupError(err error) error {
	if err != nil {
		return fmt.Errorf("%w: %v", ErrToolCleanupPending, err)
	}
	return nil
}

func GetInstalledToolRuntime(member, id int64) (*InstalledTool, error) {
	var t InstalledTool
	var values string
	err := DB.QueryRow("SELECT "+installedToolColumns+",content,values_json FROM md_tool_installs WHERE member_id=? AND tool_id=?", member, id).Scan(&t.ID, &t.Title, &t.Description, &t.Author, &t.Source, &t.Revision, &t.Instance, &t.Pinned, &t.Used, &t.Installed, &t.Assets, &t.Content, &values)
	if err != nil {
		return nil, err
	}
	t.ToolMetadata = ReadToolMetadata(member, id)
	t.AssetBase = "/api/tool-assets/" + t.Instance + "/" + path.Base(t.Assets) + "/"
	err = json.Unmarshal([]byte(values), &t.Values)
	return &t, err
}
