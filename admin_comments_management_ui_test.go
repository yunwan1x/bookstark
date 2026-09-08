package main

import (
	"os"
	"strings"
	"testing"
)

func TestAdminCommentManagementUIIsWired(t *testing.T) {
	data, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	html := string(data)

	for _, required := range []string{
		`id="tab-comments"`,
		`id="panel-comments"`,
		`switchTab('comments')`,
		`loadAdminComments`,
		`deleteSelectedAdminComments`,
		`/api/admin/share-comments`,
		`/api/admin/share-comments/delete`,
		`name="share_comment_max_length"`,
		`share_comment_max_length`,
		`comment-admin-list`,
		`comment-admin-pagination`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("admin comment management UI missing %q", required)
		}
	}
}

