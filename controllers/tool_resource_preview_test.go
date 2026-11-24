package controllers

import (
	"bookstark/internal/toolpackage"
	"encoding/json"
	"strings"
	"testing"
)

func TestToolResourcePreviewSources(t *testing.T) {
	for _, tc := range []struct{ url, kind, path string }{
		{"https://publisher.test/dav-public/admin/vendor/%E7%BD%91%E6%A0%BC.js?v=1", "webdav", "/vendor/网格.js"},
		{"https://publisher.test/upload-files/editor/image.png", "upload", ""},
		{"https://publisher.test/static/app.js", "static", ""},
		{"https://cdn.test/static/app.js", "external", ""},
		{"https://publisher.test.evil/dav-public/admin/app.js", "external", ""},
		{"http://publisher.test/dav-public/admin/app.js", "external", ""},
	} {
		t.Run(tc.url, func(t *testing.T) {
			result := toolResourcePreviews([]toolpackage.Asset{{URL: tc.url, MIME: "text/javascript", Data: []byte("source")}}, "https://publisher.test")
			if len(result) != 1 || result[0].URL != tc.url || result[0].Kind != tc.kind || result[0].WebDAVPath != tc.path || result[0].Size != 6 || result[0].MIME != "text/javascript" {
				t.Fatalf("wrong resource: %+v", result)
			}
			if tc.kind == "webdav" && result[0].Account != "admin" {
				t.Fatalf("WebDAV owner lost: %+v", result)
			}
			raw, err := json.Marshal(result)
			if err != nil || strings.Contains(string(raw), `"Data"`) || strings.Contains(string(raw), `"data"`) {
				t.Fatalf("resource bytes exposed: %s %v", raw, err)
			}
		})
	}
	raw, err := json.Marshal(toolResourcePreviews(nil, "https://publisher.test"))
	if err != nil || string(raw) != "[]" {
		t.Fatalf("empty resources: %s %v", raw, err)
	}
	result := toolResourcePreviews([]toolpackage.Asset{{URL: "https://user:secret@publisher.test/static/app.js"}}, "https://publisher.test")
	if strings.Contains(result[0].URL, "secret") {
		t.Fatal("resource URL exposed a password")
	}
}
