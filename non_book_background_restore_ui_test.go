package main

import (
	"os"
	"strings"
	"testing"
)

func TestNonBookCardsRestoreOpaqueBackgrounds(t *testing.T) {
	checks := []struct {
		path     string
		required []string
		forbid   []string
	}{
		{
			path: "static/css/notes.css",
			required: []string{
				`.note-card { background: var(--color-bg-card, #fff);`,
				`.article-card { background: var(--color-bg-card, #fff);`,
			},
			forbid: []string{
				`.note-card:hover { background: transparent;`,
				`.article-card:hover { background: transparent;`,
			},
		},
		{
			path: "static/css/tasks.css",
			required: []string{
				".task-row,\n.task-child-row,\n.tasks-empty {",
				"background: var(--color-bg-card);",
			},
			forbid: []string{".task-child-row:hover {\n    background: transparent;"},
		},
		{
			path:     "static/css/bookmarks.css",
			required: []string{".bm-row:hover .bm-row-content {\n    background: var(--color-bg-hover);"},
			forbid:   []string{".bm-row:hover {\n    background: transparent;"},
		},
		{
			path: "static/css/nav.css",
			required: []string{
				`.nav-card {`,
				`background: var(--color-bg-card);`,
				".nav-container.view-list .nav-card:hover {\n    background: var(--color-bg-hover);",
			},
			forbid: []string{
				".nav-card:hover {\n    background: transparent;",
				".nav-card:hover .nav-card-content {\n    background: transparent;",
			},
		},
		{
			path: "static/css/assets.css",
			required: []string{
				`.asset-table tbody tr:hover td { background: color-mix(in srgb, var(--color-primary) 5%, transparent); }`,
			},
			forbid: []string{
				`.asset-table-wrap:has(.asset-table tbody tr:hover)`,
				`#panel-settings:has(.asset-table tbody tr:hover)`,
			},
		},
		{
			path: "static/css/webdav.css",
			required: []string{
				".dav-file-row:hover {\n  background: var(--color-bg-hover);",
				".dav-file-row:hover {\n    background: var(--color-bg-card);",
			},
			forbid: []string{`.dav-drop-zone:has(.dav-file-row:hover)`},
		},
		{
			path: "static/css/topics.css",
			required: []string{
				".topic-card:hover {\n  background: var(--color-primary-light);",
				".topic-card.selected {\n  background: var(--color-primary-light);",
				".topic-summary-card:hover {\n  background: var(--color-bg-hover);",
				".topic-task-row:hover {\n  background: var(--color-bg-hover);",
				".topic-compact-row:hover {\n  background: var(--color-bg-hover);",
			},
		},
		{
			path: "templates/admin_system.html",
			required: []string{
				`.member-card { background: var(--color-bg-card);`,
				`.comment-admin-card {`,
				`background: var(--color-bg-card); }`,
				`.ai-action-section {`,
				`background: var(--color-bg-card, #fff);`,
			},
			forbid: []string{`.admin-system-content > [role="tabpanel"] { background: transparent`},
		},
		{
			path: "templates/profile.html",
			required: []string{
				`[data-theme="dark"] .profile-panel { background: var(--color-bg-card, #1e293b) !important;`,
				`background:var(--color-bg-card);`,
			},
			forbid: []string{
				`.profile-panel { background: transparent`,
				`.profile-panel .bg-slate-50 { background-color: transparent`,
			},
		},
		{
			path: "templates/images.html",
			required: []string{
				`.img-card { background: var(--color-bg-card);`,
				`.img-row {`,
				`background: var(--color-bg-card);`,
				`.img-row:hover { background: var(--color-bg-hover); }`,
			},
		},
		{
			path:   "templates/trash.html",
			forbid: []string{`#trash-list .list-row`},
		},
	}

	for _, check := range checks {
		data, err := os.ReadFile(check.path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", check.path, err)
		}
		content := string(data)
		for _, required := range check.required {
			if !strings.Contains(content, required) {
				t.Errorf("%s: missing restored opaque-background marker %q", check.path, required)
			}
		}
		for _, forbidden := range check.forbid {
			if strings.Contains(content, forbidden) {
				t.Errorf("%s: non-book transparency should be removed, found %q", check.path, forbidden)
			}
		}
	}
}

func TestBookShelfAndCompactBackgroundsStayTransparent(t *testing.T) {
	data, err := os.ReadFile("static/css/books.css")
	if err != nil {
		t.Fatalf("ReadFile(static/css/books.css) error = %v", err)
	}
	css := string(data)
	for _, required := range []string{
		".book-list.book-view-shelf {",
		"background-color: transparent;",
		".book-list.book-view-compact {",
		".book-compact-head {",
		".book-compact-row {",
		"background: transparent;",
	} {
		if !strings.Contains(css, required) {
			t.Errorf("book transparency marker missing: %q", required)
		}
	}
}
