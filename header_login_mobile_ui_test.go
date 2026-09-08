package main

import (
	"os"
	"strings"
	"testing"
)

func TestMobileAnonymousHeaderLoginFloatsRight(t *testing.T) {
	tplBytes, err := os.ReadFile("templates/base.html")
	if err != nil {
		t.Fatalf("ReadFile(base.html) error = %v", err)
	}
	tpl := string(tplBytes)

	for _, required := range []string{
		`class="header-login-link text-sm px-2 py-1"`,
		`.header-login-link { margin-left: auto; }`,
		`.header-lang-switcher, .header-theme-toggle { display: none !important; }`,
	} {
		if !strings.Contains(tpl, required) {
			t.Fatalf("anonymous mobile header login alignment missing %q", required)
		}
	}
}
