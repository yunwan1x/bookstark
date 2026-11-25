package controllers_test

import (
	"bookstark/models"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestPublicToolsUseSharedPlazaShellAndFragments(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	member := &models.Member{Account: "plaza-tools-member", Password: "test-only", Role: 1, Status: 1}
	if err := member.Insert(); err != nil {
		t.Fatal(err)
	}
	token, err := models.CreateApiToken(member.MemberID, "plaza-tools")
	if err != nil {
		t.Fatal(err)
	}
	for _, identity := range []struct {
		token             string
		settings, publish bool
	}{{"", false, false}, {token.Token, false, true}, {admin, true, true}} {
		for _, partial := range []bool{false, true} {
			req := httptest.NewRequest("GET", "/shares?type=tool&status=installed", nil)
			if identity.token != "" {
				req.Header.Set("Authorization", "Token "+identity.token)
			}
			if partial {
				req.Header.Set("X-BookStark-Feed", "content")
			}
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)
			body := w.Body.String()
			if w.Code != 200 {
				t.Fatalf("page %d %s", w.Code, body)
			}
			if !strings.Contains(w.Header().Get("Vary"), "X-BookStark-Feed") || w.Header().Get("Cache-Control") != "private, no-store" {
				t.Fatal("unsafe cache headers")
			}
			for _, want := range []string{`id="marketMain"`, `class="public-feed-state"`, `"kind":"tool"`, `id="marketItems"`, `skeleton-card`, `href="/shares?type=tool" aria-current="page"`} {
				if !strings.Contains(body, want) {
					t.Fatalf("missing %q", want)
				}
			}
			if strings.Contains(body, `id="marketSettings"`) != identity.settings || strings.Contains(body, `id="marketPublish"`) != identity.publish {
				t.Fatal("wrong fragment privileges")
			}
			for _, shell := range []string{`<html`, `class="public-header`, `class="public-info`, `/static/js/public-feed.js`, `/static/js/tool-market.js`} {
				if strings.Contains(body, shell) == partial {
					t.Fatalf("fragment duplicated shell/scripts: %q", shell)
				}
			}
		}
	}
	for _, path := range []string{"/market", "/market?category=image&status=installed&q=pdf&page=2"} {
		w := adminAssetRequest(router, admin, "GET", path, nil)
		u, err := url.Parse(w.Header().Get("Location"))
		if w.Code != 302 || err != nil || u.Path != "/shares" || u.Query().Get("type") != "tool" {
			t.Fatal("compat redirect", w.Code)
		}
		original, _ := url.Parse(path)
		for k, values := range original.Query() {
			if u.Query().Get(k) != values[0] {
				t.Fatal("compat filter lost", k)
			}
		}
	}
	w := adminAssetRequest(router, admin, "GET", "/market/index.json", nil)
	if w.Code != 200 {
		t.Fatal("market discovery interface changed", w.Code)
	}
}
