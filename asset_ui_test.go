package main

import (
	"os"
	"strings"
	"testing"
)

func TestAdminAssetsSshCredentialPickerContract(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	js, err := os.ReadFile("static/js/assets.js")
	if err != nil {
		t.Fatalf("ReadFile(assets.js) error = %v", err)
	}

	templateText := string(template)
	jsText := string(js)

	for _, forbidden := range []string{
		`<select id="sshCredential"`,
		`<select required id="sshCredential"`,
		`<select id="webdavCredential"`,
		`<select required id="webdavCredential"`,
	} {
		if strings.Contains(templateText, forbidden) {
			t.Fatalf("SSH credential picker should not use native select markup: found %q", forbidden)
		}
	}

	for _, required := range []string{
		`<input type="hidden" id="sshCredential" required>`,
		`data-asset-mode="{{.AssetPageMode}}"`,
		`data-docker-host-id="{{.DockerHostID}}"`,
		`id="dockerPageTitle"`,
		`id="addDockerContainerBtn"`,
		`id="dockerCreateForm"`,
		`asset-docker-subtab`,
		`docker-resource-networks`,
		`docker-resource-volumes`,
		`docker-resource-images`,
		`window.__ASSET_PAGE_MODE__`,
		`window.__DOCKER_HOST_ID__`,
		`id="sshCredentialPicker"`,
		`id="webdavCredentialPicker"`,
		`asset-combobox-input`,
		`dialog-input`,
		`id="sshCredentialDropdown"`,
		`id="webdavCredentialDropdown"`,
		`id="sshShell"`,
		`aria-controls="sshShellOptions"`,
		`id="sshShellOptions"`,
		`asset-autocomplete`,
		`id="sshCwd"`,
		`id="credentialPasswordToggle"`,
		`fa-eye`,
	} {
		if !strings.Contains(templateText, required) {
			t.Fatalf("SSH credential picker markup missing %q", required)
		}
	}

	for _, required := range []string{
		"renderCredentialPicker",
		"renderWebDAVCredentialPicker",
		"assetMode",
		"/admin/assets/ssh-hosts/",
		"/docker",
		"dockerActionButton",
		"docker-action",
		`/static/docker.svg`,
		"openDockerCreateForm",
		"saveDockerCreate",
		"collectDockerCreateRows",
		"/docker-containers",
		"dockerActionMenu",
		"loadDockerVolumes",
		"loadDockerImages",
		"bs-action-dropdown",
		"bs-action-menu-item",
		"restartPolicySubmenu",
		"bs-action-submenu",
		"restart-policy-docker",
		"updateDockerRestartPolicy",
		"/restart-policy",
		"asset-docker-image",
		"selectCredential",
		"selectWebDAVCredential",
		"filterCredentials",
		"filterWebDAVCredentials",
		"hideCredentialDropdown",
		"dropdownIsOpen",
		"focusDropdownItem",
		"moveDropdownFocus",
		"clickDropdownActiveItem",
		"bindAutocomplete",
		"renderAutocomplete",
		"ArrowDown",
		"ArrowUp",
		"Home",
		"End",
		"dockerCreateImageOptions",
		"dockerCreateNetworkOptions",
		"credential_id: Number($('#sshCredential').value)",
		"shell: $('#sshShell').value.trim() || '/bin/sh'",
		"cwd: $('#sshCwd').value.trim()",
		"setCredentialPasswordVisible",
		"credentialPasswordToggle",
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("SSH credential picker script missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`id="settingShell"`,
		"default_shell: $('#settingShell').value",
		`id="confirmModal"`,
		`id="confirmOk"`,
		`data-tab="docker"`,
		`id="dockerHostSummary"`,
		`asset.table.host`,
		`ssh_host_name`,
		`fa-box', 'docker-ssh`,
		"restartPolicySelect",
		"asset-restart-policy-select",
		"data-docker-restart-policy",
		"pendingDelete",
		`<datalist`,
		`list="sshShellOptions"`,
		`list="dockerCreateNetworkOptions"`,
	} {
		if strings.Contains(templateText, forbidden) || strings.Contains(jsText, forbidden) {
			t.Fatalf("asset page should not contain retired custom markup/script: found %q", forbidden)
		}
	}

	if !strings.Contains(jsText, "BSDialog.confirm2") {
		t.Fatalf("asset delete confirmation should use shared BSDialog.confirm2")
	}
}

func TestAdminAssetsSearchControlsMatchNotesHeight(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	templateText := string(template)
	cssText := string(css)

	for _, required := range []string{
		`<div class="asset-toolbar asset-search-row">`,
		`id="sshSearch" class="search-input asset-search-input"`,
		`id="webdavSearch" class="search-input asset-search-input"`,
		`.asset-page .asset-search-row .asset-search-input`,
		`.asset-page .asset-search-row .asset-panel-action`,
		`min-height: 38px;`,
		`.asset-page .asset-search-row .asset-search-input { padding: 6px 10px; font-size: 12px; }`,
		`.asset-page .asset-search-row .asset-panel-action { padding: 6px 10px; font-size: 12px; }`,
	} {
		if !strings.Contains(templateText, required) && !strings.Contains(cssText, required) {
			t.Fatalf("asset search controls should match notes height, missing %q", required)
		}
	}
}

func TestAdminAssetsSshWebdavTabsDoNotRenderTitleCounts(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	js, err := os.ReadFile("static/js/assets.js")
	if err != nil {
		t.Fatalf("ReadFile(assets.js) error = %v", err)
	}
	templateText := string(template)
	jsText := string(js)

	for _, forbidden := range []string{
		`id="sshCount"`,
		`id="webdavCount"`,
		`$('#sshCount')`,
		`$('#webdavCount')`,
	} {
		if strings.Contains(templateText, forbidden) || strings.Contains(jsText, forbidden) {
			t.Fatalf("SSH/WebDAV tab titles should not render or update count badges, found %q", forbidden)
		}
	}
}

func TestAdminAssetsCreateButtonsMatchBookCreateButtonSize(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	templateText := string(template)
	cssText := string(css)

	for _, required := range []string{
		`id="addSshBtn"`,
		`id="addWebdavBtn"`,
		`id="addCredentialBtn"`,
	} {
		if !strings.Contains(templateText, required) {
			t.Fatalf("asset create button markup missing %q", required)
		}
	}

	for _, required := range []string{
		`.asset-page .asset-search-row .asset-panel-action`,
		`.asset-page .asset-settings-panel .asset-panel-action`,
		`width: 78px;`,
		`height: 38px;`,
		`padding: 8px 16px;`,
		`font-size: 14px;`,
		`line-height: 20px;`,
		`border-radius: 8px;`,
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("asset create buttons should match book create button size, missing %q", required)
		}
	}
}

