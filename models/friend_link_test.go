package models

import (
	"testing"
)

func TestFooterGroupsPersistenceAndLegacy(t *testing.T) {
	initAssetTestDB(t)
	_, err := DB.Exec(`INSERT INTO md_friend_links(link_name,link_url,create_time,modify_time) VALUES('Legacy','https://example.com',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)`)
	if err != nil {
		t.Fatal(err)
	}
	old, err := ListEnabledFriendLinks()
	if err != nil || len(old) != 1 || old[0].GroupName != "" {
		t.Fatal(old, err)
	}
	items := []FriendLink{
		{LinkName: "Docs", LinkURL: "https://example.com/docs", GroupName: "Resources", GroupOrder: 2, IsEnabled: 1},
		{LinkName: "WeChat", QRCode: "/upload-files/editor/code.png", GroupName: "Follow", GroupOrder: 1, Description: "Scan to follow", IsEnabled: 1},
		{LinkName: "Hidden", LinkURL: "https://example.com/private", GroupName: "Hidden", IsEnabled: 0},
	}
	if err = ReplaceFriendLinks(items, 1); err != nil {
		t.Fatal(err)
	}
	enabled, err := ListEnabledFriendLinks()
	if err != nil {
		t.Fatal(err)
	}
	groups := GroupFriendLinks(enabled)
	if len(groups) != 2 || groups[0].Name != "Follow" || !groups[0].HasQR || groups[0].Links[0].Description != "Scan to follow" {
		t.Fatalf("groups: %+v", groups)
	}
	exported, err := exportFriendLinks()
	if err != nil {
		t.Fatal(err)
	}
	if err = ReplaceFriendLinks(nil, 1); err != nil {
		t.Fatal(err)
	}
	result := &ImportResult{}
	if err = importFriendLinks(&ExportData{FriendLinks: exported}, 1, result); err != nil {
		t.Fatal(err)
	}
	restored, err := ListEnabledFriendLinks()
	if err != nil || len(restored) != 2 || restored[0].QRCode != "/upload-files/editor/code.png" {
		t.Fatal(restored, err)
	}
	// Invalid input must not clear the existing configuration.
	invalid := items[1]
	invalid.QRCode = "/upload-files/../secret.png"
	if ReplaceFriendLinks([]FriendLink{invalid}, 1) == nil {
		t.Fatal("accepted traversal")
	}
	restored, _ = ListEnabledFriendLinks()
	if len(restored) != 2 {
		t.Fatal("invalid save changed configuration")
	}
	// A failure after replacing rows must roll back both tables.
	if _, err = DB.Exec(`CREATE TRIGGER fail_footer BEFORE INSERT ON md_friend_link_details BEGIN SELECT RAISE(ABORT,'test'); END`); err != nil {
		t.Fatal(err)
	}
	if ReplaceFriendLinks(items, 1) == nil {
		t.Fatal("expected transaction failure")
	}
	restored, _ = ListEnabledFriendLinks()
	if len(restored) != 2 || restored[0].QRCode == "" {
		t.Fatal("failed write was not rolled back")
	}
}

func TestFooterQRCodeValidation(t *testing.T) {
	for _, qr := range []string{"https://example.com/code.png", "//example.com/code.png", "/upload-files/a.svg", "/upload-files/%2e%2e/x.png", "/upload-files/a.png?x=1", "/upload-files/a\\b.png"} {
		if (FriendLink{LinkName: "QR", QRCode: qr}).Validate() == nil {
			t.Errorf("accepted %s", qr)
		}
	}
	if (FriendLink{LinkName: "QR", QRCode: "/upload-files/editor/2026/a.png"}).Validate() != nil {
		t.Fatal("valid QR rejected")
	}
	if (FriendLink{LinkName: "link", LinkURL: "javascript:alert(1)"}).Validate() == nil {
		t.Fatal("unsafe link accepted")
	}
}
