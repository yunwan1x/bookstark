package main

import (
	"os"
	"strings"
	"testing"
)

func TestTopicPageUsesLabelStyleDetailLayout(t *testing.T) {
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
	headAssetsIndex := strings.Index(template, `{{template "head-assets" .}}`)
	topicsCSSIndex := strings.Index(template, `/static/css/topics.css`)
	if headAssetsIndex < 0 || topicsCSSIndex < 0 || topicsCSSIndex < headAssetsIndex {
		t.Fatalf("topics page should load shared head assets before topic page CSS so asset modal size overrides win")
	}
	for _, required := range []string{
		`id="topicReadPanel"`,
		`class="topic-context-panel"`,
		`class="topic-side-card topic-comment-card"`,
		`id="topicCommentPanel"`,
		`{{call .T "topic.comment.title"}}`,
		`id="topicSummaryDockHost"`,
		`id="topicSummaryComposer"`,
		`id="topicSummaryImageButton"`,
		`id="topicSummaryFileInput"`,
		`id="topicSummaryEmojiButton"`,
		`id="topicSummaryPreviewButton"`,
		`id="topicSummaryPreview"`,
		`id="topicSummaryAIButton"`,
		`id="topicSummarySaveButton"`,
		`class="topic-compose-btn topic-summary-save-btn"`,
		`fa-floppy-disk`,
		`id="topicSummaryComposeDock"`,
		`id="topicSummaryEditorModal"`,
		`id="topicSummaryModalDock"`,
		`id="topicSummaryRestoreButton"`,
		`id="topicMobileCommentsBtn"`,
		`aria-controls="topicMobileCommentsModal"`,
		`id="topicMobileCommentsModal"`,
		`id="topicCommentMobileHost"`,
		`id="topicCommentComposer"`,
		`id="topicCommentImageButton"`,
		`id="topicCommentEmojiButton"`,
		`id="topicCommentPreviewButton"`,
		`id="topicCommentAIButton"`,
		`id="topicCommentClearButton"`,
		`id="topicCommentSaveButton"`,
		`id="topicCommentLocateBtn"`,
		`{{call .T "topic.comment.locate"}}`,
		`fa-location-crosshairs`,
		`class="asset-modal-backdrop" id="topicCreateModal"`,
		`class="asset-modal asset-modal-size-md" id="topicCreateForm"`,
		`class="asset-modal-head"`,
		`class="asset-modal-title" id="topicCreateTitle"`,
		`class="asset-modal-body"`,
		`class="asset-modal-foot"`,
		`class="editor-modal-close"`,
		`class="bs-btn bs-btn-primary"`,
		`/static/css/notes.css`,
		`/static/css/tasks.css`,
		`/static/js/marked.min.js`,
		`/static/js/markdown-composer.js`,
		`/static/js/ai-helper.js`,
		`<body class="min-h-screen flex flex-col topics-body">`,
		`topic-resource-content-list`,
		`class="topic-detail-tabs main-tabs"`,
		`class="topic-detail-tab main-tab topic-detail-tab-overview active"`,
		`id="topicDetailTabDetails"`,
		`role="tab" aria-selected="true"`,
		`role="tabpanel" aria-labelledby="topicDetailTabDetails"`,
		`fa-circle-info`,
		`class="topic-detail-sticky-controls"`,
		`class="topic-detail-tabs-row"`,
		`data-topic-detail-tab="details"`,
		`data-topic-detail-tab="resources"`,
		`fa-layer-group`,
		`data-topic-detail-tab="summaries"`,
		`fa-file-lines`,
		`data-topic-detail-tab="tasks"`,
		`fa-list-check`,
		`class="topic-detail-search tab-search"`,
		`id="topicDetailSearchInput"`,
		`id="topicDetailSearchBtn"`,
		`id="topicDetailCreateBtn"`,
		`class="topic-detail-create-btn topic-primary-btn"`,
		`id="topicDetailCreateBtn" title="{{call .T "topic.item.add"}}" aria-label="{{call .T "topic.item.add"}}">+</button>`,
		`px-4 py-2 bg-blue-600 text-white rounded-lg text-sm hover:bg-blue-700 whitespace-nowrap`,
		`id="topicEditModal"`,
		`id="topicEditForm"`,
		`id="editTopicTitle"`,
		`id="editTopicQuestion" class="md-composer-host md-composer-host-full topic-question-composer"`,
		`id="topicEditQuestionImageBtn"`,
		`id="topicEditQuestionEmojiBtn"`,
		`id="topicEditQuestionPreviewBtn"`,
		`id="topicEditQuestionClearBtn"`,
		`id="topicEditQuestionPreview"`,
		`id="topicEditQuestionFileInput"`,
		`id="topicEditDeleteBtn"`,
		`class="bs-btn bs-btn-danger" id="topicEditDeleteBtn"`,
		`class="bs-btn bs-btn-cancel" id="topicEditCancelBtn" data-close-modal="topicEditModal"`,
		`{{call .T "common.cancel"}}`,
		`id="topicMobileSidebarBtn"`,
		`aria-controls="topicRail" aria-expanded="false"`,
		`class="topic-mobile-comments-trigger"`,
		`data-mobile-sheet data-mobile-sheet-panel=".asset-modal"`,
		`id="topicMobileRailCloseBtn"`,
		`class="topic-mobile-sidebar-trigger"`,
		`id="topicFabBtn"`,
		`class="mobile-fab topic-fab"`,
		`id="topicMobileTopicBackdrop"`,
		`class="topic-empty-state hidden" id="topicEmptyState"`,
		`class="topic-detail-content" id="topicDetailContent"`,
		`data-topic-detail-panel="details"`,
		`id="topicOverviewPanel"`,
		`id="topicOverviewTitle"`,
		`class="topic-overview-question note-content" id="topicOverviewQuestion"`,
		`class="topic-overview-stat topic-overview-stat-resources topic-overview-stat-skeleton" disabled aria-hidden="true"`,
		`class="topic-overview-stat topic-overview-stat-summaries topic-overview-stat-skeleton" disabled aria-hidden="true"`,
		`class="topic-overview-stat topic-overview-stat-tasks topic-overview-stat-skeleton" disabled aria-hidden="true"`,
		`class="topic-skeleton-block topic-overview-stat-icon-skeleton"`,
		`class="topic-overview-stat-copy"`,
		`class="topic-skeleton-block topic-overview-stat-title-skeleton"`,
		`class="topic-skeleton-block topic-overview-stat-caption-skeleton"`,
		`class="topic-skeleton-block topic-overview-stat-chevron-skeleton"`,
		`id="topicOverviewUpdatedAt"`,
		`class="topic-overview-updated-time"`,
		`fa-clock`,
		`id="topicOverviewEditBtn"`,
		`id="topicOverviewPinBtn"`,
		`id="topicOverviewAIAssistantBtn"`,
		`topic-list-entry topic-list-skeleton`,
		`topic-detail-title-skeleton`,
		`topic-detail-line-skeleton`,
		`class="asset-modal topic-topic-edit-modal asset-modal-size-lg"`,
		`id="topicSummaryEditorModal"`,
		`class="asset-modal asset-modal-size-xl" role="dialog" aria-modal="true" aria-labelledby="topicSummaryEditorTitle"`,
		`class="asset-modal topic-resource-picker-modal asset-modal-size-xl"`,
		`class="asset-modal asset-modal-size-md" id="topicTaskForm"`,
		`class="topic-question-editor"`,
		`{{call .T "topic.detail.tab.details"}}`,
		`{{call .T "topic.detail.tab.resources"}}`,
		`{{call .T "topic.detail.search.resources.placeholder"}}`,
		`{{call .T "topic.resource.filter.all"}}`,
		`{{call .T "topic.task.modal.new"}}`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("topics template should contain %q", required)
		}
	}
	if strings.Contains(template, `class="topic-empty-state" id="topicEmptyState"`) ||
		strings.Contains(template, `class="topic-detail-content hidden" id="topicDetailContent"`) {
		t.Fatalf("topics template should paint the initial skeleton before async topic data returns")
	}
	if strings.Count(template, `data-topic-detail-panel="tasks"`) != 1 {
		t.Fatalf("topics template should contain exactly one tasks tab panel")
	}
	if strings.Contains(template, `topic-detail-tab-count`) {
		t.Fatalf("topic detail tabs should not render count nodes in the tab labels")
	}
	if strings.Contains(template, `id="topicTaskDueDate" required`) {
		t.Fatalf("topic task date should not be a required field in the quick-create modal")
	}
	if strings.Contains(template, `id="topicMobileCreateBtn"`) {
		t.Fatalf("mobile topic actions should use the contextual FAB instead of an inline create button")
	}
	if strings.Contains(template, `id="topicMobileSwitchBtn"`) || strings.Contains(template, `class="topic-mobile-actions"`) {
		t.Fatalf("mobile topic switcher should be a side trigger instead of an in-content toolbar")
	}
	if strings.Contains(template, `class="topic-side-card topic-summary-compose-card"`) ||
		strings.Contains(template, `id="topicSummaryMaximizeButton"`) {
		t.Fatalf("third column should show comments, not a persistent summary composer card")
	}
	saveButtonIndex := strings.Index(template, `id="topicSummarySaveButton"`)
	imageButtonIndex := strings.Index(template, `id="topicSummaryImageButton"`)
	emojiButtonIndex := strings.Index(template, `id="topicSummaryEmojiButton"`)
	if saveButtonIndex < 0 || imageButtonIndex < 0 || emojiButtonIndex < 0 || saveButtonIndex > imageButtonIndex || imageButtonIndex > emojiButtonIndex {
		t.Fatalf("summary toolbar should order save, image, emoji")
	}
	for _, forbidden := range []string{
		`class="topic-side-card topic-operation-card"`,
		`id="topicSidePinBtn"`,
		`id="topicSideEditBtn"`,
		`id="topicSideAddItemBtn"`,
		`id="topicSideAddTaskBtn"`,
		`class="topic-modal`,
		`class="topic-modal-panel`,
		`class="topic-modal-head`,
		`class="topic-modal-actions`,
		`class="topic-modal-backdrop`,
		`class="bs-dialog-overlay`,
		`class="bs-dialog-box`,
		`class="bs-dialog-title`,
		`class="bs-dialog-actions`,
		`>{{call .T "dialog.cancel"}}</button>`,
	} {
		if strings.Contains(template, forbidden) {
			t.Fatalf("topic modals should use the shared asset modal shell without extra cancel actions, found %q", forbidden)
		}
	}
	for _, required := range []string{
		`.topic-list-entry`,
		`.topic-read-head`,
		`.topic-context-panel`,
		`.topic-card-pin-badge`,
		`.topic-card-actions`,
		`.topic-card-action-separator`,
		`.topic-card-tool-btn`,
		`.topic-card-tool-btn.is-pinned`,
		`.topic-detail-create-btn`,
		`.topic-comment-card`,
		`.topic-comment-head`,
		`.topic-comment-list`,
		`.topic-comment-item`,
		`.topic-comment-compose`,
		`.topic-comment-scope`,
		`#topicMobileCommentsModal .topic-comment-head h2`,
		`.topic-summary-dock-host`,
		`.topic-summary-compose-head`,
		`.topic-summary-compose-dock`,
		`.topic-summary-compose-toolbar`,
		`.topic-compose-btn`,
		`.topic-summary-save-btn`,
		`.topic-skeleton-block`,
		`.topic-list-skeleton`,
		`.topic-detail-skeleton`,
		`.topic-overview-stat-skeleton`,
		`.topic-overview-stat-icon-skeleton`,
		`.topic-overview-stat-title-skeleton`,
		`.topic-overview-stat-caption-skeleton`,
		`.topic-overview-stat-chevron-skeleton`,
		`.topic-search-skeleton`,
		`.topic-summary-composer-host`,
		`.topic-summary-modal-dock`,
		`.topic-summary-preview`,
		`.topic-emoji-picker`,
		`.topic-resource-content-list`,
		`.topic-resource-content-item`,
		`.topic-resource-item-title`,
		`.topic-resource-item-type`,
		`.topic-card-stats`,
		`.topic-card-stat`,
		`.topic-compact-list`,
		`.topic-compact-row`,
		`.topic-summary-list`,
		`.topic-summary-card`,
		`.topic-task-row`,
		`.topic-panel-toolbar`,
		`.topic-detail-sticky-controls`,
		`.topic-detail-tabs`,
		`.topic-detail-content`,
		`.topic-detail-search`,
		`.topic-detail-search-hidden`,
		`.topic-detail-sticky-controls-flat`,
		`.topic-detail-sticky-controls.is-stuck`,
		`.topic-detail-search-row`,
		`.topic-detail-search-btn`,
		`.topic-detail-body`,
		`.topic-detail-tab-overview`,
		`.topic-overview-panel`,
		`.topic-overview-title`,
		`.topic-overview-question`,
		`.topic-overview-stats`,
		`.topic-overview-stat`,
		`.topic-overview-stat-resources`,
		`.topic-overview-stat-icon`,
		`.topic-overview-stat-copy`,
		`.topic-overview-stat-title`,
		`.topic-overview-stat-chevron`,
		`.topic-overview-actions`,
		`.topic-overview-updated-time`,
		`.topic-overview-ai-btn`,
		`.topic-mobile-sidebar-trigger`,
		`.topic-mobile-topic-backdrop`,
		`.topic-fab`,
		`body.topic-modal-open .topic-fab`,
		`body.topic-mobile-topic-open .topic-fab`,
		`body.topic-mobile-topic-open .topic-rail`,
		`background: var(--color-bg-card);`,
		`.topic-expand.show`,
		`.topic-topic-edit-modal .bs-btn-danger`,
		`.asset-modal-size-md`,
		`.asset-modal-size-lg`,
		`.asset-modal-size-xl`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("topics css should contain %q", required)
		}
	}

	for _, required := range []string{
		`renderTopicOverviewStatCards`,
		`renderTopicOverviewStatSkeletonCards`,
		`topicOverviewStatConfig`,
		`topicOverviewResourcesCount`,
		`topicOverviewSummariesCount`,
		`topicOverviewTasksCount`,
		`data-topic-stat-tab="`,
		`topic-overview-stat-skeleton`,
		`topic-overview-stat-title-skeleton`,
		`topic-overview-stat-caption-skeleton`,
		`topicCommentDrafts: {}`,
		`topicCommentPageSize: 50`,
		`locateTopicCommentTarget`,
		`this.closeModal('topicMobileCommentsModal');`,
		`this.topicDetailFilters[config.tab] = '';`,
		`selector: '[data-resource-id="{id}"]'`,
		`selector: '[data-summary-id="{id}"]'`,
		`selector: '[data-task-id="{id}"]'`,
		`target.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });`,
		`data-resource-id="`,
		`captureTopicCommentDraft`,
		`restoreTopicCommentDraft`,
		`var topicChanged = Number(this.selectedId) !== Number(id);`,
		`if (topicChanged) this.setTopicCommentScope('current', { force: true });`,
		`if (this.topicCommentScope === nextScope && !options.force) return;`,
		`this.setTopicCommentScope('current', { force: true });`,
		`label.classList.add('hidden');`,
		`var canCompose = self.topicCommentScope === 'current';`,
		`class="topic-comment-identity"`,
		`upsertSavedTopicComment`,
		`this.upsertSavedTopicComment(response && response.data, editing);`,
		`Number(this.editingTopicCommentId) === Number(commentID)`,
		`renderTopicCommentLoadError`,
		`var loadMore = list.querySelector('.topic-comment-load-more');`,
		`error.setAttribute('role', 'status');`,
		`data-load-more-comments`,
		`data-retry-comments`,
		`topic.comment.delete_confirm`,
		`document.querySelectorAll('.asset-modal-backdrop.open')`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topics js should contain %q", required)
		}
	}
	for _, removed := range []string{
		`data-reply-comment`,
		`fa-solid fa-reply`,
		`replyingTopicCommentId`,
		`topic.comment.delete_root_confirm`,
		`topic.comment.delete_with_replies_confirm`,
	} {
		if strings.Contains(js, removed) {
			t.Fatalf("single-level topic comments should not contain %q", removed)
		}
	}
	assertCSSRuleContains(t, css, ".topic-topic-edit-modal .bs-btn-danger", "background: var(--color-danger);")
	assertCSSRuleContains(t, css, ".topic-topic-edit-modal .bs-btn-danger", "color: #fff;")
	assertCSSRuleContains(t, css, ".topic-workbench", "grid-template-columns: minmax(280px, 320px) minmax(0, 1fr) clamp(320px, 24vw, 420px);")
	assertCSSRuleContains(t, css, ".topics-body", "height: 100vh;")
	assertCSSRuleContains(t, css, ".topics-body", "overflow: hidden;")
	if strings.Contains(css, ".topics-body > footer {\n  display: none;") {
		t.Fatalf("topics footer should stay visible while the workbench columns scroll independently")
	}
	assertCSSRuleContains(t, css, ".topics-page", "display: flex;")
	assertCSSRuleContains(t, css, ".topics-page", "flex: 1 1 auto;")
	assertCSSRuleContains(t, css, ".topics-page", "flex-direction: column;")
	assertCSSRuleContains(t, css, ".topics-page", "height: auto;")
	assertCSSRuleContains(t, css, ".topics-page", "min-height: 0;")
	assertCSSRuleContains(t, css, ".topics-page", "box-sizing: border-box;")
	assertCSSRuleContains(t, css, ".topics-page", "overflow: hidden;")
	assertCSSRuleContains(t, css, ".topic-workbench", "flex: 1 1 auto;")
	assertCSSRuleContains(t, css, ".topic-workbench", "width: 100%;")
	assertCSSRuleContains(t, css, ".topic-workbench", "height: 100%;")
	assertCSSRuleContains(t, css, ".topic-workbench", "max-height: 100%;")
	assertCSSRuleContains(t, css, ".topic-workbench", "box-sizing: border-box;")
	assertCSSRuleContains(t, css, ".topic-workbench", "min-height: 0;")
	assertCSSRuleNotContains(t, css, ".topic-workbench", "min-height: 620px;")
	assertCSSRuleContains(t, css, ".topic-workbench", "gap: 16px;")
	assertCSSRuleContains(t, css, ".topic-workbench", "padding: 16px;")
	assertCSSRuleContains(t, css, ".topic-rail", "border-radius: var(--radius-lg);")
	assertCSSRuleContains(t, css, ".topic-rail", "max-height: 100%;")
	assertCSSRuleContains(t, css, ".topic-list", "overflow: auto;")
	assertCSSRuleContains(t, css, ".topic-detail", "border-radius: var(--radius-lg);")
	assertCSSRuleContains(t, css, ".topic-detail", "max-height: 100%;")
	assertCSSRuleContains(t, css, ".topic-detail", "background: var(--color-bg);")
	assertCSSRuleContains(t, css, ".topic-detail-content", "background: var(--color-bg);")
	assertCSSRuleContains(t, css, ".topic-detail-body", "overflow: auto;")
	assertCSSRuleContains(t, css, ".topic-context-panel", "border-radius: var(--radius-lg);")
	assertCSSRuleContains(t, css, ".topic-context-panel", "max-height: 100%;")
	assertCSSRuleContains(t, css, ".topic-context-panel", "overflow: auto;")
	assertCSSRuleContains(t, css, ".topic-context-panel", "padding: 0;")
	assertCSSRuleContains(t, css, ".topic-context-panel", "scrollbar-width: none;")
	assertCSSRuleContains(t, css, ".topic-context-panel::-webkit-scrollbar", "display: none;")
	assertCSSRuleContains(t, css, ".topic-pagination:empty", "display: none;")
	assertCSSRuleContains(t, css, ".topic-list", "padding: 0;")
	assertCSSRuleContains(t, css, ".topic-list", "background: var(--color-bg);")
	assertCSSRuleNotContains(t, css, ".topic-list", "padding: 4px 0;")
	assertCSSRuleContains(t, css, ".topic-rail", "background: var(--color-bg);")
	assertCSSRuleContains(t, css, ".topic-toolbar", "background: var(--color-bg);")
	assertCSSRuleContains(t, css, ".topic-toolbar", "padding: 0 0 14px;")
	assertCSSRuleContains(t, css, ".topic-toolbar", "border-bottom: 0;")
	assertCSSRuleContains(t, css, ".topic-toolbar", "--topic-rail-control-height: 34px;")
	assertCSSRuleContains(t, css, ".topic-toolbar .topic-search-row", "align-items: flex-start;")
	assertCSSRuleContains(t, css, ".topic-toolbar .topic-search-input", "height: var(--topic-rail-control-height);")
	assertCSSRuleContains(t, css, ".topic-toolbar .topic-search-input:focus,\n.topic-toolbar .topic-search-input:focus-visible", "box-shadow: inset 0 0 0 1px var(--color-focus), 0 0 0 1px var(--color-focus-ring);")
	assertCSSRuleContains(t, css, ".topic-search-row .topic-primary-btn", "height: var(--topic-rail-control-height);")
	assertCSSRuleContains(t, css, ".topic-list-entry", "margin-bottom: 2px;")
	assertCSSRuleContains(t, css, ".topic-card", "border: 0;")
	assertCSSRuleContains(t, css, ".topic-card", "border-left: 0;")
	assertCSSRuleContains(t, css, ".topic-card", "border-radius: 4px;")
	assertCSSRuleContains(t, css, ".topic-card:hover", "box-shadow: inset 3px 0 0 var(--color-primary);")
	assertCSSRuleContains(t, css, ".topic-card.selected", "box-shadow: inset 3px 0 0 var(--color-primary);")
	assertCSSRuleContains(t, css, ".topic-card-pin-badge", "border-radius: 999px;")
	assertCSSRuleContains(t, css, ".topic-card-pin-badge", "border: 1px solid var(--color-primary-border);")
	assertCSSRuleContains(t, css, ".topic-card-pin-badge", "gap: 4px;")
	assertCSSRuleContains(t, css, ".topic-card-pin-badge i", "font-size: 10px;")
	assertCSSRuleNotContains(t, css, ".topic-rail", "border-right:")
	assertCSSRuleNotContains(t, css, ".topic-context-panel", "border-left:")
	assertCSSRuleNotContains(t, css, ".topic-detail", "margin-left: 8px;")
	assertCSSRuleContains(t, css, ".topic-side-card", "padding: 12px;")
	assertCSSRuleContains(t, css, ".topic-side-card", "margin-bottom: 16px;")
	assertCSSRuleContains(t, css, ".topic-side-card", "border-radius: var(--radius-lg);")
	assertCSSRuleContains(t, css, ".topic-side-card", "border-color: var(--color-border-light);")
	assertCSSRuleContains(t, css, ".topic-comment-card", "display: flex;")
	assertCSSRuleContains(t, css, ".topic-comment-locate", "width: 24px;")
	assertCSSRuleContains(t, css, ".topic-comment-located", "animation: topic-comment-locate-pulse 1.4s ease;")
	assertCSSRuleContains(t, css, ".topic-comment-host", "width: 100%;")
	assertCSSRuleContains(t, css, ".topic-comment-host", "max-width: 100%;")
	assertCSSRuleContains(t, css, ".topic-comment-host", "min-width: 0;")
	assertCSSRuleContains(t, css, ".topic-comment-card", "width: 100%;")
	assertCSSRuleContains(t, css, ".topic-comment-card", "max-width: 100%;")
	assertCSSRuleContains(t, css, ".topic-comment-card", "min-width: 0;")
	assertCSSRuleContains(t, css, ".topic-comment-head > div:first-child", "min-width: 0;")
	assertCSSRuleContains(t, css, ".topic-comment-list", "overflow: auto;")
	assertCSSRuleContains(t, css, ".topic-comment-compose.is-scope-all", "display: none;")
	assertCSSRuleContains(t, css, ".topic-comment-load-more,\n.topic-comment-load-error", "justify-content: center;")
	assertCSSRuleContains(t, css, ".topic-comment-item", "border-bottom: 1px solid var(--color-border-light);")
	assertCSSRuleContains(t, css, ".topic-comment-toolbar", "flex-wrap: nowrap;")
	assertCSSRuleContains(t, css, ".topic-summary-dock-host", "display: none;")
	assertCSSRuleContains(t, css, ".topic-mobile-comments-trigger", "display: none;")
	assertCSSRuleContains(t, css, ".topic-mobile-comments-modal", "width: min(560px, 100%);")
	assertCSSRuleContains(t, css, "#topicMobileCommentsModal .asset-modal-body", "overflow: hidden;")
	assertCSSRuleContains(t, css, "#topicMobileCommentsModal .topic-mobile-comments-modal", "height: var(--bs-vvh, 100dvh);")
	assertCSSRuleContains(t, css, ".topic-summary-compose-head", "border-bottom: 1px solid var(--color-border-light);")
	assertCSSRuleContains(t, css, ".asset-modal-size-md", "width: min(640px, calc(100vw - 32px));")
	assertCSSRuleContains(t, css, ".asset-modal-size-lg", "width: min(840px, calc(100vw - 48px));")
	assertCSSRuleContains(t, css, ".asset-modal-size-xl", "width: min(920px, calc(100vw - 48px));")
	assertCSSRuleContains(t, css, ".asset-modal-size-md,\n.asset-modal-size-lg,\n.asset-modal-size-xl", "max-height: calc(100dvh - 48px);")
	assertCSSRuleContains(t, css, ".topic-topic-edit-modal", "width: min(840px, calc(100vw - 48px));")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-topic-edit-modal", "display: flex;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-topic-edit-modal", "flex-direction: column;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-topic-edit-modal", "height: min(720px, calc(100dvh - 48px));")
	assertCSSRuleContains(t, css, "#topicEditModal .asset-modal-body", "flex: 1 1 auto;")
	assertCSSRuleContains(t, css, "#topicEditModal .asset-modal-body", "min-height: 0;")
	assertCSSRuleContains(t, css, "#topicEditModal .asset-modal-body", "overflow: hidden;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-form-field:last-child", "flex: 1 1 auto;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-form-field:last-child", "min-height: 0;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-question-editor", "flex: 1 1 auto;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-question-editor", "min-height: 0;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-question-composer", "flex: 1 1 auto;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-question-composer", "min-height: 0;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-question-composer .cm-scroller", "overflow: auto;")
	assertCSSRuleContains(t, css, "#topicEditModal .topic-question-composer .md-composer-fallback", "overflow: auto;")
	assertCSSRuleContains(t, css, ".topics-page #topicEditModal .topic-topic-edit-modal", "width: 100%;")
	assertCSSRuleContains(t, css, ".topics-page #topicEditModal .topic-topic-edit-modal", "max-width: none;")
	assertCSSRuleContains(t, css, ".topics-page #topicEditModal .topic-topic-edit-modal", "height: calc(var(--bs-vvh, 100dvh) - 8px);")
	assertCSSRuleContains(t, css, ".topics-page #topicEditModal .asset-modal-foot", "grid-template-columns: repeat(3, minmax(0, 1fr));")
	assertCSSRuleContains(t, css, ".topics-page #topicEditModal .asset-modal-foot .bs-btn", "width: 100%;")
	assertCSSRuleContains(t, css, ".topics-page #topicEditModal .asset-modal-foot .bs-btn", "min-height: 44px;")
	cancelButtonIndex := strings.Index(template, `id="topicEditCancelBtn"`)
	deleteButtonIndex := strings.Index(template, `id="topicEditDeleteBtn"`)
	editSaveButtonIndex := strings.Index(template[deleteButtonIndex:], `type="submit" class="bs-btn bs-btn-primary"`)
	if cancelButtonIndex < 0 || deleteButtonIndex < 0 || editSaveButtonIndex < 0 || cancelButtonIndex > deleteButtonIndex {
		t.Fatalf("topic edit modal actions should be ordered cancel, delete, save")
	}
	assertCSSRuleContains(t, css, "#topicSummaryEditorModal .asset-modal", "display: flex;")
	assertCSSRuleContains(t, css, "#topicSummaryEditorModal .asset-modal", "width: min(1040px, calc(100vw - 48px));")
	assertCSSRuleContains(t, css, "#topicSummaryEditorModal .asset-modal", "height: min(560px, calc(100dvh - 48px));")
	assertCSSRuleContains(t, css, "#topicSummaryEditorModal .asset-modal-body", "display: flex;")
	assertCSSRuleContains(t, css, "#topicSummaryEditorModal .asset-modal-body", "overflow: hidden;")
	assertCSSRuleContains(t, css, ".topics-page #topicSummaryEditorModal .asset-modal", "width: 100%;")
	assertCSSRuleContains(t, css, ".topics-page #topicSummaryEditorModal .asset-modal", "max-width: none;")
	assertCSSRuleContains(t, css, ".topic-question-input", "min-height: 180px;")
	assertCSSRuleContains(t, css, ".topic-summary-compose-head .topic-compose-btn", "width: 18px;")
	assertCSSRuleContains(t, css, ".topic-summary-compose-head .topic-compose-btn", "height: 18px;")
	assertCSSRuleContains(t, css, ".topic-summary-compose-head .topic-compose-btn", "font-size: 12px;")
	assertCSSRuleContains(t, css, ".topic-empty-panel", "border: 1px dashed var(--color-border);")
	assertCSSRuleContains(t, css, ".topic-empty-panel", "background: var(--color-bg-hover);")
	assertCSSRuleContains(t, css, ".topic-empty-panel-action", "margin-top: 12px;")
	assertCSSRuleContains(t, css, ".topic-summary-compose-input", "min-height: 260px;")
	assertCSSRuleContains(t, css, ".topic-summary-compose-dock", "scrollbar-width: none;")
	assertCSSRuleContains(t, css, ".topic-summary-compose-dock::-webkit-scrollbar", "display: none;")
	assertCSSRuleContains(t, css, ".topic-summary-composer-host .cm-scroller", "scrollbar-width: none;")
	assertCSSRuleContains(t, css, ".topic-summary-composer-host .cm-scroller::-webkit-scrollbar", "display: none;")
	assertCSSRuleContains(t, css, ".topic-summary-composer-host .md-composer-fallback", "scrollbar-width: none;")
	assertCSSRuleContains(t, css, ".topic-summary-composer-host .md-composer-fallback::-webkit-scrollbar", "display: none;")
	assertCSSRuleContains(t, css, ".topic-summary-modal-dock", "margin-bottom: 0;")
	assertCSSRuleContains(t, css, ".topic-summary-modal-dock .topic-summary-composer-host .md-composer-fallback", "min-height: 440px;")
	assertCSSRuleContains(t, css, ".topic-summary-modal-dock .topic-summary-composer-host .cm-scroller", "max-height: none !important;")
	assertCSSRuleContains(t, css, ".topic-summary-modal-dock .topic-summary-composer-host .cm-scroller", "height: 100%;")
	assertCSSRuleContains(t, css, ".topic-summary-save-btn", "margin-left: 0;")
	assertCSSRuleNotContains(t, css, ".topic-summary-save-btn", "margin-left: auto;")
	assertCSSRuleContains(t, css, ".topic-summary-preview", "min-height: 260px;")
	assertCSSRuleContains(t, css, ".topic-summary-composer-host", "min-height: 260px;")
	assertCSSRuleContains(t, css, ".topic-summary-composer-host .md-composer-fallback", "min-height: 260px;")
	assertCSSRuleContains(t, css, ".topic-detail-body", "padding: 0;")
	assertCSSRuleContains(t, css, `.topic-tab-panel[data-topic-detail-panel="details"]`, "padding: 0;")
	assertCSSRuleContains(t, css, `.topic-tab-panel[data-topic-detail-panel="resources"]`, "padding: 0;")
	assertCSSRuleContains(t, css, `.topic-tab-panel[data-topic-detail-panel="summaries"]`, "padding: 0;")
	assertCSSRuleContains(t, css, `.topic-tab-panel[data-topic-detail-panel="tasks"]`, "padding: 0;")
	assertCSSRuleContains(t, css, ".topic-resource-content-list", "border: 0;")
	assertCSSRuleContains(t, css, ".topic-detail-body", "background: var(--color-bg);")
	assertCSSRuleContains(t, css, ".topic-compact-row", "margin-bottom: 2px;")
	assertCSSRuleContains(t, css, ".topic-compact-row", "padding: 8px 12px;")
	assertCSSRuleContains(t, css, ".topic-compact-row", "border-bottom: 1px solid var(--color-gray-100);")
	assertCSSRuleContains(t, css, ".topic-compact-row", "border-radius: 4px;")
	assertCSSRuleContains(t, css, ".topic-compact-row", "background: var(--color-bg-card);")
	assertCSSRuleNotContains(t, css, ".topic-resource-content-item", "border-bottom:")
	assertCSSRuleContains(t, css, ".topic-summary-list", "margin-top: 0;")
	assertCSSRuleContains(t, css, ".topic-summary-card", "margin-bottom: 2px;")
	assertCSSRuleContains(t, css, ".topic-summary-card", "border-bottom: 1px solid var(--color-gray-100);")
	assertCSSRuleContains(t, css, ".topic-summary-card", "border-radius: 4px;")
	assertCSSRuleContains(t, css, ".topic-overview-panel", "background: var(--color-bg-card);")
	assertCSSRuleContains(t, css, ".topic-overview-panel", "border: 1px solid var(--color-border-light);")
	assertCSSRuleContains(t, css, ".topic-overview-panel", "border-radius: var(--radius-lg);")
	assertCSSRuleContains(t, css, ".topic-overview-panel", "padding: 12px;")
	assertCSSRuleNotContains(t, css, ".topic-overview-question", "font-size:")
	assertCSSRuleNotContains(t, css, ".topic-overview-question", "line-height:")
	assertCSSRuleContains(t, css, ".topic-resource-content-item", "min-height: 48px;")
	assertCSSRuleContains(t, css, ".topic-actions-list", "gap: 0;")
	assertCSSRuleContains(t, css, ".topic-task-row", "margin-bottom: 2px;")
	assertCSSRuleContains(t, css, ".topic-task-row", "border-radius: 4px;")
	assertCSSRuleContains(t, css, ".topic-task-row", "background: var(--color-bg-card);")
	assertCSSRuleContains(t, css, ".topic-task-row .task-tools", "min-height: 30px;")
	for _, removed := range []string{
		".topic-summary-row {",
		".topic-action-row {",
		".topic-action-check {",
	} {
		if strings.Contains(css, removed) {
			t.Fatalf("topics css should not keep duplicated topic list style %q", removed)
		}
	}
	if strings.Contains(css, ".topic-detail-tabs.main-tabs {\n  display: inline-flex;") ||
		strings.Contains(css, ".topic-detail-tabs.main-tabs {\n  border:") ||
		strings.Contains(css, ".topic-detail-tab.main-tab {\n  padding:") ||
		strings.Contains(css, ".topic-detail-tab.main-tab {\n  display: inline-flex;") {
		t.Fatalf("topic tabs should reuse notes page main-tabs/main-tab visual styles instead of duplicating them")
	}
	assertCSSRuleContains(t, css, ".topic-detail-tab.main-tab.topic-detail-tab-overview", "display: inline-flex;")
	assertCSSRuleNotContains(t, css, ".topic-detail-tab.main-tab.topic-detail-tab-overview", "display: none;")
	assertCSSRuleContains(t, css, ".topic-detail-tabs-row", "display: flex;")
	assertCSSRuleContains(t, css, ".topic-detail-tabs-row", "justify-content: space-between;")
	assertCSSRuleContains(t, css, ".topic-detail-search-hidden", "display: none;")
	assertCSSRuleContains(t, css, ".topic-detail-sticky-controls-flat", "border-bottom-color: transparent;")
	assertCSSRuleContains(t, css, ".topic-overview-stats", "grid-template-columns: repeat(3, minmax(0, 1fr));")
	assertCSSRuleContains(t, css, ".topic-overview-stats", "gap: 14px;")
	assertCSSRuleContains(t, css, ".topic-overview-stat", "display: flex;")
	assertCSSRuleContains(t, css, ".topic-overview-stat", "min-height: 64px;")
	assertCSSRuleContains(t, css, ".topic-overview-stat", "border: 1px solid var(--color-border-light);")
	assertCSSRuleContains(t, css, ".topic-overview-stat", "background: var(--color-bg);")
	assertCSSRuleNotContains(t, css, ".topic-overview-stat", "box-shadow:")
	assertCSSRuleNotContains(t, css, ".topic-overview-stat-resources", "border-color: var(--color-primary);")
	assertCSSRuleContains(t, css, ".topic-overview-stat:hover,\n.topic-overview-stat:focus-visible", "border-color: var(--color-primary);")
	assertCSSRuleContains(t, css, ".topic-overview-stat-icon", "width: 36px;")
	assertCSSRuleContains(t, css, ".topic-overview-stat-icon", "height: 36px;")
	assertCSSRuleContains(t, css, ".topic-overview-stat-title", "display: inline-flex;")
	assertCSSRuleContains(t, css, ".topic-overview-stat-chevron", "margin-left: auto;")
	if strings.Contains(template, "topic-overview-stat-watermark") ||
		strings.Contains(css, ".topic-overview-stat-watermark") {
		t.Fatalf("topic overview stat cards should not keep the large watermark visual")
	}
	assertCSSRuleNotContains(t, css, ".topic-overview-title", "-webkit-line-clamp:")
	assertCSSRuleNotContains(t, css, ".topic-overview-question", "-webkit-line-clamp:")
	assertCSSRuleContains(t, css, ".topic-card-actions", "align-items: center;")
	assertCSSRuleContains(t, css, ".topic-card-action-separator", "width: 1px;")
	assertCSSRuleContains(t, css, ".topic-card-action-separator", "height: 14px;")
	assertCSSRuleContains(t, css, ".topic-card-action-separator", "background: var(--color-border);")
	assertCSSRuleContains(t, css, ".topic-overview-actions", "display: flex;")
	assertCSSRuleContains(t, css, ".topic-overview-updated-time", "margin-left: auto;")
	assertCSSRuleContains(t, css, ".topic-overview-updated-time", "display: inline-flex;")
	assertCSSRuleContains(t, css, ".topic-overview-updated-time i", "font-size: 12px;")
	assertCSSRuleContains(t, css, ".topic-overview-ai-btn", "display: inline-flex;")
	assertCSSRuleContains(t, css, ".topic-overview-ai-btn", "background: transparent;")
	assertCSSRuleContains(t, css, ".topic-overview-ai-btn", "color: #7c3aed;")
	assertCSSRuleNotContains(t, css, ".topic-overview-ai-btn", "display: none;")
	assertCSSRuleNotContains(t, css, ".topic-overview-ai-btn", "background: var(--color-primary);")
	if strings.Contains(template, `id="topicAIAssistantBtn"`) ||
		strings.Contains(js, `topicAIAssistantBtn`) ||
		strings.Contains(css, ".topic-ai-assistant-btn") {
		t.Fatalf("desktop topic AI assistant entry should live beside the overview pin button, not in the tab toolbar")
	}
	if strings.Contains(css, ".topic-overview-meta {") {
		t.Fatalf("topic overview should not keep a separate created/updated meta block")
	}
	assertCSSRuleContains(t, css, ".topic-detail-create-btn", "width: 44px;")
	assertCSSRuleContains(t, css, ".topic-detail-create-btn", "height: 38px;")
	assertCSSRuleContains(t, css, ".topic-detail-create-btn", "padding: 0;")
	assertCSSRuleContains(t, css, ".topic-detail-head", "display: none;")
	if strings.Contains(css, "  .topic-detail-head {\n    display: none;") {
		t.Fatalf("topic detail title/question header should be hidden globally, not only in desktop media")
	}
	if !strings.Contains(css, "  .topic-detail {\n    display: flex;\n    margin-left: 0;\n    margin-top: 0;") {
		t.Fatalf("mobile topic detail should become the primary surface instead of stacking below an always-visible list")
	}
	if !strings.Contains(css, "    overflow: visible;") ||
		!strings.Contains(css, "  .topic-detail-content {\n    overflow: visible;") ||
		!strings.Contains(css, "  .topic-detail-body {\n    overflow: visible;") {
		t.Fatalf("mobile topic detail should not clip sticky tab and search rows during page scroll")
	}
	if !strings.Contains(css, "    scroll-margin-top: 56px;") {
		t.Fatalf("mobile topic detail should keep a fixed-header offset when auto-scrolled into view")
	}
	if !strings.Contains(css, "  .topic-detail-sticky-controls {\n    position: sticky;\n    top: 40px;") ||
		!strings.Contains(css, "    width: 100%;") ||
		!strings.Contains(css, "    padding: 8px 0 10px;") ||
		!strings.Contains(css, "    display: flex;") ||
		!strings.Contains(css, "    flex-direction: column;") ||
		!strings.Contains(css, "    gap: 10px;") {
		t.Fatalf("mobile topic controls should stick together below the system header")
	}
	if strings.Contains(css, "  .topic-detail-sticky-controls {\n    position: sticky;\n    top: 40px;\n    z-index: 6;\n    width: 100%;\n    margin: 0;\n    padding: 8px 0 10px;\n    background: var(--color-bg);") {
		t.Fatalf("mobile topic controls should stay transparent before they stick")
	}
	assertCSSRuleContains(t, css, ".topic-detail-sticky-controls", "border-bottom: 0;")
	assertCSSRuleContains(t, css, ".topic-detail-sticky-controls.is-stuck", "background: var(--color-bg);")
	assertCSSRuleContains(t, css, ".topic-detail-sticky-controls.is-stuck", "border-bottom: 0;")
	if !strings.Contains(css, "  .topic-detail-sticky-controls.is-stuck {\n    background: var(--color-bg);\n  }") {
		t.Fatalf("mobile sticky controls should restate the stuck background after the mobile transparent base rule")
	}
	if !strings.Contains(css, "[data-science-background=\"on\"] .topic-detail-sticky-controls.is-stuck") ||
		!strings.Contains(css, "background: var(--color-bg) !important;") {
		t.Fatalf("stuck topic controls should override science-background transparency")
	}
	if !strings.Contains(js, "updateTopicStickyControls: function()") ||
		!strings.Contains(js, "topic-detail-sticky-controls") ||
		!strings.Contains(js, "is-stuck") ||
		!strings.Contains(js, "window.addEventListener('scroll', this.updateTopicStickyControls)") ||
		!strings.Contains(js, "window.addEventListener('resize', this.updateTopicStickyControls)") {
		t.Fatalf("topic controls should only get a background after sticky scroll state is detected")
	}
	if !strings.Contains(css, "  .topic-detail-sticky-controls {\n    top: 48px;") {
		t.Fatalf("small mobile topic controls should account for the taller mobile system header")
	}
	if strings.Contains(css, "  .topic-detail-tabs-row {\n    position: sticky;") ||
		strings.Contains(css, "  .topic-detail-search {\n    position: sticky;") {
		t.Fatalf("mobile topic tab and search rows should not be independent sticky layers")
	}
	if !strings.Contains(css, "  .topic-detail-tabs-row {\n    width: 100%;\n    margin: 0;\n    padding: 0;") {
		t.Fatalf("mobile topic tab row should match the notes page header left edge and tab/search rhythm")
	}
	if !strings.Contains(css, "  .topic-detail-search {\n    margin: 0;\n    padding: 0;") {
		t.Fatalf("mobile topic search row should rely on the sticky parent gap instead of transparent margins")
	}
	if strings.Contains(css, "  .topic-detail-body {\n    padding-left: 12px;") ||
		strings.Contains(css, "  .topic-detail-body {\n    padding-right: 12px;") {
		t.Fatalf("mobile topic detail body should not reintroduce horizontal padding")
	}
	assertCSSRuleContains(t, css, "#topicDetailSearchInput", "flex: 1 1 auto;")
	assertCSSRuleContains(t, css, "#topicDetailSearchInput", "min-width: 0;")
	if !strings.Contains(css, "  .topic-mobile-sidebar-trigger,\n  .topic-mobile-comments-trigger {\n    display: flex;\n    flex: 0 0 auto;\n    width: 32px;\n    height: 32px;") {
		t.Fatalf("mobile topic toolbar triggers should match compact 32px actions")
	}
	if !strings.Contains(css, "  #topicMobileCommentsModal .topic-comment-actions button,\n  #topicMobileCommentsModal .topic-comment-edit-state button,\n  #topicMobileCommentsModal .topic-comment-toolbar .topic-compose-btn") ||
		!strings.Contains(css, "    min-width: 40px;\n    min-height: 40px;") {
		t.Fatalf("mobile topic comment controls should expose reliable touch targets")
	}
	if !strings.Contains(css, "@media (max-width: 360px)") ||
		!strings.Contains(css, "  .topic-detail-tabs .main-tab {\n    min-width: 0;\n    padding: 5px 6px;") {
		t.Fatalf("narrow mobile topic tabs should compact without widening the page")
	}
	if strings.Contains(js, "var query = '&page_size=200'") ||
		strings.Contains(js, "while (items.length < total)") {
		t.Fatalf("topic comments should use incremental pagination instead of eagerly loading every page")
	}
	if !strings.Contains(css, "  .topic-mobile-rail-close {\n    display: inline-flex;") {
		t.Fatalf("mobile topic drawer should expose a close button in the drawer toolbar")
	}
	if !strings.Contains(css, "  .topic-card-tool-btn {\n    width: 40px;\n    height: 40px;") {
		t.Fatalf("mobile topic icon actions should have a reliable touch target")
	}
	if !strings.Contains(css, "  .topic-task-row {\n    display: flex;\n    flex-direction: column;") {
		t.Fatalf("mobile topic task rows should follow the notes task vertical action layout so action buttons are not overlaid by content")
	}
	if strings.Contains(css, "  .topic-task-row {\n    display: grid;\n    grid-template-columns: 40px minmax(0, 1fr);") {
		t.Fatalf("mobile topic task rows should not use the old narrow two-column grid after adding edit and delete actions")
	}
	if !strings.Contains(css, "  .topic-task-row .task-check-btn {\n    width: 28px;\n    height: 28px;\n    flex: 0 0 28px;") {
		t.Fatalf("mobile topic task checkbox should stay visually compact")
	}
	if !strings.Contains(css, "  .topic-task-row.done .task-check-btn {\n    border-color: var(--color-success);\n    background: var(--color-success);\n    color: #fff;") {
		t.Fatalf("mobile topic completed task checkbox should have a distinct completed state")
	}
	if !strings.Contains(css, "  .topic-summary-modal-dock .topic-summary-preview,\n  .topic-summary-modal-dock .topic-summary-composer-host .md-composer-fallback,\n  .topic-summary-modal-dock .topic-summary-composer-host .md-composer-cm,\n  .topic-summary-modal-dock .topic-summary-composer-host .cm-editor {\n    min-height: 320px;") {
		t.Fatalf("mobile topic summary modal should avoid an oversized empty editor area")
	}
	if strings.Contains(css, "  .topic-detail-search .search-input {\n    padding:") ||
		strings.Contains(css, ".topic-detail-search .search-input {\n  flex:") {
		t.Fatalf("topic search input sizing should come from notes.css tab-search styles")
	}
	if strings.Contains(css, ".topic-modal {") ||
		strings.Contains(css, ".topic-modal-panel") ||
		strings.Contains(css, ".topic-modal-head") ||
		strings.Contains(css, ".topic-modal-actions") ||
		strings.Contains(css, ".topic-modal-backdrop") ||
		strings.Contains(css, "topicPopoverSlideDown") ||
		strings.Contains(css, "--topic-visual-height") {
		t.Fatalf("topic modal shell CSS should be removed in favor of the shared bs-dialog styles")
	}
	if !strings.Contains(css, "  .topic-toolbar {\n    position: sticky;\n    top: 0;") {
		t.Fatalf("mobile topic search toolbar should stick to the top of the topic sheet")
	}
	if !strings.Contains(css, "  .topic-mobile-sidebar-trigger,\n  .topic-mobile-comments-trigger {\n    display: flex;\n    flex: 0 0 auto;\n    width: 32px;\n    height: 32px;") {
		t.Fatalf("mobile topic toolbar triggers should sit inline at the right of the tab row")
	}
	if !strings.Contains(css, "  .topic-rail {\n    position: fixed;\n    top: 0;\n    bottom: 0;\n    left: 0;\n    right: auto;\n    width: min(88vw, 360px);\n    height: 100dvh;") {
		t.Fatalf("mobile topic rail should be a full-height left drawer")
	}
	if !strings.Contains(css, "  [data-science-background=\"on\"] body.topic-mobile-topic-open .topic-rail,\n  [data-science-background=\"on\"] body.topic-mobile-topic-open .topic-list {\n    background: var(--color-bg-card) !important;") {
		t.Fatalf("mobile topic drawer should remain opaque when the science background is enabled")
	}
	if !strings.Contains(css, "  .topics-body {\n    height: auto;\n    overflow: visible;") ||
		!strings.Contains(css, "  .topics-page {\n    flex: 1 1 auto;\n    display: block;\n    height: auto;\n    max-height: none;\n    min-height: calc(100vh - 40px);\n    overflow: visible;") {
		t.Fatalf("mobile topic page should keep normal page scrolling while desktop suppresses outer overflow")
	}
	if !strings.Contains(css, "    transform: translateX(calc(-100% - 12px));") ||
		!strings.Contains(css, "  body.topic-mobile-topic-open .topic-rail {\n    opacity: 1;\n    pointer-events: auto;\n    transform: translateX(0);") {
		t.Fatalf("mobile topic drawer should slide in from the left")
	}
	if !strings.Contains(css, "  body.topic-mobile-topic-open .topic-mobile-sidebar-trigger") {
		t.Fatalf("mobile topic sidebar trigger should hide while the drawer is open")
	}
	if !strings.Contains(css, "  .topic-toolbar .topic-search-input {\n    min-height: 0;\n    height: 34px;\n    padding: 6px 10px;\n    font-size: 12px;") {
		t.Fatalf("mobile topic search input should match the compact notes page search height")
	}
	if !strings.Contains(css, "  .topic-toolbar #topicCreateBtn {\n    display: none;") {
		t.Fatalf("mobile topic sheet should hide the rail create button so FAB is the single new-entry control")
	}
	if !strings.Contains(css, "  .topic-list-entry {\n    flex: none;\n    border-bottom: 0;") ||
		!strings.Contains(css, "  .topic-list-entry .topic-card {\n    border: 0;\n    border-left: 0;") {
		t.Fatalf("mobile topic sheet should render topics as full-width selectable cards")
	}
	if !strings.Contains(css, "  .topic-list {\n    display: block;\n    flex: 1 1 auto;") {
		t.Fatalf("mobile topic sheet list should be a scrollable vertical selector below the pinned search")
	}
	if !strings.Contains(css, "  .topic-list {\n    display: block;\n    flex: 1 1 auto;") ||
		!strings.Contains(css, "    min-height: 0;") ||
		!strings.Contains(css, "    max-height: none;") ||
		!strings.Contains(css, "    padding: 0;") ||
		!strings.Contains(css, "    scrollbar-width: none;") {
		t.Fatalf("mobile topic list should remove extra padding so rows align with the sheet")
	}
	if !strings.Contains(css, "  .topic-list-entry + .topic-list-entry {\n    margin-top: 0;") ||
		!strings.Contains(css, "  .topic-list-entry .topic-card {\n    border: 0;\n    border-left: 0;\n    border-radius: 4px;") {
		t.Fatalf("mobile topic drawer rows should match the topic detail card list rhythm")
	}
	if strings.Contains(css, "  .topic-list-entry .topic-card {\n    border: 0;\n    border-left: 0;\n    border-radius: 4px;\n    padding: 12px;") {
		t.Fatalf("mobile topic drawer cards should keep the same padding as desktop topic cards")
	}
	if !strings.Contains(css, "  .topic-list-entry .topic-card-tool-btn {\n    width: 22px;\n    height: 22px;\n    min-width: 22px;") {
		t.Fatalf("mobile topic drawer icon buttons should keep the same size as desktop topic cards")
	}
	if strings.Contains(css, "  .topic-list-entry .topic-card-desc {\n    display: none;") {
		t.Fatalf("mobile topic sheet rows should show the topic question instead of hiding the description")
	}
	if !strings.Contains(css, "  .topic-list-entry .topic-card-desc {\n    display: -webkit-box;") {
		t.Fatalf("mobile topic sheet rows should keep the topic question visible with two-line clamping")
	}
	if strings.Contains(css, "  .topic-detail-tabs-row {\n    display: grid;") ||
		strings.Contains(css, "  .topic-detail-tabs.main-tabs {\n    display: grid;") ||
		strings.Contains(css, "  .topic-detail-tabs.main-tabs {\n    grid-template-columns:") ||
		strings.Contains(css, "  .topic-detail-tabs.main-tabs {\n    flex: 0 1 auto;\n    max-width: calc(") {
		t.Fatalf("mobile topic tabs should reuse the notes page intrinsic segmented control sizing")
	}
	if strings.Contains(css, "  .topic-detail-tab.main-tab {\n    padding:") ||
		strings.Contains(css, "  .topic-detail-tab.main-tab {\n    font-size:") ||
		strings.Contains(css, "  .topic-detail-tab.main-tab i {\n    font-size:") ||
		strings.Contains(css, "  .topic-detail-tab.main-tab {\n    gap:") {
		t.Fatalf("mobile topic tab button sizing should come from notes.css main-tab")
	}
	if !strings.Contains(css, "  .topic-detail-search-btn {\n    min-height: 40px;\n    width: 40px;\n    flex: 0 0 40px;\n    height: 40px;") {
		t.Fatalf("mobile topic search button should keep a reliable touch target")
	}
	if !strings.Contains(css, "  .topic-detail-create-btn {\n    display: none;") {
		t.Fatalf("mobile topic detail add button should be hidden because the contextual FAB handles create actions")
	}
	if !strings.Contains(css, "  .topic-detail-tab.main-tab.topic-detail-tab-overview {\n    display: inline-flex;") {
		t.Fatalf("mobile topic tabs should keep the details tab visible")
	}
	if !strings.Contains(css, "  .topic-read-title-line h1 {\n    display: -webkit-box;\n    -webkit-line-clamp: 2;") {
		t.Fatalf("mobile topic detail title should allow two lines before truncation")
	}
	for _, required := range []string{
		`bindIfPresent: function(id, eventName, handler)`,
		`topicDetailFilters`,
		`openEditModal: function()`,
		`switchDetailTab: function(tabName)`,
		`syncTopicDetailSearch: function()`,
		`this.activeDetailTab = 'details';`,
		`initTopicQuestionComposer: function()`,
		`onPasteFile: function(file) { self.uploadTopicSummaryImageFile(file); }`,
		`getTopicQuestionValue: function()`,
		`setTopicQuestionValue: function(value)`,
		`toggleTopicQuestionPreview: function()`,
		`uploadTopicQuestionImageFile: function(file)`,
		`insertTopicSummaryMarkdownImage: function(filename, url)`,
		`uploadTopicSummaryImageFile: function(file)`,
		`renderTopicOverview: function()`,
		`bindOverviewStatTabs: function()`,
		`data-topic-stat-tab`,
		`question.innerHTML = this.renderMarkdown(topic.question || t('topic.no_question', 'No core question yet'));`,
		`topicOverviewTitle`,
		`topicOverviewQuestion`,
		`topicOverviewResourcesCount`,
		`topicOverviewSummariesCount`,
		`topicOverviewTasksCount`,
		`topicOverviewUpdatedAt`,
		`topicOverviewEditBtn`,
		`topicOverviewPinBtn`,
		`topic-detail-search-hidden`,
		`topic-detail-sticky-controls-flat`,
		`searchActiveDetailTab: function()`,
		`renderActiveDetailTab: function()`,
		`matchesTopicDetailSearch: function(values, keyword)`,
		`topicDetailSearchInput`,
		`topicDetailSearchBtn`,
		`renderTopicStats: function()`,
		`renderContextPanel: function()`,
		`updateTopicDetailCreateButton: function()`,
		`topicDetailCreateBtn`,
		`openMobileCommentsModal: function(skipLoad)`,
		`topicMobileCommentsBtn`,
		`topicMobileCommentsModal`,
		`loadTopicComments: async function(options)`,
		`var loadToken = ++this.topicCommentLoadToken;`,
		`if (loadToken !== this.topicCommentLoadToken || topicID !== this.selectedId) return;`,
		`topicDetailLoadToken`,
		`var loadToken = ++this.topicDetailLoadToken;`,
		`Number(id) !== Number(this.selectedId)`,
		`var requestedPage = append ? this.topicCommentPage + 1 : 1;`,
		`var items = append ? (this.topicComments || []).concat(rows) : rows;`,
		`this.openMobileCommentsModal(true);`,
		`renderTopicComments: function()`,
		`saveTopicComment: async function()`,
		`var topicID = this.selectedId;`,
		`var draftUnchanged = this.topicCommentValue() === content`,
		`'/comments/' + commentID`,
		`topicCommentList`,
		`topicCommentMobileHost`,
		`openNewSummaryEditor: function()`,
		`handleDetailTabKeydown: function(e, tab)`,
		`BookStarkScrollLock.lock('topic-modal')`,
		`BookStarkScrollLock.lock('topic-mobile-rail')`,
		`topic-task-main`,
		`renderTopicListSkeleton: function()`,
		`renderTopicDetailSkeleton: function()`,
		`renderTopicSearchSkeleton: function()`,
		`this.renderTopicListSkeleton();`,
		`this.renderTopicDetailSkeleton();`,
		`this.renderTopicSearchSkeleton();`,
		`countText(value)`,
		`renderMarkdown: function(value)`,
		`topic-card-pin-badge`,
		`<i class="fa-solid fa-thumbtack"`,
		`topic-card-actions`,
		`topic-card-action-separator`,
		`data-topic-edit`,
		`data-topic-pin`,
		`'<div class="topic-card-meta"><span class="topic-card-actions">'`,
		`formatDateOnly(item.modify_time)`,
		`toggleTopicPin: async function(topicId, nextPinned)`,
		`topic-card-stats`,
		`fa-layer-group`,
		`fa-file-lines`,
		`fa-list-check`,
		`topic-resource-content-item`,
		`topic-compact-row`,
		`note-card topic-summary-card`,
		`note-footer`,
		`note-actions`,
		`task-row topic-task-row`,
		`task-content note-content`,
		`task-pill`,
		`data-edit-summary`,
		`openSummaryEditor: function(summary)`,
		`topicSummaryEditorMode`,
		`editingSummaryId`,
		`marked.parse`,
		`topic-resource-item-title`,
		`topic-resource-item-type`,
		`initSummaryComposer: function()`,
		`openTopicSummaryAI: function()`,
		`toggleTopicSummaryPreview: function()`,
		`updateTopicSummaryPreview: function(force)`,
		`toggleTopicSummaryEmojiPicker: function()`,
		`saveInlineSummary: async function()`,
		`updateSummarySubmitLabel: function()`,
		`t('topic.save', 'Save')`,
		`topicSummaryComposer`,
		`topicSummaryEmojiButton`,
		`topicSummaryImageButton`,
		`topicSummaryFileInput`,
		`topicSummaryPreviewButton`,
		`topicSummaryAIButton`,
		`openTopicSummaryEditorModal: function()`,
		`restoreTopicSummaryEditor: function()`,
		`topicSummaryEditorExpanded`,
		`topicSummaryModalDock`,
		`topicEditDeleteBtn`,
		`renderMobileExpansion: function()`,
		`data-mobile-topic-tab`,
		`renderTopicEmptyPanel: function(kind, title, body, actionText, actionName)`,
		`bindTopicEmptyActions: function()`,
		`data-topic-empty-action`,
		`clear-search`,
		`topicDetailSearchTimer`,
		`setOptionalText`,
		`self.openNewSummaryEditor();`,
		`self.selectTopic(parseInt(card.getAttribute('data-topic-id'), 10));`,
		`openMobileTopicSheet: function()`,
		`closeMobileTopicSheet: function(restoreFocus)`,
		`updateTopicFab: function()`,
		`handleTopicFabAction: function()`,
		`topicFabBtn`,
		`case 'resources':`,
		`case 'summaries':`,
		`case 'tasks':`,
		`this.openCreateModal();`,
		`this.openItemModal();`,
		`this.openNewSummaryEditor();`,
		`this.openTaskModal();`,
		`body.classList.add('topic-modal-open')`,
		`modal.classList.add('open')`,
		`document.querySelector('.asset-modal-backdrop.open')`,
		`topic-mobile-topic-open`,
		`topicMobileSidebarBtn`,
		`topicMobileRailCloseBtn`,
		`topicMobileTopicBackdrop`,
		`t('topic.detail.search.resources.placeholder'`,
		`t('topic.resource.empty.title'`,
		`t('topic.task.status.done'`,
		`t('topic.ai.assistant.title'`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topics js should contain %q", required)
		}
	}
	if strings.Contains(template, `id="topicOverviewCreatedAt"`) ||
		strings.Contains(template, `class="topic-overview-meta"`) ||
		strings.Contains(js, `topicOverviewCreatedAt`) {
		t.Fatalf("topic overview should show only the updated time in the actions row")
	}
	if strings.Contains(js, "self.selectTopic(parseInt(card.getAttribute('data-topic-id'), 10));\n          self.closeMobileTopicSheet();") {
		t.Fatalf("mobile topic drawer should stay open after selecting a topic from the drawer")
	}
	for _, forbidden := range []string{
		`topicStatusFilters`,
		`topicStatusSelect`,
		`topicReadStatus`,
		`topicMetaLine`,
		`topicItemsStat`,
		`topicLabelsRead`,
		`topicTagInput`,
		`newTopicTagInput`,
		`topic.labels.`,
		`labelPills`,
		`detail.labels`,
		`topicSummaryInput`,
		`topicConclusionInput`,
		`id="topicEditPanel"`,
		`id="topicTitleInput"`,
		`id="topicQuestionInput"`,
		`id="topicSaveBtn"`,
		`id="topicCancelEditBtn"`,
		`id="topicResourcesTabCount">0</span>`,
		`id="topicSummariesTabCount">0</span>`,
		`id="topicTasksTabCount">0</span>`,
		`id="topicDeleteBtn"`,
		`byId('topicEditForm').addEventListener`,
		`byId('topicEditDeleteBtn').addEventListener`,
		`setEditing: function(on)`,
		`topic-mobile-edit-open`,
		`topic.conclusion.`,
		`topicStatResources`,
		`topicStatSummaries`,
		`topicStatTasks`,
		`topicStatUpdated`,
		`<h2>资料类型</h2>`,
		`topic-meter-row`,
		`topic-meter-track`,
		`topicTypeMeters`,
		`renderTypeMeters`,
		`topic-stat-grid`,
		`topic-resource-type-card`,
		`topicGenerateSummaryBtn`,
		`id="topicSummaryDraftType"`,
		`<h2>AI 小结</h2>`,
		`id="topicPinBtn"`,
		`id="topicOverviewPinnedBadge"`,
		`id="topicEditBtn"`,
		`id="topicAddItemHeadBtn"`,
		`id="topicItemsCount"`,
		`id="topicSummariesCount"`,
		`id="topicActionsCount"`,
		`id="topicAddSummaryBtn"`,
		`id="topicAddTaskBtn"`,
		`id="topicSortBtn"`,
		`笔记、文档、文章、书签和待办都可以作为资料挂入专题`,
		`手写和 AI 小结共用列表，按顺序沉淀结论`,
		`复用系统待办模型，专题只是上下文归属`,
		`<h2>资料</h2>`,
		`<h2>待办</h2>`,
		`resourceSortDesc`,
		`toggleResourceSort`,
		`<span class="topic-summary-badge manual">手写</span>`,
		`multiline(item.content, '')`,
		`fa-quote-left`,
		`openSummaryModal`,
		`saveSummary: async function()`,
		`id="topicSummaryModal"`,
		`id="topicSummaryForm"`,
		`id="topicSummaryId"`,
		`id="topicSummaryContent"`,
		`id="topicSummaryType"`,
		`#topicSidePinBtn {`,
		`#topicSidePinBtn.is-pinned`,
		`pinBtn.classList.toggle('is-pinned'`,
		`data-select-summary`,
		`loadSummaryIntoComposer: function(summary)`,
		`topic-summary-row selected`,
		`topic-icon-btn topic-danger" data-delete-summary`,
		`iconClass = 'fa-solid fa-paperclip';`,
		`iconClass = 'fa-solid fa-file-pen';`,
		`topicMobileSwitchBtn`,
		`topicActivityNewSummaryBtn`,
		`topic.activity.new_summary`,
		`topic-compose-submit`,
		`topic.summary.new`,
		`topic-loading`,
		`t('topic.loading'`,
		`t('topic.searching'`,
		`btn.querySelector('span')`,
		`span.textContent = label`,
	} {
		if strings.Contains(template, forbidden) || strings.Contains(css, forbidden) || strings.Contains(js, forbidden) {
			t.Fatalf("topics page should not contain removed status/stat UI marker %q", forbidden)
		}
	}
	if strings.Contains(js, "self.activeDetailTab === 'details') self.switchDetailTab('resources')") {
		t.Fatalf("topic detail should keep the details tab selected on desktop resize")
	}
	if strings.Contains(template, `<textarea class="dialog-input topic-question-input" id="editTopicQuestion"`) {
		t.Fatalf("topic edit question should use the markdown composer instead of a plain textarea")
	}
}

