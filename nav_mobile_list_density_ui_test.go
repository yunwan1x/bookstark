package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileNavListViewUsesCompactSwipeContentPadding(t *testing.T) {
	data, err := os.ReadFile("static/css/nav.css")
	if err != nil {
		t.Fatalf("ReadFile(nav.css) error = %v", err)
	}
	css := string(data)

	for _, required := range []string{
		`.nav-container.view-list .nav-card-manageable .nav-card-content`,
		`padding: 6px 10px;`,
		`transform: translateX(calc(-1 * var(--nav-swipe-width, 88px)))`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("mobile nav list compact swipe content missing %q", required)
		}
	}
	if strings.Contains(css, `.nav-container.view-list .nav-card-manageable .nav-card-content {
        padding: 8px 12px;`) {
		t.Fatalf("mobile nav list swipe content still uses loose padding")
	}
}
