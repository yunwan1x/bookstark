package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"strings"
	"testing"
)

func TestToolMarketConfigurationRequiresWorkspaceAdministrator(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	member := &models.Member{Account: "tools-member", Password: "test-market-password", Email: "tools-member@example.test", Role: 1, Status: 1}
	if err := member.Insert(); err != nil {
		t.Fatal(err)
	}
	token, err := models.CreateApiToken(member.MemberID, "market-ui")
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, token        string
		configure, publish bool
	}{
		{"guest", "", false, false}, {"member", token.Token, false, true}, {"admin", admin, true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			page := adminAssetRequest(router, tc.token, "GET", "/shares?type=tool", nil)
			if page.Code != 200 {
				t.Fatal(page.Body.String())
			}
			body := page.Body.String()
			if strings.Contains(body, `id="marketSettings"`) != tc.configure || strings.Contains(body, `id="marketPublish"`) != tc.publish {
				t.Fatalf("wrong actions for %s", tc.name)
			}
			if strings.Contains(body, `id="marketActions"`) != (tc.configure || tc.publish) {
				t.Fatalf("wrong action group visibility for %s", tc.name)
			}
			for _, obsolete := range []string{`id="marketMore"`, `id="marketActionsMenu"`, `id="marketIntro"`, `id="marketHeading"`, `id="marketCatalogTab"`, `id="marketInstalledTab"`, `id="marketAdmin"`, `class="market-switch"`} {
				if strings.Contains(body, obsolete) {
					t.Fatalf("obsolete nested UI: %s", obsolete)
				}
			}
			if tc.token == "" {
				return
			}
			articles := adminAssetRequest(router, tc.token, "GET", "/notes?tab=articles", nil)
			if articles.Code != 200 || strings.Contains(articles.Body.String(), "canPublishTools: true") != tc.publish {
				t.Fatalf("article publication permission does not match market for %s", tc.name)
			}
			response := adminAssetRequest(router, tc.token, "GET", "/api/tool-market/client", nil)
			var config struct {
				CanConfigure bool `json:"can_configure"`
			}
			if json.Unmarshal(response.Body.Bytes(), &config) != nil || config.CanConfigure != tc.configure {
				t.Fatal("configuration permission does not match page")
			}
			for _, write := range []struct{ method, path string }{{"PUT", "/api/tool-market/client"}, {"POST", "/api/tool-market/client/test"}} {
				response := adminAssetRequest(router, tc.token, write.method, write.path, map[string]any{"url": "http://example.com/market", "check_updates": true})
				want := 403
				if tc.configure {
					want = 200
				}
				if response.Code != want {
					t.Fatalf("%s returned %d, want %d: %s", write.path, response.Code, want, response.Body.String())
				}
			}
		})
	}
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_members_publish": "0"}); err != nil {
		t.Fatal(err)
	}
	page := adminAssetRequest(router, token.Token, "GET", "/shares?type=tool", nil)
	if strings.Contains(page.Body.String(), `id="marketPublish"`) || strings.Contains(page.Body.String(), `id="marketMore"`) {
		t.Fatal("publication menu exposed after permission revoked")
	}
	articles := adminAssetRequest(router, token.Token, "GET", "/notes?tab=articles", nil)
	if articles.Code != 200 || strings.Contains(articles.Body.String(), "canPublishTools: true") {
		t.Fatal("article publication action exposed after permission revoked")
	}
}

func TestArticleToolPublicationFollowsMarketAvailability(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_enabled": "0"}); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"/shares?type=tool", "/notes?tab=articles"} {
		page := adminAssetRequest(router, admin, "GET", path, nil)
		if page.Code != 200 || strings.Contains(page.Body.String(), `id="marketPublish"`) || strings.Contains(page.Body.String(), "canPublishTools: true") {
			t.Fatalf("publication exposed while market disabled on %s", path)
		}
		if path == "/shares?type=tool" && (strings.Contains(page.Body.String(), `id="marketMore"`) || !strings.Contains(page.Body.String(), `id="marketSettings"`)) {
			t.Fatal("disabled publishing must hide its menu while keeping administrator settings")
		}
	}
}

func TestToolMarketClientDefaultPreservesSavedSource(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	read := func() map[string]any {
		t.Helper()
		response := adminAssetRequest(router, admin, "GET", "/api/tool-market/client", nil)
		var value map[string]any
		if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &value) != nil {
			t.Fatal(response.Body.String())
		}
		return value
	}
	if p := read(); p["url"] != models.DefaultToolMarketURL || p["configured"] != false {
		t.Fatalf("wrong initial marketplace: %+v", p)
	}
	if _, err := models.DB.Exec("INSERT INTO md_tool_market_clients(member_id,url,check_updates,auto_update) VALUES(1,'https://custom.example/market',0,1)"); err != nil {
		t.Fatal(err)
	}
	if p := read(); p["url"] != "https://custom.example/market" || p["configured"] != true || p["check_updates"] != false || p["auto_update"] != true {
		t.Fatalf("saved marketplace was overridden: %+v", p)
	}
}

func TestToolMarketAdminHasSingleTabAndInitialSkeleton(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	response := adminAssetRequest(router, admin, "GET", "/admin/tool-market", nil)
	if response.Code != 200 {
		t.Fatal(response.Body.String())
	}
	body := response.Body.String()
	for _, required := range []string{`class="market-body"`, `id="marketAdminTab"`, `role="tabpanel"`, `id="marketAdminLoading"`, `aria-busy="true"`, `market-admin-placeholder skeleton-card`} {
		if !strings.Contains(body, required) {
			t.Fatalf("admin loading layout missing %s", required)
		}
	}
	if strings.Contains(body, `class="market-nav"`) || strings.Count(body, `role="tab"`) != 1 {
		t.Fatal("marketplace administration must expose a single tab")
	}
}
