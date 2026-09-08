package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesAIActionsUseSystemConfig(t *testing.T) {
	files := map[string]string{}
	for _, path := range []string{
		"models/setting.go",
		"models/ai_defaults.go",
		"controllers/blog.go",
		"templates/admin_system.html",
		"templates/notes.html",
		"static/js/notes.js",
		"i18n/zh.go",
		"i18n/en.go",
	} {
		b, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		files[path] = string(b)
	}

	for _, path := range []string{"models/setting.go", "models/ai_defaults.go"} {
		if !strings.Contains(files[path], "ai_actions_note") {
			t.Fatalf("%s missing ai_actions_note setting", path)
		}
	}
	for _, required := range []string{
		`data["AIActionsNote"] = models.GetSetting("ai_actions_note")`,
		`window.NOTE_AI_ACTIONS_RAW = {{jsonJS .AIActionsNote}}`,
	} {
		joined := files["controllers/blog.go"] + "\n" + files["templates/notes.html"]
		if !strings.Contains(joined, required) {
			t.Fatalf("notes config plumbing missing %q", required)
		}
	}
	for _, required := range []string{
		`id="ai_actions_note" name="ai_actions_note" hidden`,
		`id="aiNoteActionsList"`,
		`function addAINoteAction()`,
		`function deleteAINoteAction(idx)`,
		`syncAINoteActionsToTextarea()`,
		`resetAIDefault('ai_actions_note')`,
	} {
		if !strings.Contains(files["templates/admin_system.html"], required) {
			t.Fatalf("admin AI note action editor missing %q", required)
		}
	}
	for _, required := range []string{
		"_parseNoteAIActions",
		"_getNoteAIActions",
		"_renderNoteAIActionButtons",
		"window.NOTE_AI_ACTIONS_RAW",
		"data-note-ai-action",
	} {
		if !strings.Contains(files["static/js/notes.js"], required) {
			t.Fatalf("notes AI action renderer missing %q", required)
		}
	}
	for _, path := range []string{"i18n/zh.go", "i18n/en.go"} {
		if !strings.Contains(files[path], "admin.settings.ai.actions.note") {
			t.Fatalf("%s missing note action i18n keys", path)
		}
	}
}
