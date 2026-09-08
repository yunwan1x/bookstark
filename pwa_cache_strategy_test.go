package main

import (
	"os"
	"strings"
	"testing"
)

func TestPWAUsesScopedStaleApiCacheInvalidation(t *testing.T) {
	sw, err := os.ReadFile("static/sw.js")
	if err != nil {
		t.Fatalf("ReadFile(static/sw.js) error = %v", err)
	}
	text := string(sw)
	for _, required := range []string{
		"API_CACHE_META_URL",
		"event.waitUntil(handleSuccessfulMutation(event.request.clone(), response.clone()))",
		"queueMutationRequest(queueRequest)",
		"isOfflineQueueableMutation(url, event.request.method, event.request)",
		"if (path.indexOf('/verify-password') !== -1) return false",
		"mutationInfoForRequest",
		"apiCacheMatchesMutation",
		"markApiCacheStale",
		"clearApiCacheStaleFlag(event.request)",
		"resolveCachedApiResponse(event, cached, resolve)",
		"headers.set('X-Cache-Stale', 'true')",
		"type: 'API_CACHE_STALE'",
		"patchApiCacheForMutation",
		"patchBlogCache",
		"removeBlogFromCache",
		"cachedPath.indexOf('/api/shares') === 0",
		"cachedPath.indexOf('/api/tags/') === 0",
		"response.status >= 500",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("service worker cache strategy missing %q", required)
		}
	}
	if strings.Contains(text, "if (response.ok) {\n          clearApiCache();\n        }") {
		t.Fatalf("mutation handler still clears all API cache directly")
	}
}

func TestOfflineReplayUsesMutationScopedInvalidation(t *testing.T) {
	queue, err := os.ReadFile("static/js/offline-queue.js")
	if err != nil {
		t.Fatalf("ReadFile(static/js/offline-queue.js) error = %v", err)
	}
	text := string(queue)
	for _, required := range []string{
		"notifySWMutationSuccess(record.url, record.method)",
		"type: 'API_MUTATION_SUCCESS'",
		"notifySWMutationSuccess: notifySWMutationSuccess",
		"res.status === 408 || res.status === 429 || res.status >= 500",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("offline queue scoped invalidation missing %q", required)
		}
	}
	if strings.Contains(text, "if (success > 0) {\n          notifySWCacheInvalidation();\n        }") {
		t.Fatalf("offline replay still clears all API cache after sync")
	}
}

func TestServiceWorkerLogicParticipatesInBuildHash(t *testing.T) {
	data, err := os.ReadFile("build.py")
	if err != nil {
		t.Fatalf("ReadFile(build.py) error = %v", err)
	}
	text := string(data)
	for _, required := range []string{
		"def sw_logic_md5(filepath):",
		"const STATIC_ASSETS = [__ASSETS__];",
		"fhash = sw_logic_md5(rel) if rel == 'static/sw.js' else file_md5(rel)",
		"sw.js is appended once below with the combined hash as its version",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("service worker build hash support missing %q", required)
		}
	}
}

func TestServiceWorkerIgnoresStaticAssetVersionQuery(t *testing.T) {
	sw, err := os.ReadFile("static/sw.js")
	if err != nil {
		t.Fatalf("ReadFile(static/sw.js) error = %v", err)
	}
	text := string(sw)
	for _, required := range []string{
		"matchStaticAsset(event.request)",
		"function matchStaticAsset(request)",
		"caches.match(request, { ignoreSearch: true })",
		"function matchOfflinePage()",
		"caches.match('/static/offline.html', { ignoreSearch: true })",
		"matchOfflinePage().then(function(offlinePage)",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("service worker static asset version fallback missing %q", required)
		}
	}
	if strings.Contains(text, "caches.match('/static/offline.html').then") {
		t.Fatalf("offline page fallback should ignore version query")
	}
}

func TestCachedPWANavigationPaintsImmediately(t *testing.T) {
	sw, err := os.ReadFile("static/sw.js")
	if err != nil {
		t.Fatalf("ReadFile(static/sw.js) error = %v", err)
	}
	text := string(sw)
	for _, required := range []string{
		"const HTML_FIRST_LOAD_TIMEOUT_MS = 5000",
		"caches.match(event.request).then(function(cached)",
		"event.waitUntil(backgroundRefresh.then(function() {}))",
		"return cached;",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("service worker fast cached navigation missing %q", required)
		}
	}
	for _, forbidden := range []string{
		"HTML_CACHED_START_TIMEOUT_MS",
		"resolve(cached)",
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("cached navigation must not wait before painting, found %q", forbidden)
		}
	}
}

