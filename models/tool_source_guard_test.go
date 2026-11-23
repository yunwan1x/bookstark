package models

import (
	"strings"
	"testing"
)

func TestToolReferenceSchemaStoresOnlyHTMLAndResourceAddresses(t *testing.T) {
	initAssetTestDB(t)
	for i := 0; i < 2; i++ {
		if err := initToolMarketTables(); err != nil {
			t.Fatal(err)
		}
	}
	rows, err := DB.Query("PRAGMA table_info(md_tool_versions)")
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	columns := map[string]bool{}
	for rows.Next() {
		var cid, required, primary int
		var name, kind string
		var value any
		if err := rows.Scan(&cid, &name, &kind, &required, &value, &primary); err != nil {
			t.Fatal(err)
		}
		if kind == "BLOB" {
			t.Fatalf("tool version has a binary payload column: %s", name)
		}
		columns[name] = true
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if columns["package"] || !columns["content"] || !columns["resource_base"] {
		t.Fatalf("unexpected version schema: %#v", columns)
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
			if _, err := DB.Exec("INSERT INTO md_tool_versions(blog_id,version,revision,metadata,content,resource_base,status,created) VALUES(?,?,?,?,?,?,?,?)", b.BlogID, "1.0.0", "bulk-"+status, "{}", b.BlogContent, "https://market.example/shares/"+b.BlogIdentify, status, 1); err != nil {
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
