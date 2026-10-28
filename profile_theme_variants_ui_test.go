package main

import (
	"os"
	"strings"
	"testing"
)

func TestProfileOnlyOffersDefaultAndIndependentBrandThemes(t *testing.T) {
	data, err := os.ReadFile("templates/profile.html")
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	start := strings.Index(text, "<select id=\"profile-theme\"")
	end := strings.Index(text[start:], "</select>") + start
	selectHTML := text[start:end]
	if strings.Count(selectHTML, "<option ") != 3 || !strings.Contains(selectHTML, "value=\"light\"") || !strings.Contains(selectHTML, "value=\"nvidia\"") || !strings.Contains(selectHTML, "value=\"apple\"") {
		t.Fatal("expected exactly default, NVIDIA and Apple themes")
	}
	if !strings.Contains(text, "window.BookStarkTheme.set(theme)") {
		t.Fatal("theme selection must use shared runtime")
	}
}

func TestRetiredThemesAreRemovedFromRuntimeAndFirstPaint(t *testing.T) {
	paths := []string{"static/css/variables.css", "static/js/theme.js", "templates/base.html", "templates/editor_common.html", "templates/notes_public.html", "templates/login.html", "templates/register.html", "templates/forgot_password.html", "templates/reset_password.html", "templates/profile.html", "i18n/zh.go", "i18n/en.go"}
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		text := string(data)
		for _, old := range []string{"notion-pro", "scholar-paper", "linear-saas", "apple-minimal", "profile.theme.dark", "profile.theme.notion_pro", "profile.theme.scholar_paper", "profile.theme.linear_saas", "profile.theme.apple_minimal"} {
			if strings.Contains(text, old) {
				t.Fatalf("%s still registers retired theme %s", path, old)
			}
		}
		if strings.HasPrefix(path, "templates/") && path != "templates/profile.html" {
			for _, marker := range []string{"nvidia:'dark'", "apple:'light'", "t='light'", "localStorage.setItem(k,t)", "hasOwnProperty.call(s,saved)"} {
				if !strings.Contains(text, marker) {
					t.Fatalf("%s missing first-paint rule %s", path, marker)
				}
			}
		}
	}
}

func TestIndependentThemesUseBrandTokensAndDefaultIsUnchanged(t *testing.T) {
	data, err := os.ReadFile("static/css/variables.css")
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, marker := range []string{"--color-primary: #2563eb;", "[data-theme-style=\"nvidia\"]", "[data-theme-style=\"apple\"]", "--color-primary: #76b900;", "--color-primary: #0066cc;", "--color-on-primary: #000000;", "--color-bg: #000000;", "--color-bg: #f5f5f7;", "--color-focus: #a3d957;", "--color-text-muted: #a2a2ac;", "backdrop-filter: none;"} {
		if !strings.Contains(text, marker) {
			t.Fatalf("missing theme token %s", marker)
		}
	}
	runtime, err := os.ReadFile("static/js/theme.js")
	if err != nil {
		t.Fatal(err)
	}
	for _, marker := range []string{"light: { scheme: 'light' }", "'nvidia': { scheme: 'dark' }", "apple: { scheme: 'light' }", "return DEFAULT_LIGHT_THEME;", "applyTheme(normalizeTheme(e.newValue))"} {
		if !strings.Contains(string(runtime), marker) {
			t.Fatalf("missing runtime behavior %s", marker)
		}
	}
}

func TestHeaderThemeToggleIsHiddenWhenProfileOwnsThemeSelection(t *testing.T) {
	data, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), ".header-theme-toggle { display: none !important; }") {
		t.Fatal("profile must own theme selection")
	}
}
