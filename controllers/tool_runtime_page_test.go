package controllers_test

import (
	"bookstark/models"
	"html"
	"net/http/httptest"
	"net/url"
	"strconv"
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

func TestToolRuntimeInitialIdentityIsPrivateAndEscaped(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	title := `收音机 </title><script id="runtime-injected">alert(1)</script>`
	for _, id := range []int64{12, -7} {
		tool := models.InstalledTool{ID: id, Title: title, Content: "PRIVATE_TOOL_HTML", Revision: strings.Repeat("a", 64), ToolMetadata: models.ToolMetadata{Category: "media", Icon: "github", IconStyle: "brands", IconColor: "#4F46E5"}}
		if err := models.SaveInstalledTool(1, tool, "", ""); err != nil {
			t.Fatal(err)
		}
		row, err := models.GetInstalledTool(1, id)
		if err != nil {
			t.Fatal(err)
		}
		if err := models.WriteInstalledToolValue(1, id, row.Revision, row.Instance, "set", "private", "PRIVATE_TOOL_VALUE"); err != nil {
			t.Fatal(err)
		}
		response := adminAssetRequest(router, admin, "GET", "/tools/run/"+strconv.FormatInt(id, 10), nil)
		body := response.Body.String()
		if response.Code != 200 || !strings.Contains(body, html.EscapeString(title)) || !strings.Contains(body, `class="fa-brands fa-github"`) || !strings.Contains(body, `--tool-icon-color:#4f46e5`) {
			t.Fatal("initial tool identity missing or invalid", response.Code, body)
		}
		for _, forbidden := range []string{`<script id="runtime-injected">`, "PRIVATE_TOOL_HTML", "PRIVATE_TOOL_VALUE", `id="toolRuntimeSkeleton"`, `skeleton-card-title`, `class="tool-runtime-title is-pending"`} {
			if strings.Contains(body, forbidden) {
				t.Fatal("unexpected initial runtime content:", forbidden)
			}
		}
	}
	other := &models.Member{Account: "runtime-other", Password: "test-password", Email: "runtime-other@example.test", Status: 0, Role: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	if err := models.SaveInstalledTool(other.MemberID, models.InstalledTool{ID: 99, Title: "OTHER_ACCOUNT_TOOL_TITLE", Revision: "private-revision"}, "", ""); err != nil {
		t.Fatal(err)
	}
	body := adminAssetRequest(router, admin, "GET", "/tools/run/99", nil).Body.String()
	if strings.Contains(body, "OTHER_ACCOUNT_TOOL_TITLE") || !strings.Contains(body, `class="tool-runtime-title is-pending"`) {
		t.Fatal("another account's installed identity leaked")
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
