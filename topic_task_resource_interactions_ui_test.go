package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicTasksSupportNotesPageActions(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/topics.html")
	if err != nil {
		t.Fatalf("read topics template: %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}

	template := string(templateBytes)
	js := string(jsBytes)

	for _, required := range []string{
		`id="topicTaskSubmitBtn"`,
		`id="topicTaskDeleteBtn"`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("topic task modal should expose edit-mode controls, missing %q", required)
		}
	}

	for _, required := range []string{
		`editingTopicTaskId`,
		`openTaskModal: function(task)`,
		`saveTask: async function()`,
		`updateTaskDueDate: async function(task, dueDate)`,
		`openTaskDueDatePicker: function(task, source)`,
		`deleteTask: async function(task)`,
		`data-edit-task`,
		`data-delete-task`,
		`data-edit-task-due`,
		`class="task-pill task-due-pill`,
		`method: 'PUT'`,
		`method: 'DELETE'`,
		`topic_id: this.selectedId`,
		`topic.task.toast.saved`,
		`topic.task.toast.deleted`,
		`topic.task.toast.due_saved`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topic tasks should support the notes-page task actions, missing %q", required)
		}
	}

	if strings.Contains(js, `byId('topicTaskForm').addEventListener('submit', function(e) {
        e.preventDefault();
        self.createTask();
      });`) {
		t.Fatalf("topic task form should submit through saveTask so the same modal handles create and edit")
	}
}

func TestTopicResourceModalBehavesLikePicker(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/topics.html")
	if err != nil {
		t.Fatalf("read topics template: %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/topics.css")
	if err != nil {
		t.Fatalf("read topics css: %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}

	template := string(templateBytes)
	css := string(cssBytes)
	js := string(jsBytes)

	for _, required := range []string{
		`class="asset-modal topic-resource-picker-modal asset-modal-size-xl"`,
		`id="topicResourceFilterBar" role="group"`,
		`data-topic-resource-filter="all" aria-pressed="true"`,
		`data-topic-resource-filter="note" aria-pressed="false"`,
		`data-topic-resource-filter="document" aria-pressed="false"`,
		`data-topic-resource-filter="article" aria-pressed="false"`,
		`data-topic-resource-filter="bookmark" aria-pressed="false"`,
		`id="topicResourceSearchMeta"`,
		`id="topicSearchResults" class="topic-search-results" role="list" aria-live="polite"`,
		`id="topicResourceAddedCount"`,
		`id="topicResourceDoneBtn"`,
		`class="topic-resource-search-field"`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("topic resource modal should be a professional picker, missing %q", required)
		}
	}

	for _, required := range []string{
		`.topic-resource-picker-modal`,
		`max-height: calc(100dvh - 48px);`,
		`.topic-resource-filter-bar`,
		`min-height: 36px;`,
		`.topic-resource-filter-btn`,
		`display: inline-flex;`,
		`height: 32px;`,
		`line-height: 1.2;`,
		`.topic-resource-search-meta`,
		`.topic-resource-search-field`,
		`.topic-resource-search-field .topic-icon-btn`,
		`.topic-search-results[aria-busy="true"]`,
		`border: 1px solid var(--color-border-light);`,
		`border-radius: var(--radius-lg);`,
		`.topic-search-result:hover`,
		`.topic-search-result:focus-within`,
		`.topic-search-result.is-added`,
		`.topic-search-result.is-adding`,
		`.topic-resource-picker-foot`,
		`.topic-resource-picker-status`,
		`.topic-resource-state`,
		`.topic-resource-skeleton-row`,
		`@media (max-width: 640px)`,
		`width: 100%;`,
		`.topic-search-result-main`,
		`min-height: 0;`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("topic resource picker styles missing %q", required)
		}
	}

	for _, required := range []string{
		`topicResourceFilter: 'all'`,
		`topicResourceResults: []`,
		`topicResourceAddedKeys`,
		`topicResourceAddingKeys`,
		`topicResourceAddedSessionCount`,
		`topicModalPreviousFocus`,
		`renderResourceFilterBar: function()`,
		`handleResourceFilterKeydown: function(e, currentButton)`,
		`filterTopicResourceRows: function(rows)`,
		`resourceKey: function(row)`,
		`resourcePreviewHref: function(row)`,
		`isResourceAlreadyAdded: function(row)`,
		`renderTopicResourceState: function(type, title, message)`,
		`renderTopicResourceSkeletonRows: function()`,
		`updateTopicResourceAddedCount: function()`,
		`isTopicResourceModalOpen: function()`,
		`focusTopicResourceRow: function(key, preferButton)`,
		`trapTopicModalFocus: function(e)`,
		`data-add-resource-key`,
		`BookStarkRequestLock.run('topic-resource-add:'`,
		`this.renderSearchResults(this.topicResourceResults);`,
		`class="topic-search-result-link"`,
		`href="' + attr(self.resourcePreviewHref(row)) + '"`,
		`this.renderTopicResourcePickerMeta`,
		`byId('topicSearchResults').setAttribute('aria-busy', 'true')`,
		`btn.setAttribute('aria-pressed', active ? 'true' : 'false');`,
		`var scrollTop = resultsEl ? resultsEl.scrollTop : 0;`,
		`resultsEl.scrollTop = scrollTop;`,
		`if (this.topicModalPreviousFocus`,
		`if (!this.isTopicResourceModalOpen()) return;`,
		`if (!panel.contains(document.activeElement))`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topic resource picker behavior missing %q", required)
		}
	}
	if strings.Contains(js, `.slice(0, 50)`) {
		t.Fatalf("topic resource picker should not truncate all resource types before the active type filter is applied")
	}
	if strings.Contains(js, `byId('topicResourceKeyword').addEventListener('input'`) {
		t.Fatalf("topic resource picker should search only on Enter or explicit search button click")
	}
	for _, forbidden := range []string{
		`data-topic-resource-filter="task"`,
		`(result.tasks || []).forEach`,
		`Search existing notes, docs, articles, bookmarks, or todos.`,
		`Search notes, articles, docs, bookmarks, or todos`,
		`Attach notes, docs, articles, bookmarks, or todos.`,
	} {
		if strings.Contains(template+js, forbidden) {
			t.Fatalf("topic resource picker should keep todos in the dedicated topic tab, found %q", forbidden)
		}
	}
	if strings.Contains(css, `width: calc(100vw - 10px);`) {
		t.Fatalf("topic resource picker should be full width on small screens, not leave a 10px viewport gap")
	}

	if strings.Contains(js, `this.closeModal('topicItemModal');
        await this.loadDetail(this.selectedId);`) {
		t.Fatalf("adding a resource should keep the picker open for continuous adding")
	}
}

