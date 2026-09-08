package controllers

import (
	"testing"

	"bookstark/services"
)

func TestAssetFileTextDetection(t *testing.T) {
	if !isKnownBinaryFile("/tmp/image.png") {
		t.Fatalf("png should be treated as binary")
	}
	if isKnownBinaryFile("/etc/nginx/nginx.conf") {
		t.Fatalf("conf should not be treated as known binary")
	}
	if !isTextContent([]byte("hello\n中文\n")) {
		t.Fatalf("utf-8 text should be editable")
	}
	if isTextContent([]byte{'h', 0, 'i'}) {
		t.Fatalf("nul byte content should be binary")
	}
	if isTextContent([]byte{0xff, 0xfe, 0xfd}) {
		t.Fatalf("invalid utf-8 should be binary")
	}
}

func TestLimitAssetFileEntries(t *testing.T) {
	entries := []services.AssetFileEntry{
		{Name: "a"},
		{Name: "b"},
		{Name: "c"},
	}

	items, truncated := limitAssetFileEntries(entries, 3)
	if truncated || len(items) != 3 {
		t.Fatalf("exact limit = len %d truncated %v, want len 3 truncated false", len(items), truncated)
	}

	items, truncated = limitAssetFileEntries(entries, 2)
	if !truncated || len(items) != 2 {
		t.Fatalf("over limit = len %d truncated %v, want len 2 truncated true", len(items), truncated)
	}
	if items[0].Name != "a" || items[1].Name != "b" {
		t.Fatalf("unexpected entries after limit: %#v", items)
	}
}

func TestParseAssetHTTPRange(t *testing.T) {
	tests := []struct {
		name    string
		header  string
		size    int64
		start   int64
		end     int64
		partial bool
		wantErr bool
	}{
		{name: "empty", size: 100, start: 0, end: 99},
		{name: "prefix", header: "bytes=10-19", size: 100, start: 10, end: 19, partial: true},
		{name: "open ended", header: "bytes=95-", size: 100, start: 95, end: 99, partial: true},
		{name: "suffix", header: "bytes=-20", size: 100, start: 80, end: 99, partial: true},
		{name: "clamped", header: "bytes=90-200", size: 100, start: 90, end: 99, partial: true},
		{name: "unsatisfiable", header: "bytes=100-120", size: 100, wantErr: true},
		{name: "multi range unsupported", header: "bytes=0-1,3-4", size: 100, wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseAssetHTTPRange(tt.header, tt.size)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("parseAssetHTTPRange() error = nil, want error")
				}
				return
			}
			if err != nil {
				t.Fatalf("parseAssetHTTPRange() error = %v", err)
			}
			if got.Start != tt.start || got.End != tt.end || got.Partial != tt.partial {
				t.Fatalf("parseAssetHTTPRange() = %#v, want start=%d end=%d partial=%v", got, tt.start, tt.end, tt.partial)
			}
		})
	}
}

func TestAssetPreviewMediaDetection(t *testing.T) {
	if kind := assetPreviewMediaKind("/tmp/a.JPG"); kind != "image" {
		t.Fatalf("assetPreviewMediaKind(JPG) = %q, want image", kind)
	}
	if kind := assetPreviewMediaKind("/tmp/movie.mp4"); kind != "video" {
		t.Fatalf("assetPreviewMediaKind(mp4) = %q, want video", kind)
	}
	if isPreviewableAssetMedia("/tmp/readme.md") {
		t.Fatalf("markdown should not be treated as media-previewable")
	}
}
