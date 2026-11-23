package controllers

import (
	"bookstark/models"
	"strings"
	"testing"
)

func TestMarketPackageDecodeLimits(t *testing.T) {
	for _, content := range []string{"<h1>你好</h1>", strings.Repeat("x", 20<<20)} {
		compressed, err := models.EncodeHTMLContent(content)
		if err != nil {
			t.Fatal(err)
		}
		for _, input := range []string{content, compressed} {
			result, err := decodeMarketContent(input)
			if err != nil || result != content {
				t.Fatalf("valid package failed: %v", err)
			}
		}
	}
	oversized := strings.Repeat("x", (20<<20)+1)
	compressed, err := models.EncodeHTMLContent(oversized)
	if err != nil {
		t.Fatal(err)
	}
	for _, input := range []string{oversized, compressed, "CMP:v1:gzip:invalid"} {
		if _, err := decodeMarketContent(input); err == nil {
			t.Fatal("invalid or oversized package accepted")
		}
	}
}
