// Draft only. Not compiled/run during shared Native freeze.
package controllers_test

import (
	"bookstark/models"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

func sharedControllerSetupUpdate(t *testing.T, query string, args ...any) {
	t.Helper()
	result, err := models.DB.Exec(query, args...)
	if err != nil {
		t.Fatal(err)
	}
	count, err := result.RowsAffected()
	if err != nil || count != 1 {
		t.Fatal("setup UPDATE did not affect exactly one row")
	}
}
func TestSharedEditLegacyReceiptAndOptionalCASStatus(t *testing.T) {
	router, _ := initAssetControllerTest(t)
	blog := &models.Blog{BlogTitle: "Shared integrity", BlogIdentify: "shared-integrity-controller",
		MemberID: 1, BlogType: "article", EditorType: "markdown", Visibility: 1, BlogContent: "before"}
	if err := blog.Insert(); err != nil {
		t.Fatal(err)
	}
	token := strings.Repeat("fixture", 8)
	share, err := models.CreateShare("blog", blog.BlogID, 1, token)
	if err != nil {
		t.Fatal(err)
	}
	share, err = models.GetShareByTypeAndTarget("blog", blog.BlogID)
	if err != nil || share.ShareID <= 0 {
		t.Fatal("fixture share readback failed")
	}
	path := "/api/shares/" + url.PathEscape(share.ShareIdentify) + "/edit?token=" + url.QueryEscape(token)
	sum := sha256.Sum256([]byte("before"))
	expected := hex.EncodeToString(sum[:])
	w := adminAssetRequest(router, "", http.MethodPut, path, map[string]any{
		"content": "first", "expected_source_sha256": expected})
	if w.Code != http.StatusOK {
		t.Fatal("matching CAS rejected")
	}
	var response struct{ Data map[string]any }
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	sum = sha256.Sum256([]byte("first"))
	if response.Data["modify_time"] == "" || response.Data["source_sha256"] != hex.EncodeToString(sum[:]) {
		t.Fatal("actual source receipt missing")
	}
	// An old explicit baseline cannot overwrite the first writer.
	w = adminAssetRequest(router, "", http.MethodPut, path, map[string]any{
		"content": "must not apply", "expected_source_sha256": expected})
	if w.Code != http.StatusConflict {
		t.Fatal("stale CAS did not return 409")
	}
	actual, err := models.GetBlogByID(blog.BlogID)
	if err != nil || actual.BlogContent != "first" {
		t.Fatal("stale CAS changed source")
	}
	// Legacy client omitting the additive optional field remains supported.
	w = adminAssetRequest(router, "", http.MethodPut, path, map[string]any{"content": "legacy"})
	if w.Code != http.StatusOK {
		t.Fatal("legacy body rejected")
	}
	actual, err = models.GetBlogByID(blog.BlogID)
	if err != nil || actual.BlogContent != "legacy" {
		t.Fatal("legacy save not applied")
	}
}
func TestSharedEditChangedOwnerAndTokenRevocationFailClosed(t *testing.T) {
	router, _ := initAssetControllerTest(t)
	blog := &models.Blog{BlogTitle: "Owner guard", BlogIdentify: "shared-owner-controller",
		MemberID: 1, BlogType: "article", EditorType: "markdown", Visibility: 1, BlogContent: "before"}
	if err := blog.Insert(); err != nil {
		t.Fatal(err)
	}
	token := strings.Repeat("owner-fixture", 4)
	share, err := models.CreateShare("blog", blog.BlogID, 1, token)
	if err != nil {
		t.Fatal(err)
	}
	share, err = models.GetShareByTypeAndTarget("blog", blog.BlogID)
	if err != nil || share.ShareID <= 0 {
		t.Fatal("fixture share readback failed")
	}
	path := "/api/shares/" + url.PathEscape(share.ShareIdentify) + "/edit?token=" + url.QueryEscape(token)
	sharedControllerSetupUpdate(t, "UPDATE md_shares SET member_id=999 WHERE share_id=?", share.ShareID)
	w := adminAssetRequest(router, "", http.MethodPut, path, map[string]any{"content": "wrong owner"})
	if w.Code != http.StatusNotFound {
		t.Fatal("changed owner not rejected")
	}
	sharedControllerSetupUpdate(t, "UPDATE md_shares SET member_id=1,edit_token='' WHERE share_id=?", share.ShareID)
	w = adminAssetRequest(router, "", http.MethodPut, path, map[string]any{"content": "revoked"})
	if w.Code != http.StatusForbidden {
		t.Fatal("revoked token not rejected")
	}
	actual, _ := models.GetBlogByID(blog.BlogID)
	if actual.BlogContent != "before" {
		t.Fatal("denied capability changed source")
	}
}
