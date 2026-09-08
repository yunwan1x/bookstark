package main

import (
	"os"
	"strings"
	"testing"
)

func TestNonPasswordInputsAreMarkedNonCredential(t *testing.T) {
	js, err := os.ReadFile("static/js/utils.js")
	if err != nil {
		t.Fatalf("ReadFile(utils.js) error = %v", err)
	}
	text := string(js)
	for _, required := range []string{
		"BookStarkFormGuards",
		"markNonCredentialInput",
		"MutationObserver",
		"autocomplete', 'off'",
		"data-bookstark-noncredential",
		"data-lpignore",
		"data-1p-ignore",
		"data-bwignore",
		"data-dashlane-disabled",
		"data-protonpass-ignore",
		"data-keeper-ignore",
		"data-form-type",
		"isCredentialUsername",
		"markNonCredentialInput: markNonCredentialInput",
		"input[type=\"password\"]",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("non-password input guard missing %q", required)
		}
	}
	for _, forbidden := range []string{
		"setAttribute('autocomplete', 'new-password')",
		"bs_non_credential_",
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("non-password input guard should not contain %q", forbidden)
		}
	}
}
