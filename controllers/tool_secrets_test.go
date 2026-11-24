package controllers_test

import (
	"bookstark/conf"
	"bookstark/models"
	"encoding/json"
	"errors"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestToolSecretsEncryptAuthorizeAndFollowInstallationLifecycle(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.InitWebDAVDB(filepath.Join(t.TempDir(), "files.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { models.WebDAVDB.Close(); models.WebDAVDB = nil })
	tool := models.InstalledTool{ID: 910, Title: "SSH", Revision: "v1", Content: "<h1>SSH</h1>", ToolMetadata: models.ToolMetadata{Permissions: models.ToolPermissions{Schema: 1, ReadFiles: true, SaveFiles: true}}}
	if err := models.SaveInstalledTool(1, tool, "", ""); err != nil {
		t.Fatal(err)
	}
	current, _ := models.GetInstalledTool(1, 910)
	request := func(op, name, value string, status int) any {
		raw, _ := json.Marshal(models.ToolFileOperation{Op: op, Path: name, Value: value})
		req := httptest.NewRequest("POST", "/api/tool-installs/910/files", strings.NewReader(string(raw)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Token "+token)
		req.Header.Set("X-Tool-Revision", current.Revision)
		req.Header.Set("X-Tool-Instance", current.Instance)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		if response.Code != status {
			t.Fatalf("%s: %d, wanted %d", op, response.Code, status)
		}
		var result map[string]any
		json.Unmarshal(response.Body.Bytes(), &result)
		return result["result"]
	}
	secret := `{"password":"test-secret-only","key":"PRIVATE KEY","passphrase":"口令"}`
	if request("secret_get", "ssh-host", "", 200) != nil {
		t.Fatal("absent secret")
	}
	request("secret_set", "ssh-host", secret, 200)
	if request("secret_get", "ssh-host", "", 200) != secret {
		t.Fatal("secret not restored")
	}
	p, _ := models.ToolResourcePath(current, "data", ".credentials/ssh-host")
	_, _, reader, err := models.ReadDAVFileContext(t.Context(), 1, p)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := io.ReadAll(reader)
	reader.Close()
	if !strings.HasPrefix(string(raw), "v1:") || strings.Contains(string(raw), "test-secret-only") || strings.Contains(string(raw), "PRIVATE KEY") {
		t.Fatal("plaintext persisted")
	}
	if info, err := os.Stat(conf.App.DBPath + ".tool-secrets.key"); err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("missing protected key", err)
	}
	request("secret_set", "../escape", secret, 400)
	request("secret_set", "too-big", strings.Repeat("x", (1<<20)+1), 413)
	request("secret_get", "ssh-other", "", 200)
	original := current.Revision
	current.Revision = "old"
	request("secret_get", "ssh-host", "", 409)
	request("secret_set", "ssh-host", "overwrite", 409)
	current.Revision = original
	// A package upgrade retains the same data root and encrypted credentials.
	tool.Revision = "v2"
	if err := models.SaveInstalledTool(1, tool, current.Revision, current.Instance); err != nil {
		t.Fatal(err)
	}
	current, _ = models.GetInstalledTool(1, 910)
	if request("secret_get", "ssh-host", "", 200) != secret {
		t.Fatal("upgrade lost credentials")
	}
	setPermissions := func(read, write bool) {
		tx, _ := models.DB.Begin()
		m := current.ToolMetadata
		m.Permissions.ReadFiles = read
		m.Permissions.SaveFiles = write
		if err := models.SaveToolMetadata(tx, 1, 910, m); err != nil {
			t.Fatal(err)
		}
		if err := tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}
	setPermissions(true, false)
	request("secret_get", "ssh-host", "", 200)
	request("secret_set", "ssh-host", "denied", 403)
	request("secret_remove", "ssh-host", "", 403)
	setPermissions(false, true)
	request("secret_get", "ssh-host", "", 403)
	request("secret_remove", "ssh-host", "", 200)
	setPermissions(true, true)
	if request("secret_get", "ssh-host", "", 200) != nil {
		t.Fatal("remove failed")
	}
	request("secret_set", "ssh-host", secret, 200)
	// Removing the workspace key fails closed, without creating a new one.
	key := conf.App.DBPath + ".tool-secrets.key"
	if err := os.Rename(key, key+".bak"); err != nil {
		t.Fatal(err)
	}
	request("secret_get", "ssh-host", "", 500)
	if _, err := os.Stat(key); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("key was regenerated")
	}
	if err := os.Rename(key+".bak", key); err != nil {
		t.Fatal(err)
	}
	request("secret_remove", "ssh-host", "", 200)
	request("secret_remove", "ssh-host", "", 200)
	request("secret_set", "ssh-host", secret, 200)
	// Different tools and accounts cannot observe the same secret name.
	other := tool
	other.ID = 911
	if err := models.SaveInstalledTool(1, other, "", ""); err != nil {
		t.Fatal(err)
	}
	otherMember := models.Member{Account: "secret-other", Password: "test-only", Status: 1, Role: 1}
	if err := otherMember.Insert(); err != nil {
		t.Fatal(err)
	}
	if err := models.SaveInstalledTool(otherMember.MemberID, tool, "", ""); err != nil {
		t.Fatal(err)
	}
	for _, owner := range [][2]int64{{1, 911}, {otherMember.MemberID, 910}} {
		entry, err := models.GetInstalledTool(owner[0], owner[1])
		if err != nil {
			t.Fatal(err)
		}
		if value, err := models.ExecuteToolFileOperation(owner[0], owner[1], entry.Revision, entry.Instance, models.ToolFileOperation{Op: "secret_get", Path: "ssh-host"}); err != nil || value != nil {
			t.Fatal("secret leaked", err)
		}
		// Copying ciphertext into that namespace must still fail GCM validation.
		if err := models.PutToolResource(owner[0], owner[1], entry.Revision, entry.Instance, "data", ".credentials/ssh-host", "application/octet-stream", strings.NewReader(string(raw))); err != nil {
			t.Fatal(err)
		}
		if _, err := models.ExecuteToolFileOperation(owner[0], owner[1], entry.Revision, entry.Instance, models.ToolFileOperation{Op: "secret_get", Path: "ssh-host"}); err == nil {
			t.Fatal("transplanted secret accepted")
		}
	}
	oldInstance := current.Instance
	if err := models.DeleteInstalledTool(1, 910, current.Revision, current.Instance, true); err != nil {
		t.Fatal(err)
	}
	if err := models.SaveInstalledTool(1, tool, "", ""); err != nil {
		t.Fatal(err)
	}
	current, _ = models.GetInstalledTool(1, 910)
	if current.Instance == oldInstance {
		t.Fatal("reinstall reused instance")
	}
	if request("secret_get", "ssh-host", "", 200) != secret {
		t.Fatal("keep-data reinstall lost credentials")
	}
	if err := models.DeleteInstalledTool(1, 910, current.Revision, current.Instance, false); err != nil {
		t.Fatal(err)
	}
	if err := models.SaveInstalledTool(1, tool, "", ""); err != nil {
		t.Fatal(err)
	}
	current, _ = models.GetInstalledTool(1, 910)
	if request("secret_get", "ssh-host", "", 200) != nil {
		t.Fatal("full uninstall retained credentials")
	}
}
