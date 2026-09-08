package main

import (
	"os"
	"strings"
	"testing"
)

func TestHTMLPreviewAllowsMediaCaptureInIframe(t *testing.T) {
	js, err := os.ReadFile("static/js/editor-common.js")
	if err != nil {
		t.Fatalf("ReadFile(editor-common.js) error = %v", err)
	}
	text := string(js)

	for _, required := range []string{
		`class="html-editor-iframe html-preview-iframe"`,
		`sandbox="allow-scripts allow-same-origin allow-downloads allow-popups allow-popups-to-escape-sandbox allow-modals"`,
		`allow="camera *; microphone *; display-capture *; fullscreen; autoplay; clipboard-write"`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("HTML preview iframe should allow media permissions, missing %q", required)
		}
	}
}

func TestPermissionsPolicyAllowsSameOriginMediaCapture(t *testing.T) {
	router, err := os.ReadFile("routers/router.go")
	if err != nil {
		t.Fatalf("ReadFile(router.go) error = %v", err)
	}
	text := string(router)

	for _, required := range []string{
		`Permissions-Policy`,
		`camera=(self)`,
		`microphone=(self)`,
		`display-capture=(self)`,
		`geolocation=(self)`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("permissions policy should allow same-origin media capture, missing %q", required)
		}
	}
	if strings.Contains(text, `camera=(), microphone=()`) {
		t.Fatalf("permissions policy still disables camera and microphone")
	}
}
