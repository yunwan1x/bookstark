package main

import (
	"os"
	"strings"
	"testing"
)

func TestPageStickyHeaderAccountsForMobileSystemHeader(t *testing.T) {
	baseBytes, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	base := string(baseBytes)

	if !strings.Contains(base, `.page-sticky-header { position: sticky; top: 40px;`) {
		t.Fatalf("page sticky header should keep the desktop header offset")
	}
	if !strings.Contains(base, `@media (max-width: 640px) { header { min-height: 48px;`) {
		t.Fatalf("base header should define the taller mobile header")
	}
	if !strings.Contains(base, `.page-sticky-header { top: 48px; }`) {
		t.Fatalf("page sticky header should use the mobile header height on small screens")
	}
	baseRule := strings.LastIndex(base, `.page-sticky-header { position: sticky; top: 40px;`)
	mobileRule := strings.LastIndex(base, `.page-sticky-header { top: 48px; }`)
	if mobileRule < baseRule {
		t.Fatalf("mobile page sticky header override should appear after the base sticky header rule")
	}

	for _, path := range []string{"templates/index.html", "templates/bookmarks.html"} {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", path, err)
		}
		if !strings.Contains(string(data), `class="page-sticky-header"`) {
			t.Fatalf("%s should use the shared sticky header", path)
		}
	}
}