func TestTopicSummaryAIUsesCompactPopoverAndEditableLimitedContext(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/topics.js")
	if err != nil {
		t.Fatalf("read topics js: %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/topics.css")
	if err != nil {
		t.Fatalf("read topics css: %v", err)
	}
	js := string(jsBytes)
	css := string(cssBytes)

	for _, required := range []string{
		`topicSummaryAIContext: function()`,
		`【标题】`,
		`【描述】`,
		`【已有小结】`,
		`ensureTopicSummaryAI: function()`,
		`note-ai-popover topic-summary-ai-popover`,
		`topic-summary-ai-context-btn`,
		`topic.ai.context_chars`,
		`topic.ai.summary.action.polish`,
		`openTopicSummaryAIContextEditor: function()`,
		`topic-summary-ai-context-modal`,
		`makeTopicSummaryAIDraggable: function(popover)`,
		`cleanupDrag`,
		`runTopicSummaryAI: function()`,
		`AIHelper.complete`,
		`scene: this.topicSummaryAIActiveScene || 'topic-summary'`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("topics summary AI missing %q", required)
		}
	}

	contextStart := strings.Index(js, `topicSummaryAIContext: function()`)
	contextEnd := strings.Index(js[contextStart:], `getTopicSummaryAIContextFromEditor: function()`)
	if contextStart < 0 || contextEnd < 0 {
		t.Fatalf("cannot locate topicSummaryAIContext block")
	}
	contextBlock := js[contextStart : contextStart+contextEnd]
	for _, forbidden := range []string{`detail.resources`, `detail.tasks`, `【资料】`, `【待办】`, `getInlineSummaryValue`} {
		if strings.Contains(contextBlock, forbidden) {
			t.Fatalf("topic summary AI context should not include %q", forbidden)
		}
	}
	if strings.Contains(js, `AIComposeDialog.open({
        title: t('topic.ai.summary.title'`) {
		t.Fatalf("topic summary AI should use compact note-style popover instead of AIComposeDialog")
	}
	for _, forbidden := range []string{
		`'<em>AI</em>'`,
		`'<span class="vis-badge">AI</span>'`,
	} {
		if strings.Contains(js, forbidden) {
			t.Fatalf("topic summaries should not render AI badge %q", forbidden)
		}
	}
	for _, required := range []string{
		`.topic-summary-ai-popover .topic-summary-ai-context-btn`,
		`.topic-summary-ai-context-textarea`,
		`.topic-summary-ai-context-modal.open`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("topic summary AI CSS missing %q", required)
		}
	}
}

