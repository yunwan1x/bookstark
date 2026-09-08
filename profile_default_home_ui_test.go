package main

import (
	"os"
	"strings"
	"testing"
)

func TestProfileDefaultHomeSettingUI(t *testing.T) {
	tpl, err := os.ReadFile("templates/profile.html")
	if err != nil {
		t.Fatalf("ReadFile(profile.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`id="default-home"`,
		`profile.field.default_home`,
		`<option value="notes"`,
		`<option value="tasks"`,
		`<option value="articles"`,
		`<option value="books"`,
		`<option value="bookmarks"`,
		`<option value="nav"`,
		`<option value="search"`,
		`default_home:document.getElementById('default-home').value`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("profile default home UI missing %q", required)
		}
	}
}

func TestHeaderNavKeepsDirectNavigationPageEntry(t *testing.T) {
	tpl, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	if !strings.Contains(string(tpl), `href="/nav" class="header-menu-item {{if eq .Nav "nav"}}active{{end}}"`) {
		t.Fatalf("header navigation menu should link to /nav after / becomes default-home router")
	}
}