func TestAdminAssetsSshWebdavDoNotRenderStatusFilterChips(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	js, err := os.ReadFile("static/js/assets.js")
	if err != nil {
		t.Fatalf("ReadFile(assets.js) error = %v", err)
	}
	templateText := string(template)
	jsText := string(js)

	for _, forbidden := range []string{
		`data-status-filter="ssh"`,
		`data-status-filter="webdav"`,
	} {
		if strings.Contains(templateText, forbidden) {
			t.Fatalf("SSH/WebDAV page should not render status filter chips: found %q", forbidden)
		}
	}

	for _, required := range []string{
		`if (inputs.length === 0) return null;`,
		`(!statuses || statuses.indexOf(item.status) >= 0)`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("SSH/WebDAV status fallback missing %q", required)
		}
	}
}

func TestAdminAssetsFileEditorMobileContract(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	css, err := os.ReadFile("static/css/code-editor-modal.css")
	if err != nil {
		t.Fatalf("ReadFile(code-editor-modal.css) error = %v", err)
	}
	js, err := os.ReadFile("static/js/assets.js")
	if err != nil {
		t.Fatalf("ReadFile(assets.js) error = %v", err)
	}
	editorJS, err := os.ReadFile("static/js/code-editor-modal.js")
	if err != nil {
		t.Fatalf("ReadFile(code-editor-modal.js) error = %v", err)
	}

	templateText := string(template)
	cssText := string(css)
	jsText := string(js)
	editorJSText := string(editorJS)

	for _, required := range []string{
		`/static/css/code-editor-modal.css`,
		`/static/js/code-editor-modal.js`,
	} {
		if !strings.Contains(templateText, required) {
			t.Fatalf("asset page should load shared code editor asset %q", required)
		}
	}
	for _, required := range []string{
		`button('undo', 'fa-rotate-left'`,
		`button('redo', 'fa-rotate-right'`,
		`button('search', 'fa-magnifying-glass'`,
		`data-code-editor-save data-mobile-editor-tool="keep"`,
		`function setLoading(loading, message)`,
		`function setContent(content, fileName)`,
		`function showLoadError(error, retry)`,
		`data-code-editor-retry`,
		`global.BookStarkCodeEditorModal = api`,
	} {
		if !strings.Contains(editorJSText, required) {
			t.Fatalf("shared code editor mobile toolbar missing %q", required)
		}
	}

	for _, required := range []string{
		`.code-editor-actions [data-code-editor-command]:not([data-mobile-editor-tool="keep"])`,
		`.code-editor-actions [data-code-editor-maximize]`,
		`.code-editor-state`,
		`.code-editor-spinner`,
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("file editor mobile toolbar CSS missing %q", required)
		}
	}

	contentFetch := `apiJSON(base + '/content?path=' + encodeURIComponent(path), controller ? { signal: controller.signal } : {})`
	openEditorModal := `window.BookStarkCodeEditorModal.open({`
	if !strings.Contains(jsText, contentFetch) || !strings.Contains(jsText, openEditorModal) {
		t.Fatalf("file editor open flow missing content fetch or shared editor call")
	}
	if strings.Index(jsText, openEditorModal) > strings.Index(jsText, contentFetch) {
		t.Fatalf("file editor modal should open before content fetch starts")
	}
	for _, required := range []string{
		`loading: true`,
		`new AbortController()`,
		`{ signal: controller.signal }`,
		`editor.setContent(content, path)`,
		`editor.showLoadError(err || new Error(t('asset.error.file_action')), loadContent)`,
		`state.fileEditorLoadToken !== loadToken`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("file editor async loading contract missing %q", required)
		}
	}
	if strings.Contains(jsText, "new CM.EditorView") || strings.Contains(templateText, `id="fileEditorModal"`) {
		t.Fatalf("asset page should not keep a second CodeMirror implementation or editor modal")
	}
	for _, forbidden := range []string{
		"function bindFileEditorSwipeClose()",
		"bindFileEditorSwipeClose();",
		"#fileEditorModal,\n  #fileEditorModal .asset-file-editor-window,\n  #fileEditorPane {",
	} {
		if strings.Contains(jsText, forbidden) || strings.Contains(cssText, forbidden) {
			t.Fatalf("file editor mobile swipe close should be removed, found %q", forbidden)
		}
	}
}

