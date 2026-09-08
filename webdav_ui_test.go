package main

import (
	"os"
	"strings"
	"testing"
)

func TestWebDAVPageUsesSystemComponentsAndResponsiveStates(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/webdav.html")
	if err != nil {
		t.Fatalf("ReadFile(webdav.html) error = %v", err)
	}
	template := string(templateBytes)
	for _, required := range []string{
		`{{template "header" .}}`,
		`{{template "footer" .}}`,
		`<body class="dav-body min-h-screen">`,
		`class="dav-toolbar page-sticky-header"`,
		`class="bs-btn bs-btn-cancel"`,
		`class="bs-btn bs-btn-primary"`,
		`aria-modal="true"`,
		`id="davLoading"`,
		`id="davDropZone"`,
		`data-hash-worker="/static/js/webdav-hash-worker.js`,
		`id="davUsageDetails"`,
		`id="davUsageFileCount"`,
		`id="davUsageStored"`,
		`id="davUsageDeduplicated"`,
		`id="davUsageCompressed"`,
		`id="davLoadError"`,
		`id="davRetryBtn"`,
		`{{call .T "webdav.search.placeholder"}}`,
		`{{call .T "webdav.empty.mobile_hint"}}`,
		`class="dav-modal asset-modal-backdrop"`,
		`class="dav-modal-dialog asset-modal"`,
		`class="asset-modal-head"`,
		`class="asset-modal-title"`,
		`class="dav-modal-body asset-modal-body"`,
		`class="dav-modal-footer asset-modal-foot"`,
		`data-mobile-sheet-panel=".asset-modal"`,
		`data-mobile-sheet-close="BookStarkWebDAV.closeModal"`,
		`/static/css/code-editor-modal.css`,
		`/static/js/codemirror-html.min.js`,
		`/static/js/code-editor-modal.js`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("WebDAV template missing %q", required)
		}
	}

	cssBytes, err := os.ReadFile("static/css/webdav.css")
	if err != nil {
		t.Fatalf("ReadFile(webdav.css) error = %v", err)
	}
	css := string(cssBytes)
	for _, required := range []string{
		".dav-toolbar.is-stuck",
		".dav-body {",
		"min-height: 100dvh",
		".dav-page {",
		"max-width: 1180px",
		"@media (max-width: 760px)",
		".dav-modal-close",
		".dav-modal .bs-btn-danger",
		".dav-loading",
		".dav-empty[hidden]",
		".dav-page.has-open-menu",
		".dav-menu-backdrop",
		".dav-toolbar.is-root .dav-breadcrumbs",
		".dav-modal-footer",
		"min-height: 44px",
		"@media (max-width: 360px)",
		"grid-template-areas:",
		".dav-usage-metric",
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("WebDAV CSS missing %q", required)
		}
	}
	for _, forbidden := range []string{
		"var(--color-bg-subtle)",
		"var(--shadow-xl)",
		"var(--font-mono)",
		"bs-btn-secondary",
		".dav-modal-backdrop",
		"@keyframes davSlideDown",
	} {
		if strings.Contains(template, forbidden) || strings.Contains(css, forbidden) {
			t.Fatalf("WebDAV UI still uses unsupported token/class %q", forbidden)
		}
	}
}

func TestWebDAVClientSupportsCustomAppPasswordAndTracksUploadStages(t *testing.T) {
	jsBytes, err := os.ReadFile("static/js/webdav.js")
	if err != nil {
		t.Fatalf("ReadFile(webdav.js) error = %v", err)
	}
	js := string(jsBytes)
	for _, required := range []string{
		"if (action === 'save-password') {",
		`id="davAppPassword"`,
		`id="davAppPasswordConfirm"`,
		"password !== confirmation",
		"jsonRequest('/api/webdav/app-password/reset', 'POST', { password: password })",
		"data-password-toggle",
		"modal.dataset.passwordForm === 'true'",
		"return;",
		"webdav.upload.hashing",
		"webdav.upload.verifying",
		"webdav.upload.uploading",
		"function setModalBusy(busy)",
		"window.BookStarkWebDAV.closeModal = closeModal",
		"modal.classList.add('open')",
		"modal.classList.remove('open')",
		"BookStarkScrollLock.lock(modalScrollLockKey)",
		"BookStarkScrollLock.unlock(modalScrollLockKey)",
		"if (event.key === 'Escape')",
		"chunkSize: 2 * 1024 * 1024",
		"id=\"davPublicURLPreview\"",
		"addEventListener('input'",
		"result.action === 'linked' || result.deduplicated",
		"profile.usage.deduplicated_bytes",
		"profile.usage.compression_saved_bytes",
		"var used = profile.usage.stored_bytes || 0",
		"document.body.appendChild(menu)",
		"document.body.appendChild(backdrop)",
		"className = 'dav-menu-backdrop'",
		"data-copy-public",
		"function syncToolbarStuck()",
		"$('#davLoadError').hidden = false",
		"window.BookStarkCodeEditorModal.open({",
		"loading: true",
		"editor.setLoading(true",
		"editor.setContent(data && data.content ? data.content : '', file.name)",
		"editor.showLoadError(error || new Error",
		"new AbortController()",
		"{ signal: controller.signal }",
		"state.editorLoadToken !== loadToken",
		"jsonRequest('/api/webdav/files/content', 'PUT'",
		"$('#davUsageFileCount').textContent",
		"$('#davUsageCompressed').textContent",
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("WebDAV client missing %q", required)
		}
	}
	if strings.Contains(js, `id="davEditor"`) || strings.Contains(js, `$('#davEditor').value`) {
		t.Fatalf("WebDAV text editing should reuse the shared CodeMirror modal instead of a textarea")
	}

	workerBytes, err := os.ReadFile("static/js/webdav-hash-worker.js")
	if err != nil {
		t.Fatalf("ReadFile(webdav-hash-worker.js) error = %v", err)
	}
	worker := string(workerBytes)
	for _, required := range []string{
		"function SHA256()",
		"file.slice(offset, offset + chunkSize)",
		"self.postMessage({ hash: hash.hex() })",
	} {
		if !strings.Contains(worker, required) {
			t.Fatalf("WebDAV hash worker missing %q", required)
		}
	}
}

func TestWebDAVPageHasChineseAndEnglishMessages(t *testing.T) {
	zhBytes, err := os.ReadFile("i18n/zh.go")
	if err != nil {
		t.Fatalf("ReadFile(i18n/zh.go) error = %v", err)
	}
	enBytes, err := os.ReadFile("i18n/en.go")
	if err != nil {
		t.Fatalf("ReadFile(i18n/en.go) error = %v", err)
	}
	zh, en := string(zhBytes), string(enBytes)
	for _, key := range []string{
		"webdav.title",
		"webdav.usage.details",
		"webdav.usage.files",
		"webdav.usage.stored",
		"webdav.usage.deduplicated",
		"webdav.usage.compressed",
		"webdav.error.retry",
		"webdav.empty.mobile_hint",
		"webdav.action.manage_public",
		"webdav.password.generated",
		"webdav.password.new",
		"webdav.password.confirm",
		"webdav.password.requirement",
		"webdav.toast.password_saved",
		"webdav.upload.failed",
	} {
		quoted := `"` + key + `"`
		if !strings.Contains(zh, quoted) {
			t.Fatalf("Chinese messages missing %q", key)
		}
		if !strings.Contains(en, quoted) {
			t.Fatalf("English messages missing %q", key)
		}
	}
}
