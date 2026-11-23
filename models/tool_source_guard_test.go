package models

import (
	"bytes"
	"strings"
	"testing"
)

func TestToolReferenceSchemaMigrationRetainsLegacyArchives(t *testing.T) {
	initAssetTestDB(t)
	b := &Blog{BlogTitle: "Legacy tool", BlogIdentify: "legacy-guard-source", BlogType: "article", EditorType: "html", MemberID: 1, BlogContent: "<h1>Legacy</h1>"}
	if err := b.Insert(); err != nil {
		t.Fatal(err)
	}
	for _, query := range []string{
		"DROP TRIGGER md_tool_source_delete_guard",
		"DROP TABLE md_tool_versions",
		`CREATE TABLE md_tool_versions(blog_id INTEGER NOT NULL REFERENCES md_blogs(blog_id) ON DELETE CASCADE,version TEXT NOT NULL,revision TEXT NOT NULL UNIQUE,metadata TEXT NOT NULL,package BLOB NOT NULL,status TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(blog_id,version))`,
	} {
		if _, err := DB.Exec(query); err != nil {
			t.Fatal(err)
		}
	}
	archive := []byte{31, 139, 8, 0, 1, 2, 3}
	if _, err := DB.Exec("INSERT INTO md_tool_versions(blog_id,version,revision,metadata,package,status,created) VALUES(?,?,?,?,?,?,?)", b.BlogID, "1.0.0", "old-revision", "{}", archive, "published", 1); err != nil {
		t.Fatal(err)
	}
	if _, err := DB.Exec("INSERT INTO md_tool_releases(blog_id,title,description,content,revision) VALUES(?,?,?,?,?)", b.BlogID, b.BlogTitle, "", b.BlogContent, "old-revision"); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if err := initToolMarketTables(); err != nil {
			t.Fatalf("migration run %d: %v", i, err)
		}
	}
	var got []byte
	var content, base string
	if err := DB.QueryRow("SELECT package,content,resource_base FROM md_tool_versions WHERE blog_id=?", b.BlogID).Scan(&got, &content, &base); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, archive) || content != "" || base != "" {
		t.Fatalf("legacy archive changed during migration: %v %q %q", got, content, base)
	}
	if _, err := DB.Exec("DELETE FROM md_blogs WHERE blog_id=?", b.BlogID); err == nil {
		t.Fatal("migration did not install source deletion guard")
	}
	if _, err := DB.Exec("DELETE FROM md_tool_releases WHERE blog_id=?", b.BlogID); err != nil {
		t.Fatal(err)
	}
	if err := DeleteBlog(b.BlogID); err != nil {
		t.Fatal(err)
	}
}

func TestToolSourceBulkDeletionPreservesAssociations(t *testing.T) {
	initAssetTestDB(t)
	for _, status := range []string{"published", "pending"} {
		t.Run(status, func(t *testing.T) {
			b := &Blog{BlogTitle: "Protected " + status, BlogIdentify: "bulk-guard-" + status, BlogType: "article", EditorType: "html", MemberID: 1, BlogContent: "<h1>Keep original</h1>"}
			if err := b.Insert(); err != nil {
				t.Fatal(err)
			}
			if _, err := DB.Exec("INSERT INTO md_tool_versions(blog_id,version,revision,metadata,package,status,created) VALUES(?,?,?,?,?,?,?)", b.BlogID, "1.0.0", "bulk-"+status, "{}", []byte{}, status, 1); err != nil {
				t.Fatal(err)
			}
			if status == "published" {
				if _, err := DB.Exec("INSERT INTO md_tool_releases(blog_id,title,description,content,revision) VALUES(?,?,?,?,?)", b.BlogID, b.BlogTitle, "", b.BlogContent, "bulk-"+status); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := CreateShare("blog", b.BlogID, 1, ""); err != nil {
				t.Fatal(err)
			}
			if _, err := DB.Exec("INSERT INTO md_label_relation(label_id,resource_id,relation_type) VALUES(?,?,?)", 1, b.BlogID, "blog"); err != nil {
				t.Fatal(err)
			}
			assertOriginal := func() {
				t.Helper()
				original, err := GetBlogByID(b.BlogID)
				if err != nil || original.BlogContent != b.BlogContent {
					t.Fatalf("protected source replaced: %#v %v", original, err)
				}
				for _, query := range []string{"SELECT COUNT(*) FROM md_shares WHERE share_type='blog' AND target_id=?", "SELECT COUNT(*) FROM md_label_relation WHERE relation_type='blog' AND resource_id=?"} {
					var count int
					if err := DB.QueryRow(query, b.BlogID).Scan(&count); err != nil || count != 1 {
						t.Fatalf("protected source association removed: %s count=%d %v", query, count, err)
					}
				}
			}
			result := &ImportResult{}
			_, err := importBlogs(&ExportData{Blogs: []ExportBlog{{BlogTitle: "Overwrite", BlogIdentify: b.BlogIdentify, BlogContent: "replacement", BlogType: "article"}}}, 1, func(string, string) string { return "overwrite" }, result)
			if err != nil || result.BlogsImported != 0 || result.BlogsSkipped != 1 {
				t.Fatalf("protected import not skipped: %+v %v", result, err)
			}
			assertOriginal()
			tx, err := DB.Begin()
			if err != nil {
				t.Fatal(err)
			}
			snapshot, title, err := SnapshotBlog(tx, b.BlogID)
			if err != nil {
				tx.Rollback()
				t.Fatal(err)
			}
			if err := CreateTrash(tx, "blog", title, snapshot, 1); err != nil {
				tx.Rollback()
				t.Fatal(err)
			}
			var trashID int64
			if err := tx.QueryRow("SELECT MAX(trash_id) FROM md_trash").Scan(&trashID); err != nil {
				tx.Rollback()
				t.Fatal(err)
			}
			if err := tx.Commit(); err != nil {
				t.Fatal(err)
			}
			messages, err := BatchDeleteTrash([]int64{trashID}, 1, true)
			if err != nil || len(messages) != 1 || !strings.Contains(messages[0], ErrBlogUsedByTool.Error()) {
				t.Fatalf("protected trash deletion did not report refusal: %v %v", messages, err)
			}
			assertOriginal()
			if _, err := GetTrashByID(trashID); err != nil {
				t.Fatal("blocked deletion removed its recycle entry")
			}
		})
	}
}
