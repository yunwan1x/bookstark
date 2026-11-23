package controllers

import (
	"context"
	"net/url"
	"testing"
)

func TestToolResourceFetchBlocksPrivateNetworks(t *testing.T) {
	for _, raw := range []string{"http://127.0.0.1:1234/file.js", "http://[::1]/file.js", "http://169.254.169.254/latest/meta-data/", "file:///etc/passwd", "http://user:password@example.com/file.js"} {
		u, _ := url.Parse(raw)
		if _, _, err := fetchToolURL(context.Background(), u); err == nil {
			t.Fatalf("unsafe fetch accepted: %s", raw)
		}
	}
}
