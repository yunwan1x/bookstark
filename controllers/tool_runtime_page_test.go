package controllers_test

import (
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestInstalledToolRuntimeUsesPrivateStandalonePage(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	for _, id := range []string{"12", "-7"} {
		path := "/tools/run/" + id + "?return=%2Fmarket%3Fstatus%3Dinstalled"
		guest := httptest.NewRecorder()
		router.ServeHTTP(guest, httptest.NewRequest("GET", path, nil))
		login, err := url.Parse(guest.Header().Get("Location"))
		if guest.Code != 302 || err != nil || login.Path != "/login" || login.Query().Get("next") != path {
			t.Fatalf("login return lost: %d %s", guest.Code, guest.Header().Get("Location"))
		}
		response := adminAssetRequest(router, admin, "GET", path, nil)
		if response.Code != 200 || response.Header().Get("Cache-Control") != "private, no-store" {
			t.Fatal(response.Code, response.Body.String())
		}
		body := response.Body.String()
		for _, want := range []string{`class="tool-runtime-body"`, `id="toolRuntime"`, `id="toolRuntimeBack"`, `id="toolRuntimeFullscreen"`, `id="toolRuntimeSaveError"`, `id="toolRuntimeNewTab"`, `/static/css/html-frame.css`, `/static/js/tool-runner.js`, `/static/js/i18n.js`, `window.__I18N_MESSAGES`, `data-bs-action-dropdown-toggle`} {
			if !strings.Contains(body, want) {
				t.Fatalf("missing runtime %s", want)
			}
		}
		for _, old := range []string{`id="marketMain"`, `id="marketRunner"`, `id="marketSaveStatus"`, `class="site-footer`, `class="public-info"`, `/static/js/tool-market.js`} {
			if strings.Contains(body, old) {
				t.Fatalf("old market UI remained in runtime: %s", old)
			}
		}
	}
	for _, path := range []string{"/tools/run/0", "/tools/run/no-id"} {
		response := adminAssetRequest(router, admin, "GET", path, nil)
		if response.Code != 404 {
			t.Fatal("invalid runtime ID accepted")
		}
	}
	market := adminAssetRequest(router, admin, "GET", "/market", nil).Body.String()
	if strings.Contains(market, `id="marketRunner"`) || strings.Contains(market, `/static/js/tool-runner.js`) {
		t.Fatal("market still includes the old runner")
	}
}

func TestLegacyToolOpenRedirectsToStandaloneRuntime(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	response := adminAssetRequest(router, admin, "GET", "/market?open=-7&status=installed&category=image", nil)
	target, err := url.Parse(response.Header().Get("Location"))
	if response.Code != 302 || err != nil || target.Path != "/tools/run/-7" {
		t.Fatal(response.Code, response.Header().Get("Location"))
	}
	back, err := url.Parse(target.Query().Get("return"))
	if err != nil || back.Path != "/market" || back.Query().Get("status") != "installed" || back.Query().Get("category") != "image" || back.Query().Has("open") {
		t.Fatal("legacy redirect lost market filters")
	}
}
