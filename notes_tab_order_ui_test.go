package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesPageTabsOrderNotesArticlesTasks(t *testing.T) {
	tplBytes, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(notes.html) error = %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(notes.js) error = %v", err)
	}
	tpl := string(tplBytes)
	js := string(jsBytes)

	notesTab := `data-tab="notes" data-swipe-idx="0" onclick="notesApp.switchTab('notes')"`
	articlesTab := `data-tab="articles" data-swipe-idx="1" onclick="notesApp.switchTab('articles')"`
	tasksTab := `data-tab="tasks" data-swipe-idx="2" onclick="notesApp.switchTab('tasks')"`
	for _, required := range []string{notesTab, articlesTab, tasksTab} {
		if !strings.Contains(tpl, required) {
			t.Fatalf("notes page tab order markup missing %q", required)
		}
	}
	if !(strings.Index(tpl, notesTab) < strings.Index(tpl, articlesTab) && strings.Index(tpl, articlesTab) < strings.Index(tpl, tasksTab)) {
		t.Fatalf("notes page tabs should render in notes, articles, tasks order")
	}
	if strings.Contains(tpl, `data-tab="tasks" data-swipe-idx="1"`) || strings.Contains(tpl, `data-tab="articles" data-swipe-idx="2"`) {
		t.Fatalf("notes page should not keep the old notes, tasks, articles swipe order")
	}
	if !strings.Contains(js, `BookStarkTabURL.get('tab', ['notes', 'articles', 'tasks'], 'notes')`) {
		t.Fatalf("notes tab URL allowlist should match notes, articles, tasks order")
	}
}
