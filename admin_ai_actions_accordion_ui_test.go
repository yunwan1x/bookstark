package main

import (
	"os"
	"strings"
	"testing"
)

func TestAdminAISettingsUseAccordionSections(t *testing.T) {
	data, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	html := string(data)

	for _, required := range []string{
		".ai-action-sections",
		".ai-action-section",
		".ai-action-summary",
		".ai-action-body",
		".ai-action-tools",
		`<details class="ai-action-section" open>`,
		`id="ai_system_prompt_md" name="ai_system_prompt_md"`,
		`id="ai_system_prompt_html" name="ai_system_prompt_html"`,
		`id="ai_system_prompt_drawing" name="ai_system_prompt_drawing"`,
		`id="ai_actions_selection" name="ai_actions_selection"`,
		`id="ai_actions_html" name="ai_actions_html"`,
		`id="ai_actions_book" name="ai_actions_book"`,
		`id="ai_actions_article" name="ai_actions_article"`,
		`id="ai_actions_note" name="ai_actions_note" hidden`,
		`id="ai_actions_empty" name="ai_actions_empty"`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("AI actions accordion missing %q", required)
		}
	}

	if count := strings.Count(html, `class="ai-action-section"`); count < 9 {
		t.Fatalf("expected at least 9 AI accordion sections, got %d", count)
	}

	for _, removed := range []string{
		`<label class="block text-sm text-slate-700" for="ai_system_prompt_md"`,
		`<label class="block text-sm text-slate-700" for="ai_system_prompt_html"`,
		`<label class="block text-sm text-slate-700" for="ai_system_prompt_drawing"`,
		`<label class="block text-sm text-slate-700" for="ai_actions_selection"`,
		`<label class="block text-sm text-slate-700" for="ai_actions_html"`,
		`<label class="block text-sm text-slate-700" for="ai_actions_book"`,
		`<label class="block text-sm text-slate-700" for="ai_actions_article"`,
		`<label class="block text-sm text-slate-700" for="ai_actions_note"`,
		`<label class="block text-sm text-slate-700" for="ai_actions_empty"`,
	} {
		if strings.Contains(html, removed) {
			t.Fatalf("AI accordion still has duplicated visible label %q", removed)
		}
	}
}
