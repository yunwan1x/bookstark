package main

import (
	"os"
	"strings"
	"testing"
)

func TestAdminAIPanelDarkThemeOverridesLightCards(t *testing.T) {
	tpl, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	text := string(tpl)
	for _, required := range []string{
		`[data-theme="dark"] #panel-ai { background: var(--color-bg-card, #1e293b) !important; border: 1px solid var(--color-border, #334155); }`,
		`.ai-subtabs { display: inline-flex; gap: 4px; padding: 3px; background: var(--color-gray-100, #f1f5f9);`,
		`.ai-subtab { appearance: none; -webkit-appearance: none; background-color: transparent;`,
		`[data-theme="dark"] #panel-ai .ai-subtabs { background: var(--color-gray-100, #1e293b); border-color: var(--color-border, #334155); }`,
		`[data-theme="dark"] #panel-ai .ai-subtab.active { background-color: var(--color-bg-hover, #334155) !important; color: var(--color-primary, #3b82f6); box-shadow: none; }`,
		`[data-theme="dark"] #panel-ai .ai-stat-card`,
		`[data-theme="dark"] #panel-ai .bg-purple-50`,
		`[data-theme="dark"] #panel-ai .bg-blue-50`,
		`[data-theme="dark"] #panel-ai .bg-emerald-50`,
		`[data-theme="dark"] #panel-ai .bg-amber-50`,
		`[data-theme="dark"] #panel-ai .ai-test-result-detail`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("admin AI dark theme override missing %q", required)
		}
	}
	for _, removed := range []string{
		"--color-bg-soft",
		"rgba(147,51,234,0.16)",
		"rgba(37,99,235,0.16)",
		"#c4b5fd",
		"review-role-key-badge",
	} {
		if strings.Contains(text, removed) {
			t.Fatalf("admin AI dark theme should reuse existing tokens, found %q", removed)
		}
	}
}
