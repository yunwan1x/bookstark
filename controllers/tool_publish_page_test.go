package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"golang.org/x/net/html"
)

func TestToolPublishPageRendersInitialFormWithoutMetadataFetch(t *testing.T) {
	router, token := initAssetControllerTest(t)
	title := `来源 </script><img id="injected-node" src=x onerror=alert(1)>`
	b := &models.Blog{BlogTitle: title, BlogIdentify: "first-render-source", BlogType: "article", EditorType: "html", MemberID: 1, BlogDesc: "Source description", BlogContent: "<h1>DO_NOT_EMBED_PRIVATE_BODY</h1>"}
	if err := b.Insert(); err != nil {
		t.Fatal(err)
	}
	id := strconv.FormatInt(b.BlogID, 10)
	check := func(wantTitle, wantVersion string, published bool) {
		t.Helper()
		for _, lang := range []string{"zh", "en"} {
			request := httptest.NewRequest(http.MethodGet, "/market/publish/"+id, nil)
			request.Header.Set("Authorization", "Token "+token)
			request.AddCookie(&http.Cookie{Name: "lang", Value: lang})
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if response.Code != 200 || response.Header().Get("Cache-Control") != "private, no-store" {
				t.Fatalf("page: %d %s", response.Code, response.Body.String())
			}
			document, err := html.Parse(strings.NewReader(response.Body.String()))
			if err != nil {
				t.Fatal(err)
			}
			nodes := map[string]*html.Node{}
			attr := func(n *html.Node, key string) string {
				for _, a := range n.Attr {
					if a.Key == key {
						return a.Val
					}
				}
				return ""
			}
			has := func(n *html.Node, key string) bool {
				for _, a := range n.Attr {
					if a.Key == key {
						return true
					}
				}
				return false
			}
			var walk func(*html.Node)
			walk = func(n *html.Node) {
				if key := attr(n, "id"); key != "" {
					nodes[key] = n
				}
				for child := n.FirstChild; child != nil; child = child.NextSibling {
					walk(child)
				}
			}
			walk(document)
			for _, key := range []string{"toolPublishFields", "publishTitle", "publishVersion", "publishCategory", "publishDestination", "publishDescription", "publishAccess", "publishRead", "publishSave", "publishNetwork", "publishNotes", "toolPublishBack", "toolPublishDraft", "toolPublishPreview", "toolAppearancePlaceholder"} {
				if nodes[key] == nil {
					t.Fatalf("initial HTML is missing %s", key)
				}
			}
			if attr(nodes["publishTitle"], "value") != wantTitle || attr(nodes["publishVersion"], "value") != wantVersion {
				t.Fatal("initial values are not hydrated by the server")
			}
			label := "工具名称"
			if lang == "en" {
				label = "Tool name"
			}
			if nodes["publishTitle"].Parent.FirstChild.Data != label {
				t.Fatal("initial form is not translated")
			}
			if !has(nodes["toolPublishFields"], "disabled") || nodes["injected-node"] != nil || strings.Contains(response.Body.String(), "DO_NOT_EMBED_PRIVATE_BODY") {
				t.Fatal("unsafe or incomplete initial markup")
			}
			state := nodes["toolPublishState"]
			if state == nil || state.FirstChild == nil || attr(state, "type") != "application/json" {
				t.Fatal("initial state missing")
			}
			var initial, api map[string]any
			if err := json.Unmarshal([]byte(state.FirstChild.Data), &initial); err != nil {
				t.Fatal(err)
			}
			metadata := adminAssetRequest(router, token, "GET", "/api/blogs/"+id+"/tool", nil)
			if metadata.Code != 200 || json.Unmarshal(metadata.Body.Bytes(), &api) != nil || !reflect.DeepEqual(initial, api) {
				t.Fatal("page and API publication metadata drifted")
			}
			if initial["published"] != published || initial["title"] != title {
				t.Fatal("source metadata changed")
			}
			if published && (has(nodes["publishRead"], "checked") || has(nodes["publishSave"], "checked") || !has(nodes["publishNetwork"], "checked") || has(nodes["publishMembers"], "hidden")) {
				t.Fatal("published permissions were not rendered")
			}
		}
	}
	check(title, "1.0.0", false)
	response := adminAssetRequest(router, token, "POST", "/api/blogs/"+id+"/tool", map[string]any{"version": "1.2.3", "title": "Published tool", "category": "development", "access": "members", "member_accounts": []string{"admin"}, "permissions": map[string]bool{"read_files": false, "save_files": false, "network": true}})
	if response.Code != 200 {
		t.Fatal(response.Body.String())
	}
	check("Published tool", "1.2.4", true)
}
