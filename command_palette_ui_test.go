package main

import (
	"os"
	"strings"
	"testing"
)

func TestCommandPaletteHasCoreActionsAndSearchMappings(t *testing.T) {
	js, err := os.ReadFile("static/js/command-palette.js")
	if err != nil {
		t.Fatalf("ReadFile(command-palette.js) error = %v", err)
	}
	text := string(js)
	for _, required := range []string{
		"command('搜索全站'",
		"command('笔记'",
		"command('待办'",
		"command('文章'",
		"command('专题'",
		"command('书籍'",
		"command('全局搜索'",
		"command('个人信息'",
		"command('回收站'",
		"command('新建笔记'",
		"command('新建待办'",
		"command('新建文章'",
		"command('新建专题'",
		"command('新建书籍'",
		"command('新建书签'",
		"command('图片管理'",
		"command('标签'",
		"command('主机'",
		"command('系统设置'",
		"command('访问统计'",
		"command('导航页', '/nav'",
		"(data.tasks || []).forEach",
		"(data.topics || []).forEach",
		"href: '/topics?id=' + encodeURIComponent",
		"task_id=' + encodeURIComponent",
		"b.name || b.book_name",
		"b.identify || b.book_identify",
		"l.name || l.label_name",
		"clearTimeout(state.searchTimer)",
		"function syncActiveItem()",
		"btn.addEventListener('mouseenter'",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("command palette missing %q", required)
		}
	}
	if strings.Contains(text, "btn.addEventListener('mouseenter', function() {\n        state.active = parseInt(btn.getAttribute('data-idx'), 10) || 0;\n        renderItems();") {
		t.Fatalf("command palette hover should not rerender the list before click fires")
	}
}

func TestHeaderShowsDesktopCommandPaletteHint(t *testing.T) {
	tpl, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	text := string(tpl)
	for _, required := range []string{
		`class="header-cmdk-hint"`,
		`BookStarkCommandPalette.open()`,
		`header.cmdk.label`,
		`header.cmdk.hint`,
		`<kbd>⌘K</kbd>`,
		`@media (min-width: 1024px) { .header-cmdk-hint { display: inline-flex; } }`,
		`header.search-expanded .header-cmdk-hint { display: none !important; }`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("header command palette hint missing %q", required)
		}
	}
}