func TestAdminAssetsSessionModalDoesNotCloseOnBackdropClick(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	js, err := os.ReadFile("static/js/assets.js")
	if err != nil {
		t.Fatalf("ReadFile(assets.js) error = %v", err)
	}

	templateText := string(template)
	jsText := string(js)
	for _, required := range []string{
		`id="sessionModal"`,
		`id="closeTerminalDot"`,
		`data-close-modal aria-label="{{call .T "asset.session.close"}}"`,
	} {
		if !strings.Contains(templateText, required) {
			t.Fatalf("session modal close control markup missing %q", required)
		}
	}
	for _, required := range []string{
		`if (event.target !== modal) return;`,
		`if (modal.id === 'sessionModal') return;`,
		`$('#closeTerminalDot').addEventListener('click', closeModals);`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("session modal backdrop close guard missing %q", required)
		}
	}
}

func TestAdminAssetsPrimaryTabsStickyContract(t *testing.T) {
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	cssText := string(css)

	for _, required := range []string{
		".asset-tabs {\n  position: sticky;",
		"top: 40px;",
		"justify-self: start;",
		"display: inline-flex;",
		"width: max-content;",
		"max-width: 100%;",
		"border: 1px solid var(--color-border",
		"border-radius: var(--radius-md",
		"overflow: hidden;",
		"background: var(--color-bg);",
		".asset-tab.active {\n  background: var(--color-primary",
		"color: #fff;",
		".asset-tabs {\n    top: 48px;",
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("asset primary tabs sticky CSS missing %q", required)
		}
	}
}

