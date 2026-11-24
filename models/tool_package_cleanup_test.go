package models

import (
	"bookstark/internal/toolpackage"
	"database/sql"
	"encoding/json"
	"errors"
	"testing"
	"time"
)

func saveCleanupPackage(t *testing.T, member int64, name string) ToolPackage {
	t.Helper()
	p, err := SaveToolPackage(member, name, 16, toolpackage.Archive{Entry: "index.html", Entries: []string{"index.html"}, Files: []toolpackage.Asset{{Name: "index.html", MIME: "text/html", Data: []byte("<h1>" + name + "</h1>")}}})
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestToolPackageCleanupKeepsCurrentHistoryRecentAndOtherOwners(t *testing.T) {
	initAssetTestDB(t)
	setupWebDAVStoreTest(t)
	orphan := saveCleanupPackage(t, 1, "replaced.zip")
	current := saveCleanupPackage(t, 1, "current-draft.zip")
	historical := saveCleanupPackage(t, 1, "published-history.zip")
	recent := saveCleanupPackage(t, 1, "recent-unattached.zip")
	other := &Member{Account: "cleanup-owner", Email: "cleanup-owner@example.test", Password: "password", Role: 1, Status: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	otherPackage := saveCleanupPackage(t, other.MemberID, "other-orphan.zip")
	old := time.Now().Add(-48 * time.Hour).UnixMilli()
	for _, p := range []ToolPackage{orphan, current, historical, otherPackage} {
		if _, err := DB.Exec(`UPDATE md_tool_packages SET created=? WHERE token=?`, old, p.Token); err != nil {
			t.Fatal(err)
		}
	}
	result, err := DB.Exec(`INSERT INTO md_tools(member_id,kind,package_token) VALUES(1,'package',?)`, current.Token)
	if err != nil {
		t.Fatal(err)
	}
	id, err := result.LastInsertId()
	if err != nil {
		t.Fatal(err)
	}
	metadata, err := json.Marshal(ToolMetadata{Package: historical.Token, Version: "1.0.0", Distribution: "files"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := DB.Exec(`INSERT INTO md_tool_versions(tool_id,version,revision,metadata,content,resource_base,status,created) VALUES(?,'1.0.0','cleanup-published',?,'<h1>History</h1>','https://market.test','published',?)`, id, string(metadata), old); err != nil {
		t.Fatal(err)
	}
	if _, err := DB.Exec(`INSERT INTO md_tool_releases(tool_id,title,description,content,revision) VALUES(?,'History','','<h1>History</h1>','cleanup-published')`, id); err != nil {
		t.Fatal(err)
	}
	for run := 0; run < 2; run++ {
		if err := CleanupToolPackages(1); err != nil {
			t.Fatalf("cleanup run %d: %v", run, err)
		}
	}
	if _, err := GetToolPackage(orphan.Token); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("old unreferenced metadata retained: %v", err)
	}
	if _, err := GetDAVNode(1, toolPackageRoot(orphan.Token)); !errors.Is(err, ErrDAVNotFound) {
		t.Fatalf("old unreferenced files retained: %v", err)
	}
	for _, p := range []ToolPackage{current, historical, recent, otherPackage} {
		if _, err := GetToolPackage(p.Token); err != nil {
			t.Fatalf("live/recent/other package deleted %s: %v", p.Name, err)
		}
		if _, _, err := ReadToolPackageFile(p, "index.html"); err != nil {
			t.Fatalf("live/recent/other files deleted %s: %v", p.Name, err)
		}
	}
	for _, p := range []ToolPackage{current, historical} {
		if err := DiscardToolPackage(1, p.Token); err != nil {
			t.Fatal(err)
		}
		if _, err := GetToolPackage(p.Token); err != nil {
			t.Fatalf("direct discard removed referenced package: %s %v", p.Name, err)
		}
	}
	if err := DiscardToolPackage(1, otherPackage.Token); !errors.Is(err, ErrToolPermission) {
		t.Fatalf("cross-owner discard allowed: %v", err)
	}
}

func TestToolPackageDiscardRestoresMetadataWhenFileCleanupFails(t *testing.T) {
	initAssetTestDB(t)
	setupWebDAVStoreTest(t)
	p := saveCleanupPackage(t, 1, "retry-cleanup.zip")
	if _, err := WebDAVDB.Exec(`CREATE TRIGGER fail_package_cleanup BEFORE DELETE ON dav_nodes BEGIN SELECT RAISE(ABORT,'simulated storage failure'); END`); err != nil {
		t.Fatal(err)
	}
	if err := DiscardToolPackage(1, p.Token); err == nil {
		t.Fatal("failed file deletion reported success")
	}
	if _, err := GetToolPackage(p.Token); err != nil {
		t.Fatalf("cleanup failure lost retry metadata: %v", err)
	}
	if _, _, err := ReadToolPackageFile(p, "index.html"); err != nil {
		t.Fatalf("failed cleanup altered files: %v", err)
	}
	if _, err := WebDAVDB.Exec(`DROP TRIGGER fail_package_cleanup`); err != nil {
		t.Fatal(err)
	}
	if err := DiscardToolPackage(1, p.Token); err != nil {
		t.Fatalf("cleanup retry failed: %v", err)
	}
	if _, err := GetToolPackage(p.Token); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("cleanup retry retained metadata: %v", err)
	}
}
