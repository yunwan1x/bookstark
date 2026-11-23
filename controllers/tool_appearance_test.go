package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"strconv"
	"testing"
)

func TestToolPublicationAppearanceValidationAndPersistence(t *testing.T) {
	router, token := initAssetControllerTest(t)
	source := &models.Blog{BlogTitle: "Appearance", BlogIdentify: "appearance-tool", BlogType: "article", EditorType: "html", MemberID: 1, BlogContent: "<h1>Tool</h1>"}
	if err := source.Insert(); err != nil {
		t.Fatal(err)
	}
	path := "/api/blogs/" + strconv.FormatInt(source.BlogID, 10) + "/tool"
	for _, bad := range []map[string]any{
		{"icon": `cube\" onclick=alert(1)`}, {"icon": "not-an-included-icon"}, {"icon": "github", "icon_style": "solid"}, {"icon": "cube", "icon_style": "brands"},
		{"icon_color": "red;background:url(https://example.test)"}, {"icon_color": "#123"},
	} {
		response := adminAssetRequest(router, token, "POST", path+"?preview=1", bad)
		if response.Code != 400 {
			t.Fatalf("invalid appearance accepted: %d %s", response.Code, response.Body.String())
		}
	}
	response := adminAssetRequest(router, token, "POST", path, map[string]any{"version": "1.0.0", "icon": "github", "icon_style": "brands", "icon_color": "#7C3AED"})
	if response.Code != 200 {
		t.Fatal(response.Body.String())
	}
	var result struct {
		Metadata models.ToolMetadata `json:"metadata"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Metadata.Icon != "github" || result.Metadata.IconColor != "#7c3aed" || result.Metadata.IconStyle != "brands" {
		t.Fatalf("appearance not preserved: %#v", result.Metadata)
	}
	response = adminAssetRequest(router, token, "GET", path, nil)
	var page struct {
		Metadata models.ToolMetadata     `json:"metadata"`
		Icons    []models.ToolIconOption `json:"icons"`
	}
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &page) != nil || page.Metadata.Icon != "github" || page.Metadata.IconStyle != "brands" || page.Metadata.IconColor != "#7c3aed" || len(page.Icons) < 2000 {
		t.Fatalf("publication editor lost appearance: %d %s", response.Code, response.Body.String())
	}
	response = adminAssetRequest(router, token, "GET", "/api/tool-market", nil)
	var catalog struct {
		Tools []models.ToolMetadata `json:"tools"`
	}
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &catalog) != nil || len(catalog.Tools) != 1 || catalog.Tools[0].Icon != "github" || catalog.Tools[0].IconStyle != "brands" || catalog.Tools[0].IconColor != "#7c3aed" {
		t.Fatalf("marketplace lost appearance: %d %s", response.Code, response.Body.String())
	}
}

func TestPendingToolPublicationRetainsAppearanceInEditor(t *testing.T) {
	router, _ := initAssetControllerTest(t)
	member := &models.Member{Account: "icon-publisher", Password: "icon-test-password", Email: "icon@example.test", Role: 1, Status: 1}
	if err := member.Insert(); err != nil {
		t.Fatal(err)
	}
	token, err := models.CreateApiToken(member.MemberID, "appearance")
	if err != nil {
		t.Fatal(err)
	}
	source := &models.Blog{BlogTitle: "Pending icon", BlogIdentify: "pending-icon", BlogType: "article", EditorType: "html", MemberID: member.MemberID, BlogContent: "<h1>Tool</h1>"}
	if err := source.Insert(); err != nil {
		t.Fatal(err)
	}
	path := "/api/blogs/" + strconv.FormatInt(source.BlogID, 10) + "/tool"
	response := adminAssetRequest(router, token.Token, "POST", path, map[string]any{"version": "1.0.0", "icon": "weixin", "icon_style": "brands", "icon_color": "#16a34a"})
	if response.Code != 200 {
		t.Fatal(response.Body.String())
	}
	response = adminAssetRequest(router, token.Token, "GET", path, nil)
	var page struct {
		Published bool                `json:"published"`
		Metadata  models.ToolMetadata `json:"metadata"`
	}
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &page) != nil || page.Published || page.Metadata.Status != "pending" || page.Metadata.Icon != "weixin" || page.Metadata.IconStyle != "brands" || page.Metadata.IconColor != "#16a34a" {
		t.Fatalf("pending editor lost appearance: %d %s", response.Code, response.Body.String())
	}
}
