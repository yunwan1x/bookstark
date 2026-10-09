package main

import (
	"os"
	"strings"
	"testing"
)

func TestShareEditSaveUsesRealServerSuccessAndStableButtonStyle(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("read share template: %v", err)
	}
	template := string(templateBytes)
	for _, required := range []string{
		`#edit-save-btn.saved { color: var(--color-success); }`,
		`result.response.ok && data && data.code === 0 && !data.offlineQueued`,
		`shareAutoSaver.manualSave()`,
		`document.getElementById('edit-save-btn').disabled = true`,
		`cache: 'no-store'`,
		`shareAutoSaver.loadDraft(shareEditServerContent)`,
		`id = 'share-edit-draft-banner'`,
		`status !== 'unsaved' && status !== 'saving'`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("share edit save flow missing %q", required)
		}
	}
	if strings.Contains(template, `#edit-save-btn.saved { background-color:`) {
		t.Fatal("successful share save must not replace the save button background")
	}
}

func TestAutoSaveSerializesWritesAndDraftRequiresExplicitRestore(t *testing.T) {
	commonBytes, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("read editor common JS: %v", err)
	}
	common := string(commonBytes)
	for _, required := range []string{
		`let inFlight = null;`,
		`var DRAFT_DB_NAME = 'bookstark-editor-drafts';`,
		`function writeIndexedDraft(key, content)`,
		`function queueDraftDelete()`,
		`if (inFlight) {`,
		`return inFlight.catch(function() {}).then(function()`,
		`return { content: serverContent, draftContent: draft, hasDraft: true`,
		`queueDraftWrite(current);`,
		`const latest = opts.getContent();`,
		`if (latest !== lastSaved)`,
		`return saveLatest();`,
	} {
		if !strings.Contains(common, required) {
			t.Fatalf("auto-save reliability flow missing %q", required)
		}
	}

	editorBytes, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("read editor JS: %v", err)
	}
	editor := string(editorBytes)
	if !strings.Contains(editor, `applyDraftContentToActiveEditor(draftContent)`) ||
		!strings.Contains(editor, `showDraftBanner(draftResult.serverContent, draftResult.draftContent)`) {
		t.Fatal("editor must render server content until the user explicitly restores a draft")
	}
}

func TestContentSaveRejectsOfflineReplayAndDocumentSwitchRaces(t *testing.T) {
	utilsBytes, err := os.ReadFile("static/js/utils.js")
	if err != nil {
		t.Fatalf("read utils JS: %v", err)
	}
	utils := string(utilsBytes)
	for _, required := range []string{
		`var offlinePolicy = options.offlinePolicy || 'queue';`,
		`options.headers.set('X-BookStark-Offline-Policy', 'reject');`,
		`offlinePolicy !== 'reject' && window.BSOfflineQueue`,
	} {
		if !strings.Contains(utils, required) {
			t.Fatalf("offline policy missing %q", required)
		}
	}

	editorBytes, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("read editor JS: %v", err)
	}
	editor := string(editorBytes)
	for _, required := range []string{
		`var docLoadSequence = 0;`,
		`var docLoadPending = false;`,
		`if (isCurrentDoc(docId) && !docLoadPending) return;`,
		`docLoadController.abort();`,
		`if (loadSequence !== docLoadSequence) return;`,
		`saveMgr.getSaveStatus() === 'saving'`,
		`csrfFetch('/api/docs/' + docId`,
		`offlinePolicy: 'reject'`,
	} {
		if !strings.Contains(editor, required) {
			t.Fatalf("editor save/switch reliability missing %q", required)
		}
	}

	workerBytes, err := os.ReadFile("static/sw.js")
	if err != nil {
		t.Fatalf("read service worker: %v", err)
	}
	if !strings.Contains(string(workerBytes), `request.headers.get('X-BookStark-Offline-Policy') === 'reject'`) {
		t.Fatal("service worker must honor mutation offline rejection policy")
	}
}

func TestServiceWorkerDoesNotQueueShareEditsOrServeStaleEditorPages(t *testing.T) {
	workerBytes, err := os.ReadFile("static/sw.js")
	if err != nil {
		t.Fatalf("read service worker: %v", err)
	}
	worker := string(workerBytes)
	for _, required := range []string{
		`/^\/api\/shares\/[^/]+\/edit(?:\/|$)/.test(path)`,
		`function isEditorPageRequest(url)`,
		`fetch(event.request, { cache: 'no-store' })`,
		`if (url.pathname.startsWith('/api/') && !isNoCacheAPIRequest(url))`,
	} {
		if !strings.Contains(worker, required) {
			t.Fatalf("service worker freshness flow missing %q", required)
		}
	}
}
