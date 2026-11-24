package models

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"
)

// Start from the deployed schema rather than the new InitDB schema. The fixture
// deliberately includes installed and retained data that migration must not touch.
func initLegacyToolSourceFixture(t *testing.T) {
	t.Helper()
	assetTestDBMu.Lock()
	if DB != nil {
		_ = DB.Close()
	}
	var err error
	DB, err = sql.Open("sqlite", sqliteDSN(filepath.Join(t.TempDir(), "legacy-tools.db")))
	if err != nil {
		assetTestDBMu.Unlock()
		t.Fatal(err)
	}
	DB.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = DB.Close(); DB = nil; assetTestDBMu.Unlock() })
	for _, query := range []string{
		`CREATE TABLE md_members(member_id INTEGER PRIMARY KEY)`,
		`CREATE TABLE md_blogs(blog_id INTEGER PRIMARY KEY,member_id INTEGER NOT NULL REFERENCES md_members(member_id))`,
		`CREATE TABLE md_tool_releases(blog_id INTEGER PRIMARY KEY REFERENCES md_blogs(blog_id) ON DELETE CASCADE,title TEXT NOT NULL,description TEXT NOT NULL,content TEXT NOT NULL,revision TEXT NOT NULL)`,
		`CREATE TABLE md_tool_versions(blog_id INTEGER NOT NULL REFERENCES md_blogs(blog_id) ON DELETE CASCADE,version TEXT NOT NULL,revision TEXT NOT NULL UNIQUE,metadata TEXT NOT NULL,content TEXT NOT NULL,resource_base TEXT NOT NULL,status TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(blog_id,version))`,
		`CREATE TABLE md_tool_installs(member_id INTEGER NOT NULL,tool_id INTEGER NOT NULL,instance TEXT NOT NULL,assets TEXT NOT NULL,values_json TEXT NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE md_tool_retained(member_id INTEGER NOT NULL REFERENCES md_members(member_id) ON DELETE CASCADE,tool_id INTEGER NOT NULL,root TEXT NOT NULL,values_json TEXT NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE md_tool_install_metadata(member_id INTEGER NOT NULL,tool_id INTEGER NOT NULL,metadata TEXT NOT NULL,PRIMARY KEY(member_id,tool_id))`,
		`CREATE TABLE md_tool_remote_sources(id INTEGER PRIMARY KEY,member_id INTEGER NOT NULL,origin TEXT NOT NULL,remote_id INTEGER NOT NULL,UNIQUE(member_id,origin,remote_id))`,
		`CREATE TRIGGER md_tool_source_delete_guard BEFORE DELETE ON md_blogs WHEN EXISTS(SELECT 1 FROM md_tool_releases WHERE blog_id=OLD.blog_id) OR EXISTS(SELECT 1 FROM md_tool_versions WHERE blog_id=OLD.blog_id AND status='pending') BEGIN SELECT RAISE(ABORT,'blog_in_tool_market'); END`,
		`INSERT INTO md_members VALUES(1)`,
		`INSERT INTO md_blogs VALUES(42,1),(73,1),(80,1)`,
		`INSERT INTO md_tool_versions VALUES(42,'1.0.0','published-revision','{"version":"1.0.0","permissions":{"network":true}}','<h1>Published</h1>','https://market.test/shares/published','published',123),(73,'2.0.0','pending-revision','{"version":"2.0.0"}','<h1>Pending</h1>','https://market.test/shares/pending','pending',456)`,
		`INSERT INTO md_tool_releases VALUES(42,'Published tool','Description','<h1>Published</h1>','published-revision')`,
		`INSERT INTO md_tool_installs VALUES(1,42,'installation-instance','/BookStark/tools/installation-instance/assets/epoch','{"setting":"keep"}')`,
		`INSERT INTO md_tool_retained VALUES(1,42,'/BookStark/tools/installation-instance/data','{"retained":"keep"}')`,
		`INSERT INTO md_tool_install_metadata VALUES(1,42,'{"data_root":"/BookStark/tools/installation-instance/data","permissions":{"network":true}}')`,
		`INSERT INTO md_tool_remote_sources VALUES(7,1,'https://remote.test',42)`,
	} {
		if _, err := DB.Exec(query); err != nil {
			t.Fatalf("legacy fixture: %s: %v", query, err)
		}
	}
}

