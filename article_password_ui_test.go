package main

import (
	"os"
	"strings"
	"testing"
)

func TestArticlePasswordDialogVisibilityToggleAndOfflineError(t *testing.T) {
	js, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("read editor.js: %v", err)
	}
	css, err := os.ReadFile("static/css/editor.css")
	if err != nil {
		t.Fatalf("read editor.css: %v", err)
	}

	editor := string(js)
	styles := string(css)
	for _, want := range []string{
		`id="blog-pwd-toggle"`,
		`fa-eye-slash`,
		`inp.type = visible ? 'text' : 'password'`,
		`((err && err.message) || '密码不正确')`,
		`autocomplete="off"`,
		`data-lpignore="true"`,
		`getRememberedBlogPassword`,
		`rememberBlogPassword(pwd)`,
		`forgetRememberedBlogPassword(pwd)`,
	} {
		if !strings.Contains(editor, want) {
			t.Fatalf("editor.js missing %q", want)
		}
	}
	for _, want := range []string{
		".blog-pwd-input-wrap",
		".blog-pwd-toggle",
		"padding-right: 42px",
	} {
		if !strings.Contains(styles, want) {
			t.Fatalf("editor.css missing %q", want)
		}
	}
}

func TestNotesArticleSettingsPasswordInputsHaveVisibilityToggles(t *testing.T) {
	tpl, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("read notes.html: %v", err)
	}
	js, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("read notes.js: %v", err)
	}
	css, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("read notes.css: %v", err)
	}

	template := string(tpl)
	for _, want := range []string{
		`toggleArticlePasswordVisible('articleCurrentPwd', this)`,
		`toggleArticlePasswordVisible('articleNewPwd', this)`,
		`autocomplete="current-password"`,
		`autocomplete="new-password"`,
		`article-pwd-toggle`,
	} {
		if !strings.Contains(template, want) {
			t.Fatalf("notes.html missing %q", want)
		}
	}
	script := string(js)
	for _, want := range []string{
		"NotesApp.prototype.toggleArticlePasswordVisible",
		"NotesApp.prototype._resetArticlePasswordVisibility",
		"input.type = visible ? 'text' : 'password'",
		"fa-eye-slash",
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("notes.js missing %q", want)
		}
	}
	styles := string(css)
	for _, want := range []string{
		".article-pwd-input-wrap",
		".article-pwd-toggle",
		"padding-right: 42px",
	} {
		if !strings.Contains(styles, want) {
			t.Fatalf("notes.css missing %q", want)
		}
	}
}