func TestTopicPageEnglishLocalizationKeys(t *testing.T) {
	enBytes, err := os.ReadFile("i18n/en.go")
	if err != nil {
		t.Fatalf("read english translations: %v", err)
	}
	zhBytes, err := os.ReadFile("i18n/zh.go")
	if err != nil {
		t.Fatalf("read chinese translations: %v", err)
	}
	en := string(enBytes)
	zh := string(zhBytes)
	for _, required := range []string{
		`"topic.detail.tab.details":`,
		`"topic.detail.search.resources.placeholder":`,
		`"topic.resource.empty.title":`,
		`"topic.task.status.done":`,
		`"topic.overview.stat.resources.caption":`,
		`"topic.overview.stat.summaries.caption":`,
		`"topic.overview.stat.tasks.caption":`,
		`"topic.ai.assistant.title":`,
		`"topic.comment.title":`,
		`"topic.comment.scope.current":`,
		`"topic.comment.placeholder":`,
		`"topic.comment.locate":`,
		`"topic.toast.question_too_long":`,
	} {
		if !strings.Contains(en, required) {
			t.Fatalf("english translations should contain %q", required)
		}
		if !strings.Contains(zh, required) {
			t.Fatalf("chinese translations should contain %q", required)
		}
	}
	for _, forbidden := range []string{
		`"topic.detail.tab.details":              "详情"`,
		`"topic.resource.empty.title":            "还没有资料"`,
		`"topic.ai.assistant.title":              "AI 专题助手"`,
	} {
		if strings.Contains(en, forbidden) {
			t.Fatalf("english translations should not keep chinese UI text: %q", forbidden)
		}
	}
}

func assertCSSRuleContains(t *testing.T, css, selector, declaration string) {
	t.Helper()
	rule := cssRule(css, selector)
	if rule == "" {
		t.Fatalf("topics css should contain selector %q", selector)
	}
	if !strings.Contains(rule, declaration) {
		t.Fatalf("selector %q should contain %q; rule=%s", selector, declaration, rule)
	}
}

func assertCSSRuleNotContains(t *testing.T, css, selector, declaration string) {
	t.Helper()
	rule := cssRule(css, selector)
	if rule == "" {
		t.Fatalf("topics css should contain selector %q", selector)
	}
	if strings.Contains(rule, declaration) {
		t.Fatalf("selector %q should not contain %q; rule=%s", selector, declaration, rule)
	}
}

func cssRule(css, selector string) string {
	start := strings.Index(css, selector+" {")
	if start < 0 {
		return ""
	}
	end := strings.Index(css[start:], "\n}")
	if end < 0 {
		return css[start:]
	}
	return css[start : start+end+2]
}
