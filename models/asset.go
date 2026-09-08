package models

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

const (
	AssetAuthPassword = "password"
	AssetAuthKey      = "key"

	AssetStatusUnknown = "unknown"
	AssetStatusOnline  = "online"
	AssetStatusOffline = "offline"
)

type AssetSSHHost struct {
	HostID           int64      `json:"id"`
	Name             string     `json:"name"`
	Host             string     `json:"host"`
	Port             int        `json:"port"`
	Shell            string     `json:"shell"`
	Cwd              string     `json:"cwd"`
	DockerSocketPath string     `json:"docker_socket_path"`
	CredentialID     int64      `json:"credential_id"`
	CredentialName   string     `json:"credential_name,omitempty"`
	Username         string     `json:"username"`
	AuthType         string     `json:"auth_type"`
	CredentialCipher string     `json:"-"`
	Credential       string     `json:"credential,omitempty"`
	CredentialHint   string     `json:"credential_hint"`
	Status           string     `json:"status"`
	LastCheckTime    *time.Time `json:"last_check_time,omitempty"`
	CreatedBy        int64      `json:"created_by"`
	CreateTime       time.Time  `json:"create_time"`
	ModifyTime       time.Time  `json:"modify_time"`
}

type AssetCredential struct {
	CredentialID     int64     `json:"id"`
	Name             string    `json:"name"`
	Username         string    `json:"username"`
	AuthType         string    `json:"auth_type"`
	CredentialCipher string    `json:"-"`
	Credential       string    `json:"credential,omitempty"`
	CredentialHint   string    `json:"credential_hint"`
	CreatedBy        int64     `json:"created_by"`
	CreateTime       time.Time `json:"create_time"`
	ModifyTime       time.Time `json:"modify_time"`
}

type AssetWebDAVServer struct {
	ServerID       int64      `json:"id"`
	Name           string     `json:"name"`
	URL            string     `json:"url"`
	RootPath       string     `json:"root_path"`
	CredentialID   int64      `json:"credential_id"`
	CredentialName string     `json:"credential_name,omitempty"`
	Username       string     `json:"username,omitempty"`
	Status         string     `json:"status"`
	LastCheckTime  *time.Time `json:"last_check_time,omitempty"`
	CreatedBy      int64      `json:"created_by"`
	CreateTime     time.Time  `json:"create_time"`
	ModifyTime     time.Time  `json:"modify_time"`
}

type AssetSSHHostFilter struct {
	Query  string
	Status string
}

type AssetWebDAVServerFilter struct {
	Query  string
	Status string
}

type AssetSettings struct {
	TerminalIdleTimeoutSeconds int    `json:"terminal_idle_timeout_seconds"`
	TerminalScrollbackLines    int    `json:"terminal_scrollback_lines"`
	CredentialSecret           string `json:"credential_secret"`
}

