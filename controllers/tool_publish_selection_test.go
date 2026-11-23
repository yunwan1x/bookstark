package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"testing"
)

func TestToolPublicationSourceSelectionPaginationAndEligibility(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	ids := []int64{}
	for i := 0; i < 315; i++ {
		b := &models.Blog{BlogTitle: fmt.Sprintf("Eligible %03d", i), BlogIdentify: fmt.Sprintf("source-page-%d", i), MemberID: 1, BlogType: "article", EditorType: "html", BlogDesc: "Source metadata", BlogContent: "<h1>SECRET_HTML_BODY</h1>"}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, b.BlogID)
	}
	for i, kind := range []string{"markdown", "note", "locked"} {
		b := &models.Blog{BlogTitle: "Eligible invalid " + kind, BlogIdentify: fmt.Sprintf("source-invalid-%d", i), MemberID: 1, BlogType: "article", EditorType: "html", BlogContent: "PRIVATE_CONTENT"}
		if kind == "markdown" {
			b.EditorType = "markdown"
		}
		if kind == "note" {
			b.BlogType = "note"
		}
		if kind == "locked" {
			b.Password = "encrypted"
		}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
	}
	var publishedID = ids[2]
	publication := adminAssetRequest(router, admin, "POST", "/api/blogs/"+strconv.FormatInt(publishedID, 10)+"/tool", map[string]any{"version": "1.0.0"})
	if publication.Code != 200 {
		t.Fatal(publication.Body.String())
	}
	type source struct {
		ID        int64  `json:"id"`
		Title     string `json:"title"`
		Published bool   `json:"published"`
		Version   string `json:"version"`
	}
	type result struct {
		Articles []source `json:"articles"`
		Selected *source  `json:"selected"`
		Total    int      `json:"total"`
		Page     int      `json:"page"`
		Pages    int      `json:"total_pages"`
	}
	read := func(query string) result {
		t.Helper()
		response := adminAssetRequest(router, admin, "GET", "/api/tool-market/articles?"+query, nil)
		if response.Code != 200 || strings.Contains(response.Body.String(), "SECRET_HTML_BODY") || strings.Contains(response.Body.String(), "PRIVATE_CONTENT") {
			t.Fatalf("source metadata list: %d %s", response.Code, response.Body.String())
		}
		var data result
		if err := json.Unmarshal(response.Body.Bytes(), &data); err != nil {
			t.Fatal(err)
		}
		return data
	}
	last := read("q=Eligible&sort=name&page=32&take=10")
	if last.Total != 315 || last.Page != 32 || last.Pages != 32 || len(last.Articles) != 5 || last.Articles[4].Title != "Eligible 314" {
		t.Fatalf("pagination truncated the eligible source list: %#v", last)
	}
	published := read("q=Eligible&status=published")
	if published.Total != 1 || published.Articles[0].ID != publishedID || !published.Articles[0].Published || published.Articles[0].Version != "1.0.0" {
		t.Fatalf("wrong publication state: %#v", published)
	}
	unpublished := read("q=Eligible&status=unpublished&selected=" + strconv.FormatInt(publishedID, 10))
	if unpublished.Total != 314 || unpublished.Selected == nil || unpublished.Selected.ID != publishedID || !unpublished.Selected.Published {
		t.Fatalf("filtered list lost selection: %#v", unpublished)
	}
	searched := read("q=Eligible+002")
	if searched.Total != 1 || searched.Articles[0].ID != publishedID {
		t.Fatalf("source search failed: %#v", searched)
	}
	page := adminAssetRequest(router, admin, "GET", "/market/publish", nil)
	if page.Code != 200 || !strings.Contains(page.Body.String(), `id="toolPublishSelection"`) || strings.Contains(page.Body.String(), `<dialog`) {
		t.Fatal("standalone source selection page unavailable")
	}
}

func TestToolPublicationSourceSelectionRespectsMemberPermissions(t *testing.T) {
	router, admin := initAssetControllerTest(t)
	member := &models.Member{Account: "source-publisher", Password: "selection-password", Email: "source@example.test", Role: 1, Status: 1}
	if err := member.Insert(); err != nil {
		t.Fatal(err)
	}
	token, err := models.CreateApiToken(member.MemberID, "selection")
	if err != nil {
		t.Fatal(err)
	}
	for _, owner := range []int64{1, member.MemberID} {
		b := &models.Blog{BlogTitle: fmt.Sprintf("Owner %d", owner), BlogIdentify: fmt.Sprintf("owner-source-%d", owner), MemberID: owner, BlogType: "article", EditorType: "html", BlogContent: "<h1>Source</h1>"}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
	}
	foreign, _ := models.GetBlogByIdentify("owner-source-1")
	response := adminAssetRequest(router, token.Token, "GET", "/api/tool-market/articles?selected="+strconv.FormatInt(foreign.BlogID, 10), nil)
	var data struct {
		Total    int `json:"total"`
		Selected any `json:"selected"`
	}
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &data) != nil || data.Total != 1 || data.Selected != nil || strings.Contains(response.Body.String(), `"title":"Owner 1"`) {
		t.Fatalf("foreign source exposed: %d %s", response.Code, response.Body.String())
	}
	if err := models.BatchUpdateSettings(map[string]string{"tool_market_members_publish": "0"}); err != nil {
		t.Fatal(err)
	}
	if response := adminAssetRequest(router, token.Token, "GET", "/api/tool-market/articles", nil); response.Code != 403 {
		t.Fatal("member list remained available after publishing permission was revoked")
	}
	if response := adminAssetRequest(router, token.Token, "GET", "/market/publish", nil); strings.Contains(response.Body.String(), `id="toolPublishSelection"`) {
		t.Fatal("member opened source selection after permission was revoked")
	}
	own, err := models.GetBlogByIdentify(fmt.Sprintf("owner-source-%d", member.MemberID))
	if err != nil {
		t.Fatal(err)
	}
	// Revoking new publication access must not remove the owner's existing
	// settings page, where published tools can still be withdrawn.
	if response := adminAssetRequest(router, token.Token, "GET", "/market/publish/"+strconv.FormatInt(own.BlogID, 10), nil); response.Code != 200 || !strings.Contains(response.Body.String(), `id="toolPublishForm"`) {
		t.Fatal("revoking publication access removed existing tool management")
	}
	if response := adminAssetRequest(router, admin, "GET", "/api/tool-market/articles", nil); response.Code != 200 {
		t.Fatal("administrator lost publication access")
	}
}