func TestTopicDesktopDetailColumnUsesAlignedContentRhythm(t *testing.T) {
	cssBytes, err := os.ReadFile("static/css/topics.css")
	if err != nil {
		t.Fatalf("read topics css: %v", err)
	}
	css := string(cssBytes)

	for _, required := range []string{
		`@media (min-width: 981px)`,
		`.topic-detail {`,
		`border: 0;`,
		`.topic-detail-sticky-controls {`,
		`padding: 0 0 14px;`,
		`display: flex;`,
		`flex-direction: column;`,
		`gap: 12px;`,
		`border-bottom: 0;`,
		`background: transparent;`,
		`.topic-detail-tabs-row {`,
		`margin: 0;`,
		`.topic-detail-search {`,
		`margin: 0;`,
		`.topic-detail-body {`,
		`padding: 0 0 24px;`,
		`background: var(--color-bg);`,
		`.topic-compact-row {`,
		`margin-bottom: 2px;`,
		`padding: 8px 12px;`,
		`border-radius: 4px;`,
		`.topic-resource-content-item {`,
		`min-height: 52px;`,
		`.topic-summary-card {`,
		`margin-bottom: 2px;`,
		`.topic-task-row {`,
		`min-height: 58px;`,
		`flex-direction: row;`,
		`background: var(--color-bg-card);`,
		`grid-template-columns: minmax(0, 1fr) auto;`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("desktop topic detail column should keep controls and list content aligned, missing %q", required)
		}
	}
	if strings.Contains(css, `.topic-summary-card .note-content {`) ||
		strings.Contains(css, `-webkit-line-clamp: 4;`) {
		t.Fatalf("topic summaries should show full content without desktop line clamping")
	}
}
