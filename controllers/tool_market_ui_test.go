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
			page := adminAssetRequest(router, tc.token, "GET", "/market", nil)
			if page.Code != 200 {
				t.Fatal(page.Body.String())
			}
			body := page.Body.String()
			if strings.Contains(body, `id="marketSettings"`) != tc.configure || strings.Contains(body, `id="marketPublish"`) != tc.publish {
				t.Fatalf("wrong actions for %s", tc.name)
			}
			for _, obsolete := range []string{`id="marketCatalogTab"`, `id="marketInstalledTab"`, `id="marketAdmin"`, `class="market-switch"`} {
				if strings.Contains(body, obsolete) {
					t.Fatalf("obsolete nested UI: %s", obsolete)
				}
			}
			if tc.token == "" {
				return
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
	page := adminAssetRequest(router, token.Token, "GET", "/market", nil)
	if strings.Contains(page.Body.String(), `id="marketPublish"`) {
		t.Fatal("publication action exposed after permission revoked")
	}
}