func TestAdminAssetsMediaPreviewContract(t *testing.T) {
	template, err := os.ReadFile("templates/admin_assets.html")
	if err != nil {
		t.Fatalf("ReadFile(template) error = %v", err)
	}
	js, err := os.ReadFile("static/js/assets.js")
	if err != nil {
		t.Fatalf("ReadFile(assets.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	router, err := os.ReadFile("routers/router.go")
	if err != nil {
		t.Fatalf("ReadFile(router.go) error = %v", err)
	}

	combined := string(template) + "\n" + string(js) + "\n" + string(css) + "\n" + string(router)
	for _, required := range []string{
		`id="filePreviewModal"`,
		`id="filePreviewImage"`,
		`id="filePreviewVideo"`,
		`data-action="' + (isDir ? 'open-file-dir' : previewKind ? 'preview-file' : 'edit-file')`,
		`actionButton(t('asset.files.preview'), 'fa-eye', 'preview-file', item.path)`,
		`base + '/preview?path=' + encodeURIComponent(path)`,
		`function filePreviewKind(path)`,
		`.asset-preview-backdrop`,
		`.asset-preview-video`,
		`assets.GET("/ssh-hosts/:id/files/preview", controllers.PreviewAssetFile)`,
		`assets.GET("/webdav-servers/:id/files/preview", controllers.PreviewAssetWebDAVFile)`,
	} {
		if !strings.Contains(combined, required) {
			t.Fatalf("asset media preview contract missing %q", required)
		}
	}
}

func TestAdminAssetsMobileFileManagerListContract(t *testing.T) {
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	cssText := string(css)

	for _, required := range []string{
		"#panel-files .asset-panel-head {\n  position: sticky;\n  top: 40px;",
		"#panel-files .asset-filter-head {\n    top: 48px;\n    grid-template-columns: minmax(0, 1fr) auto;",
		"#panel-files .asset-file-pathbar {\n    grid-template-columns: auto minmax(0, 1fr);\n    gap: 6px;\n    align-items: start;",
		"#panel-files .asset-file-path {\n    min-width: 0;\n    min-height: 32px;\n    flex-wrap: nowrap;",
		"#panel-files .asset-docker-head-actions {\n    align-self: start;",
		"#panel-files .asset-table tr {\n    display: grid;",
		`"name name name"`,
		`"actions size modified"`,
		"row-gap: 2px;",
		"padding: 7px 10px;",
		"line-height: 26px;",
		"#panel-files .asset-table td:nth-child(2),\n  #panel-files .asset-table td:nth-child(4) {\n    display: none;",
		"#panel-files .asset-actions {\n    justify-content: flex-start;",
		"#panel-files .asset-actions .row-action {\n    width: 26px;\n    height: 26px;",
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("asset mobile file manager list CSS missing %q", required)
		}
	}
}

func TestAdminAssetsFileManagerTitleLinksContract(t *testing.T) {
	js, err := os.ReadFile("static/js/assets.js")
	if err != nil {
		t.Fatalf("ReadFile(assets.js) error = %v", err)
	}
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	combined := string(js) + "\n" + string(css)

	for _, required := range []string{
		"function assetFilesHref(type, id)",
		"'/admin/assets/webdav-servers/'",
		"'/admin/assets/ssh-hosts/'",
		"function assetFilesTitleLink(type, item)",
		`assetFilesTitleLink('ssh', item)`,
		`assetFilesTitleLink('webdav', item)`,
		".asset-name-link {",
		".asset-name-link:hover,\n.asset-name-link:focus-visible {",
	} {
		if !strings.Contains(combined, required) {
			t.Fatalf("asset file manager title link contract missing %q", required)
		}
	}
}

func TestAdminAssetsBackLinkButtonContract(t *testing.T) {
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	cssText := string(css)

	for _, required := range []string{
		".asset-back-link {\n  display: inline-flex;",
		"min-height: 34px;",
		"padding: 0 12px;",
		"border: 1px solid var(--color-border);",
		"border-radius: var(--radius-md);",
		"background: var(--color-bg-card);",
		".asset-back-link:hover {",
		".asset-back-link:focus-visible {",
		"box-shadow: 0 0 0 2px var(--color-focus-ring);",
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("asset back link button CSS missing %q", required)
		}
	}
}

func TestAdminAssetsWebDAVMobileAddButtonHiddenContract(t *testing.T) {
	css, err := os.ReadFile("static/css/assets.css")
	if err != nil {
		t.Fatalf("ReadFile(assets.css) error = %v", err)
	}
	cssText := string(css)

	if !strings.Contains(cssText, "#panel-webdav #addWebdavBtn,\n  #settings-credentials #addCredentialBtn { display: none !important; }") {
		t.Fatalf("WebDAV mobile add button should be hidden by the mobile media rule")
	}
	if !strings.Contains(cssText, ".asset-mobile-fab { display: flex; }") {
		t.Fatalf("mobile FAB should remain available on small screens")
	}
}
