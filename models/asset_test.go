package models

import (
	"context"
	"database/sql"
	"path/filepath"
	"sync"
	"testing"
)

var assetTestDBMu sync.Mutex

func initAssetTestDB(t *testing.T) {
	t.Helper()
	assetTestDBMu.Lock()
	if DB != nil {
		_ = DB.Close()
	}
	dbPath := filepath.Join(t.TempDir(), "asset-test.db")
	if err := InitDB(dbPath); err != nil {
		if DB != nil {
			_ = DB.Close()
			DB = nil
		}
		assetTestDBMu.Unlock()
		t.Fatalf("InitDB() error = %v", err)
	}
	t.Cleanup(func() {
		if DB != nil {
			_ = DB.Close()
			DB = nil
		}
		assetTestDBMu.Unlock()
	})
}

func TestAssetSSHHostCRUDPreservesCredentialOnBlankUpdate(t *testing.T) {
	initAssetTestDB(t)

	host := &AssetSSHHost{
		Name:             "prod-web-01",
		Host:             "10.0.1.21",
		Port:             22,
		Shell:            "/bin/bash",
		Cwd:              "/srv/app",
		Username:         "root",
		AuthType:         AssetAuthKey,
		CredentialCipher: "cipher-v1",
		CredentialHint:   "key saved",
		Status:           AssetStatusUnknown,
		CreatedBy:        1,
	}
	id, err := CreateAssetSSHHost(host)
	if err != nil {
		t.Fatalf("CreateAssetSSHHost() error = %v", err)
	}

	loaded, err := GetAssetSSHHost(id)
	if err != nil {
		t.Fatalf("GetAssetSSHHost() error = %v", err)
	}
	if loaded.Name != "prod-web-01" || loaded.CredentialCipher != "cipher-v1" {
		t.Fatalf("loaded host mismatch: %#v", loaded)
	}
	if loaded.Shell != "/bin/bash" || loaded.Cwd != "/srv/app" {
		t.Fatalf("loaded session config = shell %q cwd %q", loaded.Shell, loaded.Cwd)
	}

	loaded.Name = "prod-web-02"
	loaded.Shell = "/bin/zsh"
	loaded.Cwd = "/var/www"
	loaded.CredentialCipher = ""
	loaded.CredentialHint = ""
	if err := UpdateAssetSSHHost(loaded, false); err != nil {
		t.Fatalf("UpdateAssetSSHHost() preserve error = %v", err)
	}

	updated, err := GetAssetSSHHost(id)
	if err != nil {
		t.Fatalf("GetAssetSSHHost() after update error = %v", err)
	}
	if updated.Name != "prod-web-02" {
		t.Fatalf("Name = %q, want prod-web-02", updated.Name)
	}
	if updated.CredentialCipher != "cipher-v1" {
		t.Fatalf("CredentialCipher = %q, want preserved cipher-v1", updated.CredentialCipher)
	}
	if updated.Shell != "/bin/zsh" || updated.Cwd != "/var/www" {
		t.Fatalf("updated session config = shell %q cwd %q", updated.Shell, updated.Cwd)
	}
}

func TestDeletingSSHHostRemovesHost(t *testing.T) {
	initAssetTestDB(t)

	hostID, err := CreateAssetSSHHost(&AssetSSHHost{
		Name:             "docker-host",
		Host:             "192.168.1.20",
		Port:             22,
		Username:         "deploy",
		AuthType:         AssetAuthPassword,
		CredentialCipher: "cipher",
		CredentialHint:   "password saved",
		Status:           AssetStatusOnline,
		CreatedBy:        7,
	})
	if err != nil {
		t.Fatalf("CreateAssetSSHHost() error = %v", err)
	}
	if err := DeleteAssetSSHHost(hostID); err != nil {
		t.Fatalf("DeleteAssetSSHHost() error = %v", err)
	}
	if _, err := GetAssetSSHHost(hostID); err != sql.ErrNoRows {
		t.Fatalf("GetAssetSSHHost() error = %v, want sql.ErrNoRows", err)
	}
}

