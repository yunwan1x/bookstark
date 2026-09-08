package main

import (
	"os"
	"strings"
	"testing"
)

func TestTaskDueLabelPickerKeepsPillAppearance(t *testing.T) {
	jsData, err := os.ReadFile("static/js/tasks.js")
	if err != nil {
		t.Fatalf("ReadFile(tasks.js) error = %v", err)
	}
	cssData, err := os.ReadFile("static/css/tasks.css")
	if err != nil {
		t.Fatalf("ReadFile(tasks.css) error = %v", err)
	}
	zhData, err := os.ReadFile("i18n/zh.go")
	if err != nil {
		t.Fatalf("ReadFile(zh.go) error = %v", err)
	}
	enData, err := os.ReadFile("i18n/en.go")
	if err != nil {
		t.Fatalf("ReadFile(en.go) error = %v", err)
	}

	js := string(jsData)
	for _, required := range []string{
		"function renderStatusPill(task, doneLabel, openLabel)",
		"task.status.overdue",
		"renderStatusPill(task, doneLabel, openLabel)",
		"renderStatusPill(child, doneLabel, openLabel)",
		"function renderDuePill(task)",
		"class=\"task-pill task-due-pill",
		"data-action=\"edit-due\"",
		"function openDueDatePicker(task, source)",
		"input.type = 'date'",
		"document.body.appendChild(input)",
		"source.__bookstarkDuePickerOpen = true",
		"source.__bookstarkDuePickerOpen = false",
		"if (typeof source.blur === 'function') source.blur();",
		"function updateTaskDueDate(task, dueDate)",
		"function normalizeDueDate(value)",
		"function bindRequiredDueDate(inputID)",
		"dueDate = normalizeDueDate(dueDate);",
		"lockKey: 'task-due:' + task.task_id",
		"task.toast.due_saved",
		"if (typeof input.showPicker === 'function')",
		"input.click();",
		"if (action === 'edit-due') openDueDatePicker(task, btn);",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("task due inline editor missing %q", required)
		}
	}

	css := string(cssData)
	for _, required := range []string{
		"button.task-pill",
		".task-due-pill:hover",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("task due inline editor style missing %q", required)
		}
	}
	for _, forbidden := range []string{
		".task-row.overdue:not(.done)",
		".task-child-row.overdue:not(.done)",
		".task-due-inline-input",
		"text-decoration: line-through",
	} {
		if strings.Contains(css, forbidden) {
			t.Fatalf("tasks.css should not include forbidden task visual style %q", forbidden)
		}
	}

	for _, required := range []string{
		"task.action.set_due",
		"task.toast.due_saved",
		"task.status.overdue",
	} {
		if !strings.Contains(string(zhData), required) || !strings.Contains(string(enData), required) {
			t.Fatalf("task due inline editor i18n missing %q", required)
		}
	}
	for _, forbidden := range []string{
		"input.className = 'task-due-inline-input'",
		"source.classList.add('is-editing')",
		"source.classList.remove('is-editing')",
		"source.replaceWith(input)",
		"input.replaceWith(source)",
	} {
		if strings.Contains(js, forbidden) {
			t.Fatalf("task due picker should keep the existing pill instead of replacing it with %q", forbidden)
		}
	}
}
