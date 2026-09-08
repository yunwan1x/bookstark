package services

import "testing"

func TestAssetFileShellQuoteEscapesRemotePaths(t *testing.T) {
	got := shellQuote("/tmp/a b/it's.txt")
	want := "'/tmp/a b/it'\\''s.txt'"
	if got != want {
		t.Fatalf("shellQuote() = %q, want %q", got, want)
	}
}

func TestAssetFileHelpers(t *testing.T) {
	if got := remoteJoin("/tmp", "app.log"); got != "/tmp/app.log" {
		t.Fatalf("remoteJoin absolute = %q", got)
	}
	if got := remoteJoin(".", "app.log"); got != "app.log" {
		t.Fatalf("remoteJoin relative = %q", got)
	}
	if got := normalizeMode("644"); got != "0644" {
		t.Fatalf("normalizeMode() = %q, want 0644", got)
	}
	if got := shellFileType("d"); got != "dir" {
		t.Fatalf("shellFileType(d) = %q, want dir", got)
	}
}
