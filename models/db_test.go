package models

import (
	"os"
	"runtime"
	"strings"
	"testing"
)

func TestCreateTablesUsesCurrentSchemaWithoutLegacyMigrations(t *testing.T) {
	initAssetTestDB(t)

	for _, tc := range []struct {
		table string
		col   string
	}{
		{"md_members", "default_home"},
		{"md_blogs", "editor_type"},
		{"md_blogs", "blog_desc"},
		{"md_blogs", "location_name"},
		{"md_blogs", "latitude"},
		{"md_blogs", "longitude"},
		{"md_blogs", "location_accuracy"},
		{"md_documents", "doc_type"},
		{"md_uploads", "file_hash"},
		{"md_shares", "edit_token"},
		{"md_asset_ssh_hosts", "docker_socket_path"},
		{"md_tasks", "topic_id"},
		{"md_tasks", "complete_time"},
		{"md_topic_summaries", "summary_type"},
	} {
		var count int
		if err := DB.QueryRow("SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?", tc.table, tc.col).Scan(&count); err != nil {
			t.Fatalf("inspect %s.%s error = %v", tc.table, tc.col, err)
		}
		if count != 1 {
			t.Fatalf("%s.%s column count = %d, want 1", tc.table, tc.col, count)
		}
	}

	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatalf("runtime.Caller failed")
	}
	sourcePath := strings.TrimSuffix(file, "_test.go") + ".go"
	source, err := os.ReadFile(sourcePath)
	if err != nil {
		t.Fatalf("read %s: %v", sourcePath, err)
	}
	for _, legacy := range []string{
		"ALTER TABLE",
		"DROP TABLE IF EXISTS md_tasks",
		"DROP INDEX IF EXISTS idx_blogs_title_member",
		"migrateMemberColumns",
		"migrateBlogColumns",
		"migrateDocumentColumns",
		"migrateUploadColumns",
		"migrateShareColumns",
		"migrateAssetSSHHostColumns",
		"ensureTopicSchema",
		"ensureActionSchema",
	} {
		if strings.Contains(string(source), legacy) {
			t.Fatalf("db.go still contains legacy migration marker %q", legacy)
		}
	}
}