func TestSessionChangesClearCachedHTMLPages(t *testing.T) {
	register, err := os.ReadFile("static/js/sw-register.js")
	if err != nil {
		t.Fatalf("ReadFile(static/js/sw-register.js) error = %v", err)
	}
	registerText := string(register)
	for _, required := range []string{
		"function clearPageCache()",
		"request.mode === 'navigate'",
		"request.destination === 'document'",
		"accept.indexOf('text/html') !== -1",
		"clearPageCache: clearPageCache",
	} {
		if !strings.Contains(registerText, required) {
			t.Fatalf("PWA page cache clearing missing %q", required)
		}
	}

	login, err := os.ReadFile("templates/login.html")
	if err != nil {
		t.Fatalf("ReadFile(templates/login.html) error = %v", err)
	}
	base, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(templates/base.html) error = %v", err)
	}
	for name, text := range map[string]string{
		"login":  string(login),
		"logout": string(base),
	} {
		if !strings.Contains(text, "BookStarkPWA.clearPageCache") {
			t.Fatalf("%s flow must clear cached HTML pages before navigation", name)
		}
	}
}

func TestStaleCacheToastIsRegistered(t *testing.T) {
	utils, err := os.ReadFile("static/js/utils.js")
	if err != nil {
		t.Fatalf("ReadFile(static/js/utils.js) error = %v", err)
	}
	text := string(utils)
	for _, required := range []string{
		"API_CACHE_STALE",
		"offline.cache_stale",
		"offlineQueued: true",
		"X-Offline-Queued",
		"lastStaleToastAt",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("stale cache toast missing %q", required)
		}
	}
}

func TestOfflineStatusProbeRequiresLiveNetwork(t *testing.T) {
	status, err := os.ReadFile("static/js/offline-status.js")
	if err != nil {
		t.Fatalf("ReadFile(static/js/offline-status.js) error = %v", err)
	}
	statusText := string(status)
	for _, required := range []string{
		"__online_probe=",
		"X-BookStark-Online-Probe",
		"!response || !response.ok",
		"response.headers.get('X-From-Cache') === 'true'",
		"response.headers.get('X-Cache-Stale') === 'true'",
		"setOnline(false)",
	} {
		if !strings.Contains(statusText, required) {
			t.Fatalf("offline status probe missing %q", required)
		}
	}

	sw, err := os.ReadFile("static/sw.js")
	if err != nil {
		t.Fatalf("ReadFile(static/sw.js) error = %v", err)
	}
	swText := string(sw)
	for _, required := range []string{
		"isOnlineProbeRequest(url, event.request)",
		"if (isOnlineProbeRequest(url, event.request)) return;",
		"url.searchParams.has('__online_probe')",
		"request.headers.get('X-BookStark-Online-Probe') === '1'",
	} {
		if !strings.Contains(swText, required) {
			t.Fatalf("service worker online probe bypass missing %q", required)
		}
	}
}

func TestOfflineStatusDoesNotScheduleAutomaticProbes(t *testing.T) {
	status, err := os.ReadFile("static/js/offline-status.js")
	if err != nil {
		t.Fatalf("ReadFile(static/js/offline-status.js) error = %v", err)
	}
	statusText := string(status)
	for _, forbidden := range []string{
		"scheduleProbe",
		"probeTimer",
		"scheduleProbe(15000)",
		"offlineStatusTrigger",
		"offline-status-trigger",
	} {
		if strings.Contains(statusText, forbidden) {
			t.Fatalf("offline status should not schedule automatic probes or create a header trigger, found %q", forbidden)
		}
	}
	for _, required := range []string{
		"refreshWithProbe",
		"window.addEventListener('online'",
		"window.BookStarkOfflineStatus",
		"mount: function(target)",
	} {
		if !strings.Contains(statusText, required) {
			t.Fatalf("offline status explicit probe/mount support missing %q", required)
		}
	}
}

func TestAdminSystemDoesNotIncludePWAStatusPanel(t *testing.T) {
	tpl, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	text := string(tpl)
	for _, forbidden := range []string{
		`id="tab-pwa"`,
		`id="panel-pwa"`,
		`id="adminOfflineStatusMount"`,
		`admin.tab.pwa`,
		`admin.pwa.title`,
		`window.BookStarkOfflineStatus.mount('adminOfflineStatusMount')`,
		`['members', 'settings', 'ai', 'pwa', 'data']`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("admin system should not include PWA panel, found %q", forbidden)
		}
	}
	if !strings.Contains(text, `['members', 'comments', 'settings', 'ai', 'data']`) {
		t.Fatalf("admin system tab list should exclude pwa")
	}
}

