package main

import (
	"os"
	"strings"
	"testing"
)

func TestAdminDataPanelUsesAccordionSections(t *testing.T) {
	data, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	html := string(data)

	for _, required := range []string{
		`id="panel-data"`,
		`<details class="ai-action-section" open>`,
		`{{call .T "admin.data.export.title"}}`,
		`{{call .T "admin.data.import.title"}}`,
		`{{call .T "admin.data.bm_import.title"}}`,
		`{{call .T "admin.data.cleanup.title"}}`,
		`id="export-member"`,
		`id="export-include-uploads"`,
		`id="btn-export"`,
		`id="import-target-user"`,
		`id="import-drop-zone"`,
		`id="import-file-input"`,
		`id="bm-import-target-user"`,
		`id="bm-import-custom-date"`,
		`id="bm-import-drop-zone"`,
		`id="bm-import-file-input"`,
		`id="cleanup-member"`,
		`id="cleanup-timeout"`,
		`id="cleanup-concurrency"`,
		`id="btn-cleanup-start"`,
		`id="cleanup-progress-area"`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("admin data accordion missing %q", required)
		}
	}

	panelStart := strings.Index(html, `id="panel-data"`)
	if panelStart < 0 {
		t.Fatalf("panel-data not found")
	}
	panelEnd := strings.Index(html[panelStart:], `{{template "footer" .}}`)
	if panelEnd < 0 {
		t.Fatalf("panel-data end marker not found")
	}
	panel := html[panelStart : panelStart+panelEnd]
	if count := strings.Count(panel, `class="ai-action-section"`); count != 4 {
		t.Fatalf("expected 4 data accordion sections, got %d", count)
	}
}