func TestToolSourceMigrationPreservesIdentitiesVersionsAndUserData(t *testing.T) {
	initLegacyToolSourceFixture(t)
	for run := 0; run < 2; run++ {
		if err := initToolSourceTables(); err != nil {
			t.Fatalf("migration run %d: %v", run, err)
		}
		if err := initToolMarketTables(); err != nil {
			t.Fatalf("market initialization run %d: %v", run, err)
		}
	}
	for _, id := range []int64{42, 73} {
		source, err := GetToolSource(id)
		if err != nil || source.ID != id || source.MemberID != 1 || source.Kind != "article" || !source.BlogID.Valid || source.BlogID.Int64 != id {
			t.Fatalf("legacy identity changed: %+v, %v", source, err)
		}
	}
	var version, revision, metadata, content, resourceBase, status string
	var created int64
	if err := DB.QueryRow(`SELECT version,revision,metadata,content,resource_base,status,created FROM md_tool_versions WHERE tool_id=42`).Scan(&version, &revision, &metadata, &content, &resourceBase, &status, &created); err != nil {
		t.Fatal(err)
	}
	if version != "1.0.0" || revision != "published-revision" || metadata != `{"version":"1.0.0","permissions":{"network":true}}` || content != "<h1>Published</h1>" || resourceBase != "https://market.test/shares/published" || status != "published" || created != 123 {
		t.Fatalf("version payload changed: %s %s %s %s %s %s %d", version, revision, metadata, content, resourceBase, status, created)
	}
	var instance, assets, values string
	if err := DB.QueryRow(`SELECT instance,assets,values_json FROM md_tool_installs WHERE member_id=1 AND tool_id=42`).Scan(&instance, &assets, &values); err != nil || instance != "installation-instance" || assets != "/BookStark/tools/installation-instance/assets/epoch" || values != `{"setting":"keep"}` {
		t.Fatalf("installed tool changed: %q %q %q %v", instance, assets, values, err)
	}
	var root string
	if err := DB.QueryRow(`SELECT root,values_json FROM md_tool_retained WHERE member_id=1 AND tool_id=42`).Scan(&root, &values); err != nil || root != "/BookStark/tools/installation-instance/data" || values != `{"retained":"keep"}` {
		t.Fatalf("retained data changed: %q %q %v", root, values, err)
	}
	if err := DB.QueryRow(`SELECT metadata FROM md_tool_install_metadata WHERE member_id=1 AND tool_id=42`).Scan(&metadata); err != nil || metadata != `{"data_root":"/BookStark/tools/installation-instance/data","permissions":{"network":true}}` {
		t.Fatalf("installed capabilities changed: %q %v", metadata, err)
	}
	var remoteID int64
	if err := DB.QueryRow(`SELECT remote_id FROM md_tool_remote_sources WHERE id=7 AND member_id=1 AND origin='https://remote.test'`).Scan(&remoteID); err != nil || remoteID != 42 {
		t.Fatalf("remote identity changed: %d %v", remoteID, err)
	}
	var count int
	if err := DB.QueryRow(`SELECT COUNT(*) FROM md_tools`).Scan(&count); err != nil || count != 2 {
		t.Fatalf("unexpected identities after repeated migration: %d %v", count, err)
	}
	if err := DB.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('md_tool_versions') WHERE name='blog_id'`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("legacy version identity column remains: %d %v", count, err)
	}
	rows, err := DB.Query(`PRAGMA foreign_key_check`)
	if err != nil {
		t.Fatal(err)
	}
	if rows.Next() {
		rows.Close()
		t.Fatal("migration introduced a broken foreign key")
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		t.Fatal(err)
	}
	rows.Close()
	// New package identities allocate independently without reusing legacy tools.
	result, err := DB.Exec(`INSERT INTO md_tools(member_id,kind) VALUES(1,'package')`)
	if err != nil {
		t.Fatal(err)
	}
	id, err := result.LastInsertId()
	if err != nil || id <= 73 {
		t.Fatalf("package reused a legacy tool ID: %d %v", id, err)
	}
	for _, blog := range []int64{42, 73} {
		if _, err := DB.Exec(`DELETE FROM md_blogs WHERE blog_id=?`, blog); err == nil || !strings.Contains(err.Error(), ErrBlogUsedByTool.Error()) {
			t.Fatalf("source deletion guard lost for %d: %v", blog, err)
		}
	}
	if _, err := DB.Exec(`DELETE FROM md_tool_releases WHERE tool_id=42`); err != nil {
		t.Fatal(err)
	}
	if _, err := DB.Exec(`DELETE FROM md_blogs WHERE blog_id=42`); err != nil {
		t.Fatalf("withdrawn source cannot be deleted: %v", err)
	}
	if err := DB.QueryRow(`SELECT COUNT(*) FROM md_tool_installs WHERE tool_id=42`).Scan(&count); err != nil || count != 1 {
		t.Fatalf("source deletion removed installed copy: %d %v", count, err)
	}
}

func TestToolSourceMigrationRollsBackInvalidLegacyAssociation(t *testing.T) {
	initLegacyToolSourceFixture(t)
	if _, err := DB.Exec(`PRAGMA foreign_keys=OFF`); err != nil {
		t.Fatal(err)
	}
	if _, err := DB.Exec(`INSERT INTO md_tool_versions VALUES(99,'1.0.0','orphan','{}','<h1>Missing source</h1>','https://market.test','pending',1)`); err != nil {
		t.Fatal(err)
	}
	if _, err := DB.Exec(`PRAGMA foreign_keys=ON`); err != nil {
		t.Fatal(err)
	}
	if err := initToolSourceTables(); err == nil {
		t.Fatal("invalid legacy source was silently migrated")
	}
	var count int
	if err := DB.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('md_tool_versions') WHERE name='blog_id'`).Scan(&count); err != nil || count != 1 {
		t.Fatalf("failed migration modified original schema: %d %v", count, err)
	}
	if err := DB.QueryRow(`SELECT COUNT(*) FROM md_tool_versions`).Scan(&count); err != nil || count != 3 {
		t.Fatalf("failed migration lost versions: %d %v", count, err)
	}
	if err := DB.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE name IN ('md_tools','md_tool_releases_legacy','md_tool_versions_legacy')`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("failed migration leaked partial schema: %d %v", count, err)
	}
}

func TestArticleToolIdentitySurvivesPackageIDCollision(t *testing.T) {
	initAssetTestDB(t)
	b := &Blog{BlogTitle: "Independent article", BlogIdentify: "independent-tool-source", BlogType: "article", EditorType: "html", MemberID: 1, BlogContent: "<h1>Article tool</h1>"}
	if err := b.Insert(); err != nil {
		t.Fatal(err)
	}
	// A package can already occupy the same numeric ID as a later article.
	if _, err := DB.Exec(`INSERT INTO md_tools(tool_id,member_id,kind) VALUES(?,1,'package')`, b.BlogID); err != nil {
		t.Fatal(err)
	}
	articleID, err := EnsureArticleTool(b.BlogID, 1)
	if err != nil || articleID == b.BlogID {
		t.Fatalf("article/package collision not resolved: article=%d blog=%d err=%v", articleID, b.BlogID, err)
	}
	if repeated, err := EnsureArticleTool(b.BlogID, 1); err != nil || repeated != articleID {
		t.Fatalf("article identity not stable: %d %v", repeated, err)
	}
	if resolved, err := ArticleToolID(b.BlogID); err != nil || resolved != articleID {
		t.Fatalf("article mapping incorrect: %d %v", resolved, err)
	}
	article, err := GetToolSource(articleID)
	if err != nil || article.Kind != "article" || !article.BlogID.Valid || article.BlogID.Int64 != b.BlogID {
		t.Fatalf("article association changed: %+v %v", article, err)
	}
	pkg, err := GetToolSource(b.BlogID)
	if err != nil || pkg.Kind != "package" || pkg.BlogID.Valid {
		t.Fatalf("package overwritten by article: %+v %v", pkg, err)
	}
	var count int
	if err := DB.QueryRow(`SELECT COUNT(*) FROM md_tools`).Scan(&count); err != nil || count != 2 {
		t.Fatalf("duplicate tool records: %d %v", count, err)
	}
}
