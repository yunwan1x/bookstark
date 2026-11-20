package main

import (
	"bookstark/models"
	"fmt"
	"testing"
	"time"
)

func TestPublicWorkspaceBrowser(t *testing.T) {
	runIsolatedBrowser(t, "public_workspace_browser_test.cjs", func(t *testing.T) {
		for i := 0; i < 17; i++ {
			blog := &models.Blog{BlogTitle: fmt.Sprintf("Workspace article %02d", i), BlogIdentify: fmt.Sprintf("workspace-%d", i), BlogType: "article", BlogContent: "A public knowledge resource.", MemberID: 1, Visibility: 1}
			if err := blog.Insert(); err != nil {
				t.Fatal(err)
			}
			if err := models.BindLabelsFromNames(blog.BlogID, "blog", "工具"); err != nil {
				t.Fatal(err)
			}
		}
		note := &models.Blog{BlogTitle: "Workspace note", BlogIdentify: "workspace-note", BlogType: "note", BlogContent: "**One idea at a time.**\n\n- Capture\n- Connect", MemberID: 1, Visibility: 1}
		if err := note.Insert(); err != nil {
			t.Fatal(err)
		}
		book := &models.Book{BookName: "Workspace book", Identify: "workspace-book", MemberID: 1, Description: "Knowledge, organized.", CreateTime: time.Now()}
		if err := book.Insert(); err != nil {
			t.Fatal(err)
		}
		if _, err := models.CreateShare("book", book.BookID, 1, ""); err != nil {
			t.Fatal(err)
		}
		for i, title := range []string{"投资认知—从市场机制到投资决策", "技术笔记", "设计手册"} {
			extra := &models.Book{BookName: title, Identify: fmt.Sprintf("widget-book-%d", i), MemberID: 1, Description: "记录实践中的思考与经验，从知识整理到日常应用。", CreateTime: time.Now()}
			if err := extra.Insert(); err != nil {
				t.Fatal(err)
			}
			if _, err := models.CreateShare("book", extra.BookID, 1, ""); err != nil {
				t.Fatal(err)
			}
		}

		bookmark := &models.Bookmark{Title: "Workspace bookmark", URL: "https://example.com/docs", Description: "Reference documentation", MemberID: 1, IsPublic: true}
		if err := bookmark.Insert(); err != nil {
			t.Fatal(err)
		}
	})
}