func TestAssetWebDAVServerCRUDAndCredentialProtection(t *testing.T) {
	initAssetTestDB(t)

	credentialID, err := CreateAssetCredential(&AssetCredential{
		Name:             "webdav-user",
		Username:         "dav",
		AuthType:         AssetAuthPassword,
		CredentialCipher: "secret",
		CredentialHint:   "password saved",
		CreatedBy:        7,
	})
	if err != nil {
		t.Fatalf("CreateAssetCredential() error = %v", err)
	}
	serverID, err := CreateAssetWebDAVServer(&AssetWebDAVServer{
		Name:         "nextcloud",
		URL:          "https://example.com/remote.php/dav/files/dav",
		RootPath:     "/docs",
		CredentialID: credentialID,
		Status:       AssetStatusUnknown,
		CreatedBy:    7,
	})
	if err != nil {
		t.Fatalf("CreateAssetWebDAVServer() error = %v", err)
	}
	loaded, err := GetAssetWebDAVServer(serverID)
	if err != nil {
		t.Fatalf("GetAssetWebDAVServer() error = %v", err)
	}
	if loaded.Name != "nextcloud" || loaded.CredentialName != "webdav-user" || loaded.Username != "dav" {
		t.Fatalf("loaded WebDAV server mismatch: %#v", loaded)
	}
	if err := DeleteAssetCredential(credentialID); err == nil {
		t.Fatalf("DeleteAssetCredential() succeeded for credential used by WebDAV server")
	}
	loaded.Name = "nextcloud-docs"
	loaded.RootPath = "/archive"
	if err := UpdateAssetWebDAVServer(loaded); err != nil {
		t.Fatalf("UpdateAssetWebDAVServer() error = %v", err)
	}
	updated, err := GetAssetWebDAVServer(serverID)
	if err != nil {
		t.Fatalf("GetAssetWebDAVServer() after update error = %v", err)
	}
	if updated.Name != "nextcloud-docs" || updated.RootPath != "/archive" {
		t.Fatalf("updated WebDAV server mismatch: %#v", updated)
	}
	if err := DeleteAssetWebDAVServer(serverID); err != nil {
		t.Fatalf("DeleteAssetWebDAVServer() error = %v", err)
	}
	if err := DeleteAssetCredential(credentialID); err != nil {
		t.Fatalf("DeleteAssetCredential() after server delete error = %v", err)
	}
}

func TestAssetDockerTableIsNotCreated(t *testing.T) {
	initAssetTestDB(t)

	var exists int
	if err := DB.QueryRow(`SELECT COUNT(1) FROM sqlite_master WHERE type='table' AND name='md_asset_docker_containers'`).Scan(&exists); err != nil {
		t.Fatalf("query sqlite_master error = %v", err)
	}
	if exists != 0 {
		t.Fatalf("md_asset_docker_containers exists = %d, want 0", exists)
	}
}

func TestAssetSQLiteForeignKeysEnabledOnPooledConnections(t *testing.T) {
	initAssetTestDB(t)

	ctx := context.Background()
	conns := make([]*sql.Conn, 0, 5)
	for i := 0; i < 5; i++ {
		conn, err := DB.Conn(ctx)
		if err != nil {
			t.Fatalf("DB.Conn(%d) error = %v", i, err)
		}
		conns = append(conns, conn)
	}
	defer func() {
		for _, conn := range conns {
			_ = conn.Close()
		}
	}()

	for i, conn := range conns {
		var enabled int
		if err := conn.QueryRowContext(ctx, "PRAGMA foreign_keys").Scan(&enabled); err != nil {
			t.Fatalf("PRAGMA foreign_keys on connection %d error = %v", i, err)
		}
		if enabled != 1 {
			t.Fatalf("PRAGMA foreign_keys on connection %d = %d, want 1", i, enabled)
		}
	}
}
