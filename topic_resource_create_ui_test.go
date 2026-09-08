package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicResourcePickerUsesSharedResourceCreator(t *testing.T) {
	topicTemplate := mustReadTopicCreateFile(t, "templates/topics.html")
	sharedTemplate := mustReadTopicCreateFile(t, "templates/resource_create.html")
	topicJS := mustReadTopicCreateFile(t, "static/js/topics.js")
	sharedJS := mustReadTopicCreateFile(t, "static/js/resource-create.js")
	sharedCSS := mustReadTopicCreateFile(t, "static/css/resource-create.css")

	for _, required := range []string{
		`id="topicResourceCreateBtn"`,
		`{{template "resource-create-modal" .}}`,
		`/static/js/resource-create.js`,
		`/static/css/resource-create.css`,
		`/static/css/selection-controls.css`,
		`/static/js/tag-input.js`,
		`/static/js/selection-controls.js`,
	} {
		if !strings.Contains(topicTemplate, required) {
			t.Fatalf("topics page should contain %q", required)
		}
	}
	for _, forbidden := range []string{
		`id="topicResourceCreateForm"`,
		`id="topicCreateNoteContent"`,
		`data-topic-item-panel="create"`,
	} {
		if strings.Contains(topicTemplate, forbidden) {
			t.Fatalf("topics page should not keep duplicated compact creator %q", forbidden)
		}
	}

	for _, required := range []string{
		`id="resourceCreateModal"`,
		`id="resourceCreateForm"`,
		`id="resourceCreateContent"`,
		`id="resourceCreateSubmitBtn"`,
		`data-mobile-sheet`,
	} {
		if !strings.Contains(sharedTemplate, required) {
			t.Fatalf("shared resource creator template should contain %q", required)
		}
	}

	for _, required := range []string{
		`window.BookStarkResourceCreate.open`,
		`onCreated: async function(row)`,
		`await self.addSearchResource(row`,
		`onCancel: restorePicker`,
		`onClose: restorePicker`,
	} {
		if !strings.Contains(topicJS, required) {
			t.Fatalf("topic integration should contain %q", required)
		}
	}

	for _, required := range []string{
		`global.BookStarkResourceCreate`,
		`global.BookStarkSearchSelect.create`,
		`global.BookStarkTreePicker.create`,
		`global.MarkdownComposer.create`,
		`new global.TagInput`,
		`/api/fetch-meta`,
		`/api/books?page=1&page_size=30&keyword=`,
		`/api/blogs`,
		`/api/bookmarks`,
		`/docs/tree`,
		`data-resource-editor-type`,
		`onPasteFile: uploadImage`,
		`favicon: state.bookmarkFavicon`,
		`event.key === 'Tab'`,
	} {
		if !strings.Contains(sharedJS, required) {
			t.Fatalf("shared resource creator should contain %q", required)
		}
	}

	for _, forbidden := range []string{
		`<select class="dialog-input" id="resourceCreateDocumentBook"`,
		`<select class="dialog-input" id="resourceCreateDocumentFolder"`,
		`function flattenFolders(`,
		`task: { icon: 'fa-list-check'`,
		`function renderTask(`,
		`/api/tasks`,
	} {
		if strings.Contains(sharedJS, forbidden) {
			t.Fatalf("shared resource creator should use shared searchable/tree controls, found %q", forbidden)
		}
	}

	for _, required := range []string{
		`.resource-create-modal`,
		`.resource-create-toolbar`,
		`.resource-create-type-grid`,
		`@media (max-width: 640px)`,
		`width: 100%;`,
		`height: var(--bs-vvh, var(--visual-viewport-height, 100dvh));`,
		`grid-template-columns: repeat(2, minmax(0, 1fr));`,
	} {
		if !strings.Contains(sharedCSS, required) {
			t.Fatalf("shared resource creator styles should contain %q", required)
		}
	}
}

func mustReadTopicCreateFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}
