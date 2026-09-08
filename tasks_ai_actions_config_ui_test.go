package main

import (
	"os"
	"strings"
	"testing"
)

func TestTasksAIActionsUseTaskSystemConfig(t *testing.T) {
	files := map[string]string{}
	for _, path := range []string{
		"models/setting.go",
		"models/ai_defaults.go",
		"controllers/blog.go",
		"templates/admin_system.html",
		"templates/notes.html",
		"static/js/notes.js",
		"static/js/tasks.js",
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
		if !strings.Contains(files[path], "ai_actions_task") {
			t.Fatalf("%s missing ai_actions_task setting", path)
		}
	}

	joined := files["controllers/blog.go"] + "\n" + files["templates/notes.html"]
	for _, required := range []string{
		`data["AIActionsTask"] = models.GetSetting("ai_actions_task")`,
		`window.TASK_AI_ACTIONS_RAW = {{jsonJS .AIActionsTask}}`,
	} {
		if !strings.Contains(joined, required) {
			t.Fatalf("task AI config plumbing missing %q", required)
		}
	}

	for _, required := range []string{
		`id="ai_actions_task" name="ai_actions_task"`,
		`resetAIDefault('ai_actions_task')`,
		`admin.settings.ai.actions.task`,
	} {
		if !strings.Contains(files["templates/admin_system.html"], required) {
			t.Fatalf("admin AI task action editor missing %q", required)
		}
	}

	for _, required := range []string{
		"quickActions",
		"_getTaskAIActions",
		"window.TASK_AI_ACTIONS_RAW",
	} {
		if !strings.Contains(files["static/js/tasks.js"]+files["static/js/notes.js"], required) {
			t.Fatalf("task AI action renderer missing %q", required)
		}
	}

	for _, path := range []string{"i18n/zh.go", "i18n/en.go"} {
		if !strings.Contains(files[path], "admin.settings.ai.actions.task") {
			t.Fatalf("%s missing task action i18n keys", path)
		}
	}
}
