package main

import (
	"os"
	"strings"
	"testing"
)

func TestModalSaveActionsUseRequestLock(t *testing.T) {
	files := map[string][]string{
		"templates/index.html": {
			"BookStarkRequestLock.run('books:modal:'",
			"BookStarkRequestLock.run('books:share:'",
			"BookStarkRequestLock.run('books:delete:'",
			"bookModalSaveBtn",
		},
		"static/js/public-feed.js": {
			"lockKey: 'public:'",
		},
		"static/js/assets.js": {
			"runSubmitLocked",
			"BookStarkRequestLock.run",
			"assets:ssh:",
			"assets:credential:",
		},
		"static/js/editor.js": {
			"runShareLocked",
			"editor:share:publish:",
			"editor:share:edit-token:",
			"editor:share:reset-token:",
			"editor:share:unpublish:",
		},
	}
	for path, required := range files {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		text := string(data)
		for _, needle := range required {
			if !strings.Contains(text, needle) {
				t.Fatalf("%s missing modal submit lock marker %q", path, needle)
			}
		}
	}
}
