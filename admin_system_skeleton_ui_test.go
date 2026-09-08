package main

import (
	"os"
	"strings"
	"testing"
)

func TestAdminSystemMemberLoadingUsesSkeleton(t *testing.T) {
	tpl, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		".admin-member-skeleton",
		".admin-skeleton-block",
		"admin-member-skeleton-shimmer",
		"function renderMemberSkeleton()",
		"listEl.innerHTML = renderMemberSkeleton();",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("admin system member loading skeleton missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`listEl.innerHTML = '<div class="text-center py-8 text-slate-400"><i class="fa-solid fa-spinner fa-spin"`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("admin system member loading should not use spinner, found %q", forbidden)
		}
	}
}