func CreateAssetSSHHost(h *AssetSSHHost) (int64, error) {
	now := time.Now()
	h.CreateTime = now
	h.ModifyTime = now
	if h.Port == 0 {
		h.Port = 22
	}
	if strings.TrimSpace(h.Shell) == "" {
		h.Shell = "/bin/sh"
	}
	if strings.TrimSpace(h.DockerSocketPath) == "" {
		h.DockerSocketPath = "/var/run/docker.sock"
	}
	if h.AuthType == "" {
		h.AuthType = AssetAuthPassword
	}
	if h.Status == "" {
		h.Status = AssetStatusUnknown
	}
	result, err := DB.Exec(`
		INSERT INTO md_asset_ssh_hosts
		(name, host, port, shell, cwd, docker_socket_path, credential_id, username, auth_type, credential_cipher, credential_hint, status, last_check_time, created_by, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		h.Name, h.Host, h.Port, h.Shell, h.Cwd, h.DockerSocketPath, h.CredentialID, h.Username, h.AuthType, h.CredentialCipher, h.CredentialHint, h.Status,
		h.LastCheckTime, h.CreatedBy, h.CreateTime, h.ModifyTime,
	)
	if err != nil {
		return 0, fmt.Errorf("create asset ssh host: %w", err)
	}
	return result.LastInsertId()
}

func GetAssetSSHHost(id int64) (*AssetSSHHost, error) {
	row := DB.QueryRow(`
		SELECT h.host_id, h.name, h.host, h.port, h.shell, h.cwd, h.docker_socket_path, h.credential_id,
		       COALESCE(c.name, ''), COALESCE(c.username, h.username), COALESCE(c.auth_type, h.auth_type),
		       COALESCE(c.credential_cipher, h.credential_cipher), COALESCE(c.credential_hint, h.credential_hint),
		       h.status, h.last_check_time, h.created_by, h.create_time, h.modify_time
		FROM md_asset_ssh_hosts h
		LEFT JOIN md_asset_credentials c ON c.credential_id = h.credential_id
		WHERE h.host_id = ?`, id)
	return scanAssetSSHHost(row)
}

func ListAssetSSHHosts(filter AssetSSHHostFilter) ([]AssetSSHHost, error) {
	where, args := []string{}, []any{}
	if filter.Query != "" {
		where = append(where, "(h.name LIKE ? OR h.host LIKE ? OR COALESCE(c.username, h.username) LIKE ? OR c.name LIKE ?)")
		q := "%" + filter.Query + "%"
		args = append(args, q, q, q, q)
	}
	if filter.Status != "" {
		where = append(where, "h.status = ?")
		args = append(args, filter.Status)
	}
	sqlText := `
		SELECT h.host_id, h.name, h.host, h.port, h.shell, h.cwd, h.docker_socket_path, h.credential_id,
		       COALESCE(c.name, ''), COALESCE(c.username, h.username), COALESCE(c.auth_type, h.auth_type),
		       COALESCE(c.credential_cipher, h.credential_cipher), COALESCE(c.credential_hint, h.credential_hint),
		       h.status, h.last_check_time, h.created_by, h.create_time, h.modify_time
		FROM md_asset_ssh_hosts h
		LEFT JOIN md_asset_credentials c ON c.credential_id = h.credential_id`
	if len(where) > 0 {
		sqlText += " WHERE " + strings.Join(where, " AND ")
	}
	sqlText += " ORDER BY h.host_id DESC"
	rows, err := DB.Query(sqlText, args...)
	if err != nil {
		return nil, fmt.Errorf("list asset ssh hosts: %w", err)
	}
	defer rows.Close()

	result := []AssetSSHHost{}
	for rows.Next() {
		h, err := scanAssetSSHHost(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, *h)
	}
	return result, rows.Err()
}

func UpdateAssetSSHHost(h *AssetSSHHost, replaceCredential bool) error {
	h.ModifyTime = time.Now()
	if strings.TrimSpace(h.DockerSocketPath) == "" {
		h.DockerSocketPath = "/var/run/docker.sock"
	}
	var err error
	if replaceCredential {
		_, err = DB.Exec(`
			UPDATE md_asset_ssh_hosts
			SET name=?, host=?, port=?, shell=?, cwd=?, docker_socket_path=?, credential_id=?, username=?, auth_type=?, credential_cipher=?, credential_hint=?, status=?, last_check_time=?, modify_time=?
			WHERE host_id=?`,
			h.Name, h.Host, h.Port, h.Shell, h.Cwd, h.DockerSocketPath, h.CredentialID, h.Username, h.AuthType, h.CredentialCipher, h.CredentialHint, h.Status, h.LastCheckTime, h.ModifyTime, h.HostID,
		)
	} else {
		_, err = DB.Exec(`
			UPDATE md_asset_ssh_hosts
			SET name=?, host=?, port=?, shell=?, cwd=?, docker_socket_path=?, credential_id=?, username=?, auth_type=?, status=?, last_check_time=?, modify_time=?
			WHERE host_id=?`,
			h.Name, h.Host, h.Port, h.Shell, h.Cwd, h.DockerSocketPath, h.CredentialID, h.Username, h.AuthType, h.Status, h.LastCheckTime, h.ModifyTime, h.HostID,
		)
	}
	if err != nil {
		return fmt.Errorf("update asset ssh host: %w", err)
	}
	return nil
}

func UpdateAssetSSHHostStatus(id int64, status string, checkedAt time.Time) error {
	_, err := DB.Exec(`UPDATE md_asset_ssh_hosts SET status=?, last_check_time=?, modify_time=? WHERE host_id=?`, status, checkedAt, time.Now(), id)
	return err
}

func DeleteAssetSSHHost(id int64) error {
	_, err := DB.Exec("DELETE FROM md_asset_ssh_hosts WHERE host_id = ?", id)
	return err
}

func CreateAssetWebDAVServer(s *AssetWebDAVServer) (int64, error) {
	now := time.Now()
	s.CreateTime = now
	s.ModifyTime = now
	if strings.TrimSpace(s.RootPath) == "" {
		s.RootPath = "/"
	}
	if s.Status == "" {
		s.Status = AssetStatusUnknown
	}
	result, err := DB.Exec(`
		INSERT INTO md_asset_webdav_servers
		(name, url, root_path, credential_id, status, last_check_time, created_by, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		s.Name, s.URL, s.RootPath, s.CredentialID, s.Status, s.LastCheckTime, s.CreatedBy, s.CreateTime, s.ModifyTime,
	)
	if err != nil {
		return 0, fmt.Errorf("create asset webdav server: %w", err)
	}
	return result.LastInsertId()
}

func GetAssetWebDAVServer(id int64) (*AssetWebDAVServer, error) {
	row := DB.QueryRow(`
		SELECT s.server_id, s.name, s.url, s.root_path, s.credential_id,
		       COALESCE(c.name, ''), COALESCE(c.username, ''),
		       s.status, s.last_check_time, s.created_by, s.create_time, s.modify_time
		FROM md_asset_webdav_servers s
		LEFT JOIN md_asset_credentials c ON c.credential_id = s.credential_id
		WHERE s.server_id = ?`, id)
	return scanAssetWebDAVServer(row)
}

func ListAssetWebDAVServers(filter AssetWebDAVServerFilter) ([]AssetWebDAVServer, error) {
	where, args := []string{}, []any{}
	if filter.Query != "" {
		where = append(where, "(s.name LIKE ? OR s.url LIKE ? OR s.root_path LIKE ? OR c.name LIKE ? OR c.username LIKE ?)")
		q := "%" + filter.Query + "%"
		args = append(args, q, q, q, q, q)
	}
	if filter.Status != "" {
		where = append(where, "s.status = ?")
		args = append(args, filter.Status)
	}
	sqlText := `
		SELECT s.server_id, s.name, s.url, s.root_path, s.credential_id,
		       COALESCE(c.name, ''), COALESCE(c.username, ''),
		       s.status, s.last_check_time, s.created_by, s.create_time, s.modify_time
		FROM md_asset_webdav_servers s
		LEFT JOIN md_asset_credentials c ON c.credential_id = s.credential_id`
	if len(where) > 0 {
		sqlText += " WHERE " + strings.Join(where, " AND ")
	}
	sqlText += " ORDER BY s.server_id DESC"
	rows, err := DB.Query(sqlText, args...)
	if err != nil {
		return nil, fmt.Errorf("list asset webdav servers: %w", err)
	}
	defer rows.Close()

	result := []AssetWebDAVServer{}
	for rows.Next() {
		s, err := scanAssetWebDAVServer(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, *s)
	}
	return result, rows.Err()
}

func UpdateAssetWebDAVServer(s *AssetWebDAVServer) error {
	s.ModifyTime = time.Now()
	if strings.TrimSpace(s.RootPath) == "" {
		s.RootPath = "/"
	}
	_, err := DB.Exec(`
		UPDATE md_asset_webdav_servers
		SET name=?, url=?, root_path=?, credential_id=?, status=?, last_check_time=?, modify_time=?
		WHERE server_id=?`,
		s.Name, s.URL, s.RootPath, s.CredentialID, s.Status, s.LastCheckTime, s.ModifyTime, s.ServerID,
	)
	if err != nil {
		return fmt.Errorf("update asset webdav server: %w", err)
	}
	return nil
}

func UpdateAssetWebDAVServerStatus(id int64, status string, checkedAt time.Time) error {
	_, err := DB.Exec(`UPDATE md_asset_webdav_servers SET status=?, last_check_time=?, modify_time=? WHERE server_id=?`, status, checkedAt, time.Now(), id)
	return err
}

func DeleteAssetWebDAVServer(id int64) error {
	_, err := DB.Exec("DELETE FROM md_asset_webdav_servers WHERE server_id = ?", id)
	return err
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanAssetSSHHost(row rowScanner) (*AssetSSHHost, error) {
	var h AssetSSHHost
	var last sql.NullTime
	if err := row.Scan(&h.HostID, &h.Name, &h.Host, &h.Port, &h.Shell, &h.Cwd, &h.DockerSocketPath, &h.CredentialID, &h.CredentialName, &h.Username, &h.AuthType, &h.CredentialCipher, &h.CredentialHint, &h.Status, &last, &h.CreatedBy, &h.CreateTime, &h.ModifyTime); err != nil {
		return nil, err
	}
	if strings.TrimSpace(h.DockerSocketPath) == "" {
		h.DockerSocketPath = "/var/run/docker.sock"
	}
	if last.Valid {
		h.LastCheckTime = &last.Time
	}
	return &h, nil
}

func scanAssetWebDAVServer(row rowScanner) (*AssetWebDAVServer, error) {
	var s AssetWebDAVServer
	var last sql.NullTime
	if err := row.Scan(&s.ServerID, &s.Name, &s.URL, &s.RootPath, &s.CredentialID, &s.CredentialName, &s.Username, &s.Status, &last, &s.CreatedBy, &s.CreateTime, &s.ModifyTime); err != nil {
		return nil, err
	}
	if strings.TrimSpace(s.RootPath) == "" {
		s.RootPath = "/"
	}
	if last.Valid {
		s.LastCheckTime = &last.Time
	}
	return &s, nil
}

func CreateAssetCredential(c *AssetCredential) (int64, error) {
	now := time.Now()
	c.CreateTime = now
	c.ModifyTime = now
	if c.AuthType == "" {
		c.AuthType = AssetAuthPassword
	}
	result, err := DB.Exec(`
		INSERT INTO md_asset_credentials
		(name, username, auth_type, credential_cipher, credential_hint, created_by, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		c.Name, c.Username, c.AuthType, c.CredentialCipher, c.CredentialHint, c.CreatedBy, c.CreateTime, c.ModifyTime,
	)
	if err != nil {
		return 0, fmt.Errorf("create asset credential: %w", err)
	}
	return result.LastInsertId()
}

func GetAssetCredential(id int64) (*AssetCredential, error) {
	row := DB.QueryRow(`
		SELECT credential_id, name, username, auth_type, credential_cipher, credential_hint, created_by, create_time, modify_time
		FROM md_asset_credentials WHERE credential_id = ?`, id)
	return scanAssetCredential(row)
}

func ListAssetCredentials() ([]AssetCredential, error) {
	rows, err := DB.Query(`
		SELECT credential_id, name, username, auth_type, credential_cipher, credential_hint, created_by, create_time, modify_time
		FROM md_asset_credentials ORDER BY credential_id DESC`)
	if err != nil {
		return nil, fmt.Errorf("list asset credentials: %w", err)
	}
	defer rows.Close()
	result := []AssetCredential{}
	for rows.Next() {
		c, err := scanAssetCredential(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, *c)
	}
	return result, rows.Err()
}

func UpdateAssetCredential(c *AssetCredential) error {
	c.ModifyTime = time.Now()
	_, err := DB.Exec(`
		UPDATE md_asset_credentials
		SET name=?, username=?, auth_type=?, credential_cipher=?, credential_hint=?, modify_time=?
		WHERE credential_id=?`,
		c.Name, c.Username, c.AuthType, c.CredentialCipher, c.CredentialHint, c.ModifyTime, c.CredentialID,
	)
	if err != nil {
		return fmt.Errorf("update asset credential: %w", err)
	}
	return nil
}

func DeleteAssetCredential(id int64) error {
	var used int
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_asset_ssh_hosts WHERE credential_id = ?", id).Scan(&used); err != nil {
		return err
	}
	if used > 0 {
		return fmt.Errorf("credential is used by %d SSH hosts", used)
	}
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_asset_webdav_servers WHERE credential_id = ?", id).Scan(&used); err != nil {
		return err
	}
	if used > 0 {
		return fmt.Errorf("credential is used by %d WebDAV servers", used)
	}
	_, err := DB.Exec("DELETE FROM md_asset_credentials WHERE credential_id = ?", id)
	return err
}

func scanAssetCredential(row rowScanner) (*AssetCredential, error) {
	var c AssetCredential
	if err := row.Scan(&c.CredentialID, &c.Name, &c.Username, &c.AuthType, &c.CredentialCipher, &c.CredentialHint, &c.CreatedBy, &c.CreateTime, &c.ModifyTime); err != nil {
		return nil, err
	}
	return &c, nil
}

func GetAssetSettings() AssetSettings {
	return AssetSettings{
		TerminalIdleTimeoutSeconds: assetTerminalIdleTimeoutSeconds(),
		TerminalScrollbackLines:    parseIntSetting("asset_terminal_scrollback_lines", 5000, 500, 50000),
		CredentialSecret:           GetSetting("asset_credential_secret"),
	}
}

func UpdateAssetSettings(s AssetSettings) error {
	if s.TerminalIdleTimeoutSeconds < 1 || s.TerminalIdleTimeoutSeconds > 86400 {
		return fmt.Errorf("terminal idle timeout out of range")
	}
	if s.TerminalScrollbackLines == 0 {
		s.TerminalScrollbackLines = 5000
	}
	if s.TerminalScrollbackLines < 500 || s.TerminalScrollbackLines > 50000 {
		return fmt.Errorf("terminal scrollback lines out of range")
	}
	return BatchUpdateSettings(map[string]string{
		"asset_terminal_idle_timeout_seconds": fmt.Sprintf("%d", s.TerminalIdleTimeoutSeconds),
		"asset_terminal_scrollback_lines":     fmt.Sprintf("%d", s.TerminalScrollbackLines),
		"asset_credential_secret":             strings.TrimSpace(s.CredentialSecret),
	})
}

func assetTerminalIdleTimeoutSeconds() int {
	if _, ok := GetSettingValue("asset_terminal_idle_timeout_seconds"); ok {
		return parseIntSetting("asset_terminal_idle_timeout_seconds", 1800, 1, 86400)
	}
	return parseIntSetting("asset_terminal_idle_timeout_minutes", 30, 1, 1440) * 60
}

func parseIntSetting(key string, fallback, minVal, maxVal int) int {
	val := GetSetting(key)
	var n int
	if _, err := fmt.Sscanf(val, "%d", &n); err != nil || n < minVal || n > maxVal {
		return fallback
	}
	return n
}
