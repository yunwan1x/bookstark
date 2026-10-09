package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileHeaderNavSwipeSwitchesPagesByNavIndex(t *testing.T) {
	tpl, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	text := string(tpl)
	zh, err := os.ReadFile("i18n/zh.go")
	if err != nil {
		t.Fatalf("ReadFile(zh.go) error = %v", err)
	}
	if !strings.Contains(string(zh), `"nav.shares":          "分享",`) {
		t.Fatalf("Chinese shares nav label should be 分享")
	}
	if !strings.Contains(string(zh), `"nav.collections":     "合集",`) {
		t.Fatalf("Chinese collections nav label should be 合集")
	}
	if !strings.Contains(string(zh), `"nav.assets":          "资源",`) {
		t.Fatalf("Chinese resources nav label should be 资源")
	}
	for _, required := range []string{
		`data-swipe-nav`,
		`data-swipe-item="[data-nav-idx][href]"`,
		`data-swipe-index="data-nav-idx"`,
		`data-swipe-mode="href"`,
		`data-header-menu-trigger`,
		`header-knowledge-menu`,
		`header-collections-menu`,
		`header-assets-menu`,
		`header-create-menu`,
		`{{call .T "nav.knowledge"}}`,
		`{{call .T "nav.todos"}}`,
		`{{call .T "nav.collections"}}`,
		`{{call .T "nav.assets"}}`,
		`{{call .T "nav.create"}}`,
		`data-nav-idx="0"`,
		`data-nav-idx="1"`,
		`href="/shares" class="header-menu-item`,
		`href="/labels" class="header-menu-item`,
		`/notes?command=new-note`,
		`/notes?command=new-article`,
		`/books?command=new-book`,
		`/bookmarks?command=new-bookmark`,
		`href="/notes?tab=tasks"`,
		`href="/notes?tab=articles"`,
		`/notes?tab=tasks&command=new-task`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("mobile header nav index swipe missing %q", required)
		}
	}
	knowledgeMenu := extractBetween(t, text, `id="header-knowledge-menu"`, `id="header-collections-menu"`)
	for _, required := range []string{
		`href="/notes?tab=tasks"`,
		`href="/notes?tab=articles"`,
		`{{call .T "note.tab.articles"}}`,
		`(ne .ActiveKnowledgeTab "articles")`,
	} {
		if !strings.Contains(knowledgeMenu, required) {
			t.Fatalf("knowledge header menu should contain article item marker %q", required)
		}
	}
	collectionsMenu := extractBetween(t, text, `id="header-collections-menu"`, `id="header-assets-menu"`)
	for _, required := range []string{
		`href="/topics"`,
		`href="/labels"`,
	} {
		if !strings.Contains(collectionsMenu, required) {
			t.Fatalf("collections header menu should contain %q", required)
		}
	}
	if strings.Contains(collectionsMenu, `href="/shares"`) {
		t.Fatalf("shares should live under assets, not collections")
	}
	assetsMenu := extractBetween(t, text, `id="header-assets-menu"`, `</nav>`)
	for _, required := range []string{
		`href="/nav"`,
		`href="/shares"`,
		`href="/admin/assets"`,
	} {
		if !strings.Contains(assetsMenu, required) {
			t.Fatalf("assets header menu should contain %q", required)
		}
	}
	if strings.Contains(assetsMenu, `href="/labels"`) {
		t.Fatalf("labels should live under collections, not assets")
	}
	if strings.Contains(assetsMenu, `href="/webdav"`) {
		t.Fatalf("WebDAV should not appear in the assets header menu")
	}
	js, err := os.ReadFile("static/js/mobile-ui.js")
	if err != nil {
		t.Fatalf("ReadFile(mobile-ui.js) error = %v", err)
	}
	jsText := string(js)
	for _, required := range []string{
		"function enhanceIndexedSwipeNav",
		"root.querySelectorAll(itemSelector)",
		"window.location.assign(el.href)",
		"root.addEventListener('touchstart'",
		"document.addEventListener('touchmove'",
		"document.addEventListener('touchend'",
		"document.addEventListener('touchcancel'",
		"var startX = 0;",
		"suppressClick",
		"function autoEnhanceSwipeNavs",
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("shared mobile swipe nav missing %q", required)
		}
	}
	for _, removed := range []string{
		".page-swipe-dragging main",
		".page-swipe-settle main",
		".page-swipe-enter main",
		"@keyframes page-swipe-enter",
		"var MAX_DRAG",
		"function setPageSwipeOffset",
		"--page-swipe-x",
		"bookstark:header-page-swipe-dir",
		"window.location.href = links[next].href",
		"overflow-x: auto",
		"centerActiveNavItem",
		"nav.scrollTo({ left: Math.max(0, target), behavior: 'smooth' })",
		"function getHeaderNavItems",
	} {
		if strings.Contains(text, removed) {
			t.Fatalf("mobile header nav should use index navigation, found obsolete swipe code %q", removed)
		}
	}
	for _, removed := range []string{
		`aria-disabled="true"`,
		`{{call .T "nav.coming_soon"}}`,
		`header-action-menu`,
		`/tasks?tab=today`,
		`/tasks?tab=tasks`,
		`/tasks?tab=plans`,
	} {
		if strings.Contains(text, removed) {
			t.Fatalf("task navigation should be live, found obsolete placeholder %q", removed)
		}
	}
}

func extractBetween(t *testing.T, text, start, end string) string {
	t.Helper()
	startIdx := strings.Index(text, start)
	if startIdx < 0 {
		t.Fatalf("missing start marker %q", start)
	}
	tail := text[startIdx:]
	endIdx := strings.Index(tail, end)
	if endIdx < 0 {
		t.Fatalf("missing end marker %q after %q", end, start)
	}
	return tail[:endIdx]
}

func TestHeaderCreateMenuCommandsOpenExistingCreateFlows(t *testing.T) {
	files := map[string][]string{
		"templates/notes.html": {
			`params.get('command') === 'new-note'`,
			`params.get('command') === 'new-article'`,
			`openArticleSettingModal(null)`,
		},
		"templates/index.html": {
			`_bookParams.get('command') === 'new-book'`,
			`openBookModal();`,
		},
		"static/js/bookmarks.js": {
			`params.get('command') === 'new-bookmark'`,
			`showBookmarkDialog();`,
		},
		"static/js/tasks.js": {
			`params.get('command') === 'new-task'`,
			`openTaskSheet(null)`,
		},
	}
	for name, required := range files {
		content, err := os.ReadFile(name)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", name, err)
		}
		text := string(content)
		for _, item := range required {
			if !strings.Contains(text, item) {
				t.Fatalf("%s missing header create command hook %q", name, item)
			}
		}
	}
}
