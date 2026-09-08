package main

import (
	"os"
	"strings"
	"testing"
)

func TestAdminSettingsPanelUsesAccordionSections(t *testing.T) {
	data, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	html := string(data)

	panelStart := strings.Index(html, `id="panel-settings"`)
	if panelStart < 0 {
		t.Fatalf("panel-settings not found")
	}
	panelEnd := strings.Index(html[panelStart:], `<!-- AI 助手 -->`)
	if panelEnd < 0 {
		t.Fatalf("panel-settings end marker not found")
	}
	panel := html[panelStart : panelStart+panelEnd]

	for _, required := range []string{
		`id="settingsForm"`,
		`<div class="ai-action-sections">`,
		`<details class="ai-action-section" open>`,
		`{{call .T "admin.settings.login"}}`,
		`{{call .T "admin.settings.pagination"}}`,
		`{{call .T "admin.settings.nav"}}`,
		`{{call .T "admin.settings.editor"}}`,
		`{{call .T "admin.settings.cache"}}`,
		`{{call .T "admin.settings.media"}}`,
		`{{call .T "admin.settings.comments"}}`,
		`{{call .T "admin.settings.webrtc"}}`,
		`{{call .T "admin.settings.mail"}}`,
		`{{call .T "admin.settings.invite"}}`,
		`name="nav_max_items"`,
		`name="login_session_days"`,
		`name="save_interval"`,
		`name="favicon_cache_days"`,
		`name="upload_max_size"`,
		`name="share_comments_enabled"`,
		`name="webrtc_signaling_enabled"`,
		`name="webrtc_signaling_stun_urls"`,
		`name="webdav_file_max_bytes"`,
		`name="webdav_user_quota_bytes"`,
		`name="webdav_public_file_max_bytes"`,
		`name="webdav_max_concurrent_transfers"`,
		`name="webdav_public_asset_separate_url_enabled"`,
		`name="mail_enabled"`,
		`name="task_email_reminder_enabled"`,
		`name="smtp_host"`,
		`name="invite_code_enabled"`,
	} {
		if !strings.Contains(panel, required) {
			t.Fatalf("admin settings accordion missing %q", required)
		}
	}

	if count := strings.Count(panel, `class="ai-action-section"`); count != 11 {
		t.Fatalf("expected 11 settings accordion sections, got %d", count)
	}

	if count := strings.Count(panel, `data-webdav-size-mib`); count != 3 {
		t.Fatalf("expected 3 WebDAV MiB size fields, got %d", count)
	}
	for _, required := range []string{
		`<span class="text-sm text-slate-500">MiB</span>`,
		`data[input.name] = String(Math.round(mib * 1048576))`,
		`input.value = String(bytes / 1048576)`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("WebDAV MiB UI missing %q", required)
		}
	}
}
