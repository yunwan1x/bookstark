package main

import (
	"os"
	"strings"
	"testing"
)

func TestInlineAIStreamShowsEditorStatusAfterPromptCloses(t *testing.T) {
	files := map[string]string{
		"templates/notes.html":  mustReadUIFile(t, "templates/notes.html"),
		"templates/topics.html": mustReadUIFile(t, "templates/topics.html"),
		"static/js/notes.js":    mustReadUIFile(t, "static/js/notes.js"),
		"static/js/topics.js":   mustReadUIFile(t, "static/js/topics.js"),
		"static/css/notes.css":  mustReadUIFile(t, "static/css/notes.css"),
		"i18n/zh.go":            mustReadUIFile(t, "i18n/zh.go"),
		"i18n/en.go":            mustReadUIFile(t, "i18n/en.go"),
	}

	for _, required := range []struct {
		file string
		want string
	}{
		{"templates/notes.html", `id="composeAIStreamStatus"`},
		{"templates/notes.html", `id="editorAIStreamStatus"`},
		{"templates/topics.html", `id="topicSummaryAIStreamStatus"`},
		{"static/css/notes.css", `.ai-inline-generation-status`},
		{"static/css/notes.css", `.ai-inline-generation-status.is-visible`},
		{"static/js/notes.js", `NotesApp.prototype._getAIStreamStatusEl = function(composer)`},
		{"static/js/notes.js", `this._setAIStreamStatus(composer, 'streaming', 0);`},
		{"static/js/notes.js", `writtenChars += chunk.length;`},
		{"static/js/notes.js", `this._hideAIStreamStatus(composer);`},
		{"static/js/topics.js", `setTopicSummaryAIStreamStatus: function(state, count, message)`},
		{"static/js/topics.js", `this.setTopicSummaryAIStreamStatus('streaming', 0);`},
		{"static/js/topics.js", `writtenChars += chunk.length;`},
		{"static/js/topics.js", `self.setTopicSummaryAIStreamStatus('idle');`},
		{"i18n/zh.go", `"note.ai.streaming_count":`},
		{"i18n/en.go", `"note.ai.streaming_count":`},
	} {
		if !strings.Contains(files[required.file], required.want) {
			t.Fatalf("%s missing %q", required.file, required.want)
		}
	}
}

func mustReadUIFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile(%s) error = %v", path, err)
	}
	return string(data)
}
