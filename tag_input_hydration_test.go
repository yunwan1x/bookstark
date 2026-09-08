package main

import (
	"os"
	"strings"
	"testing"
)

func TestTagInputClosedDropdownStaysClosed(t *testing.T) {
	data, err := os.ReadFile("static/js/tag-input.js")
	if err != nil {
		t.Fatalf("ReadFile(tag-input.js) error = %v", err)
	}
	js := string(data)
	for _, required := range []string{
		"this._searchVersion = 0",
		"var searchVersion = ++this._searchVersion",
		"searchVersion !== self._searchVersion",
		"document.activeElement !== input",
		"TagInput.prototype._cancelPendingSearch",
		"this._cancelPendingSearch();",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("TagInput stale-search guard missing %q", required)
		}
	}
}

func TestExistingTagsUseNonFocusingHydration(t *testing.T) {
	cases := []struct {
		path     string
		required []string
		forbid   []string
	}{
		{
			path: "static/js/bookmarks.js",
			required: []string{
				"ti.setTags(advLabels)",
				"dialogTagInput.setTags(existingLabels)",
				"dialogTagInput.setTags(bm.tag_names)",
			},
			forbid: []string{
				"advLabels.forEach(function(lb) { ti.addTag(lb); })",
				"existingLabels.forEach(function(lb) { dialogTagInput.addTag(lb); })",
				"bm.tag_names.forEach(function(t) { dialogTagInput.addTag(t); })",
			},
		},
		{
			path:     "static/js/nav.js",
			required: []string{"tagInput.setTags(b.labels || [])"},
			forbid:   []string{"(b.labels || []).forEach(function(label) { tagInput.addTag(label); })"},
		},
		{
			path: "static/js/notes.js",
			required: []string{
				"self.articleTagInput.setTags(NotesApp._extractTagsFromCard(artCard))",
				"self.editorTagInput.setTags(NotesApp._extractTagsFromCard(card))",
			},
		},
		{
			path:     "templates/index.html",
			required: []string{"bookTagInput.setTags(d.data.labels)"},
			forbid:   []string{"d.data.labels.forEach(function(l)"},
		},
	}

	for _, tc := range cases {
		data, err := os.ReadFile(tc.path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", tc.path, err)
		}
		content := string(data)
		for _, required := range tc.required {
			if !strings.Contains(content, required) {
				t.Errorf("%s missing non-focusing hydration %q", tc.path, required)
			}
		}
		for _, forbidden := range tc.forbid {
			if strings.Contains(content, forbidden) {
				t.Errorf("%s still contains focusing hydration %q", tc.path, forbidden)
			}
		}
	}
}
