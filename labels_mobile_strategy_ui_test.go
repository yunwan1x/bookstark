package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileLabelStrategyPopover(t *testing.T) {
	data, err := os.ReadFile("templates/labels.html")
	if err != nil {
		t.Fatalf("ReadFile(labels.html) error = %v", err)
	}
	text := string(data)
	for _, required := range []string{
		"mobile-strategy-popover",
		"mobile-strategy-sheet",
		"translateY(-105%)",
		"mobile-strategy-popover.active .mobile-strategy-sheet",
		"mobile-strategy-content",
		"function strategyRenderTarget()",
		"isMobileLabelsView() ? document.getElementById('mobile-strategy-content') : document.getElementById('label-detail')",
		"showMobileStrategyPopover()",
		"closeStrategyManager()",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("mobile label strategy popover missing %q", required)
		}
	}
}
