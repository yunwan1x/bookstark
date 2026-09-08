package main

import (
	"os"
	"strings"
	"testing"
)

func TestProfileThemeSelectOffersSixLocalThemes(t *testing.T) {
	tpl, err := os.ReadFile("templates/profile.html")
	if err != nil {
		t.Fatalf("ReadFile(profile.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`<option value="light">{{call .T "profile.theme.light"}}</option>`,
		`<option value="dark">{{call .T "profile.theme.dark"}}</option>`,
		`<option value="notion-pro">{{call .T "profile.theme.notion_pro"}}</option>`,
		`<option value="scholar-paper">{{call .T "profile.theme.scholar_paper"}}</option>`,
		`<option value="linear-saas">{{call .T "profile.theme.linear_saas"}}</option>`,
		`<option value="apple-minimal">{{call .T "profile.theme.apple_minimal"}}</option>`,
		`window.BookStarkTheme.set(theme)`,
		`select.value = theme;`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("profile theme variants missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`select.value = theme === 'dark' ? 'dark' : 'light';`,
		`<option value="ink-wash">`,
		`<option value="cinnabar-seal">`,
		`profile.theme.ink_wash`,
		`profile.theme.cinnabar_seal`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("profile theme variants should use the exact stored theme, found %q", forbidden)
		}
	}
}

func TestThemeRuntimeSupportsNamedLocalThemes(t *testing.T) {
	js, err := os.ReadFile("static/js/theme.js")
	if err != nil {
		t.Fatalf("ReadFile(theme.js) error = %v", err)
	}
	text := string(js)

	for _, required := range []string{
		`light: { scheme: 'light' }`,
		`dark: { scheme: 'dark' }`,
		`'notion-pro'`,
		`'scholar-paper'`,
		`'linear-saas'`,
		`'apple-minimal'`,
		`data-theme-style`,
		`function isDarkTheme(theme)`,
		`localStorage.setItem(STORAGE_KEY, next)`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("theme runtime missing named theme support %q", required)
		}
	}
	for _, forbidden := range []string{
		`'ink-wash'`,
		`'cinnabar-seal'`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("removed Chinese theme should not be registered in runtime, found %q", forbidden)
		}
	}
}

func TestThemeTokensDefineNamedThemePalettes(t *testing.T) {
	css, err := os.ReadFile("static/css/variables.css")
	if err != nil {
		t.Fatalf("ReadFile(variables.css) error = %v", err)
	}
	text := string(css)

	for _, required := range []string{
		`[data-theme-style="notion-pro"]`,
		`[data-theme-style="scholar-paper"]`,
		`[data-theme-style="linear-saas"]`,
		`[data-theme-style="apple-minimal"]`,
		`[data-theme-style="light"]`,
		`[data-theme-style="dark"]`,
		`--color-primary: #2563eb;`,
		`--color-primary: #5b6f54;`,
		`--color-primary: #7c3aed;`,
		`--color-primary: #111827;`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("theme tokens missing named palette support %q", required)
		}
	}
	for _, forbidden := range []string{
		`[data-theme-style="ink-wash"]`,
		`[data-theme-style="cinnabar-seal"]`,
		`--color-primary: #2e6b57;`,
		`--color-primary: #b33a2f;`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("removed Chinese theme should not be present in CSS, found %q", forbidden)
		}
	}
}

func TestRemovedChineseThemesAreNotLocalizedOrPreloaded(t *testing.T) {
	for _, tc := range []struct {
		path      string
		forbidden []string
	}{
		{
			path: "i18n/zh.go",
			forbidden: []string{
				`"profile.theme.ink_wash":`,
				`"文房水墨"`,
				`"profile.theme.cinnabar_seal":`,
				`"朱砂印章"`,
			},
		},
		{
			path: "i18n/en.go",
			forbidden: []string{
				`"profile.theme.ink_wash":`,
				`"Ink Wash Study"`,
				`"profile.theme.cinnabar_seal":`,
				`"Cinnabar Seal"`,
			},
		},
		{
			path: "templates/login.html",
			forbidden: []string{
				`'ink-wash':'light'`,
				`'cinnabar-seal':'light'`,
			},
		},
		{
			path: "templates/editor_common.html",
			forbidden: []string{
				`'ink-wash':'light'`,
				`'cinnabar-seal':'light'`,
			},
		},
		{
			path: "templates/register.html",
			forbidden: []string{
				`'ink-wash':'light'`,
				`'cinnabar-seal':'light'`,
			},
		},
	} {
		data, err := os.ReadFile(tc.path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", tc.path, err)
		}
		text := string(data)
		for _, forbidden := range tc.forbidden {
			if strings.Contains(text, forbidden) {
				t.Fatalf("%s should not contain removed Chinese theme marker %q", tc.path, forbidden)
			}
		}
	}
}

func TestHeaderThemeToggleIsHiddenWhenProfileOwnsThemeSelection(t *testing.T) {
	base, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	text := string(base)

	for _, required := range []string{
		`.header-theme-toggle { display: none !important; }`,
		`BookStarkTheme.toggle()`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("header theme toggle hiding missing %q", required)
		}
	}
}