func TestAdminSystemTabsAreHorizontallyScrollable(t *testing.T) {
	tpl, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	text := string(tpl)
	for _, required := range []string{
		`.admin-tabs { overflow-x: auto;`,
		`.admin-tabs .tab-btn { flex: 1 0 max-content;`,
		`role="tablist" class="admin-tabs flex`,
		`scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' })`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("admin system scrollable tabs missing %q", required)
		}
	}
}

func TestProfileUsesTabbedPanelsAndIncludesPWAStatus(t *testing.T) {
	tpl, err := os.ReadFile("templates/profile.html")
	if err != nil {
		t.Fatalf("ReadFile(profile.html) error = %v", err)
	}
	text := string(tpl)
	for _, required := range []string{
		`role="tablist"`,
		`id="tab-profile"`,
		`id="tab-pwa"`,
		`id="tab-api"`,
		`id="profile-language"`,
		`id="profile-theme"`,
		`function switchProfileTheme(theme)`,
		`window.BookStarkTheme.set(theme)`,
		`id="profileOfflineStatusMount"`,
		`window.BookStarkOfflineStatus.mount('profileOfflineStatusMount')`,
		`function switchProfileTab(tab, opts)`,
		`function switchProfileLanguage(lang)`,
		`profile.tab.pwa`,
		`profile.pwa.title`,
		`profile.field.language`,
		`profile.field.theme`,
		`profile.pwd.title`,
		`id="old_password"`,
		`profile.language.zh`,
		`profile.language.en`,
		`<option value="zh" {{if ne .Lang "en"}}selected{{end}}>`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("profile tabbed PWA panel missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`id="tab-password"`,
		`id="panel-password"`,
		`['profile', 'pwa', 'api', 'password']`,
		`profile.tab.password`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("password should be merged into profile tab, found %q", forbidden)
		}
	}
}

func TestMobileHeaderHidesLanguageSwitcher(t *testing.T) {
	base, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	text := string(base)
	if strings.Contains(text, "offlineStatusTrigger") {
		t.Fatalf("header swipe ignore list should not reference removed offlineStatusTrigger")
	}
	for _, required := range []string{
		`header-lang-switcher`,
		`.header-lang-switcher, .header-theme-toggle { display: none !important; }`,
		`lang-switcher-wrapper header-lang-switcher`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("mobile header language switcher handling missing %q", required)
		}
	}
}

func TestMobileHeaderShowsAllPrimaryNavWithoutMoreMenu(t *testing.T) {
	base, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	text := string(base)
	for _, required := range []string{
		`header-knowledge-menu`,
		`header-collections-menu`,
		`header-assets-menu`,
		`header-create-menu`,
		`{{call .T "nav.knowledge"}}`,
		`{{call .T "nav.todos"}}`,
		`{{call .T "nav.collections"}}`,
		`{{call .T "note.tab.articles"}}`,
		`{{call .T "nav.assets"}}`,
		`{{call .T "nav.create"}}`,
		`href="/notes?tab=tasks"`,
		`href="/notes?tab=articles"`,
		`href="/books" class="header-menu-item`,
		`href="/bookmarks" class="header-menu-item`,
		`href="/shares" class="header-menu-item`,
		`href="/admin/assets" class="header-menu-item`,
		`.header-lang-switcher, .header-theme-toggle { display: none !important; }`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("mobile header primary nav missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`headerMoreTrigger`,
		`headerMoreDropdown`,
		`header-more-nav`,
		`header-more-panel`,
		`header-action-menu`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("mobile header should not render more menu, found %q", forbidden)
		}
	}
}

func TestMarkdownOutlineSkipsFencedCodeBlocks(t *testing.T) {
	editor, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatalf("ReadFile(editor.js) error = %v", err)
	}
	text := string(editor)
	for _, required := range []string{
		`function extractHeadings(markdown)`,
		`var cherryHeadings = extractCherryHeadings();`,
		`function extractCherryHeadings()`,
		`typeof instance.getHtml !== 'function'`,
		`new DOMParser().parseFromString(html || '', 'text/html')`,
		`doc.querySelectorAll('h1, h2, h3, h4, h5, h6')`,
		`function extractMarkdownHeadings(markdown)`,
		`var activeFence = null;`,
		`function getFenceMarker(line)`,
		`line.match(/^\s{0,3}(`,
		`activeFence = fence;`,
		`continue;`,
		`line: i`,
		`var heading = extractHeadings(currentMarkdown)[index];`,
		`var targetLine = heading ? heading.line : -1;`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("markdown outline fenced-code handling missing %q", required)
		}
	}
	if strings.Contains(text, `if (/^#{1,6}\s+/.test(mdLines[i]))`) {
		t.Fatalf("scroll-to-heading should not use a separate naive heading matcher")
	}
}
