package controllers

import "testing"

func TestDAVPublicAssetCacheControl(t *testing.T) {
	const version = "2bfd88fef0d721b24b3a97bd5e3c8a36cabff0c6"
	tests := []struct {
		path string
		want string
	}{
		{"/pptist/" + version + "/fonts/Roboto.woff2", "public, max-age=31536000, immutable"},
		{"pptist/" + version + "/fonts/SourceHanSans.WOFF2", "public, max-age=31536000, immutable"},
		{"/pptist/latest/fonts/Roboto.woff2", "public, max-age=3600"},
		{"/pptist/" + version + "/fonts/theme.css", "public, max-age=3600"},
		{"/vendor/app.js", "public, max-age=3600"},
	}
	for _, test := range tests {
		if got := davPublicAssetCacheControl(test.path); got != test.want {
			t.Errorf("davPublicAssetCacheControl(%q) = %q, want %q", test.path, got, test.want)
		}
	}
}
