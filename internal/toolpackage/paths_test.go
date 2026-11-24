package toolpackage

import (
	"strings"
	"testing"
)

func TestArchiveRootRelocationPreservesRuntimeAndExternalURLs(t *testing.T) {
	names := map[string]bool{"assets/main.js": true, "assets/font.woff2": true, "assets/icon.svg": true}
	input := "import '/assets/main.js';const wasm=new URL(`/assets/icon.svg?size=2#view`,import.meta.url);" +
		`@font-face{src:url(/assets/font.woff2)}.icon{background:url( /assets/icon.svg )}` +
		`.quoted{background:url('/assets/icon.svg')}` +
		`fetch('/api/channels');fetch('https://cdn.test/assets/main.js');fetch('//cdn.test/assets/main.js');` +
		`body{background:url(https://cdn.test/assets/icon.svg)}.cdn{background:url(//cdn.test/assets/icon.svg)}`
	got := RewriteArchiveRoots(input, names)
	for _, expected := range []string{
		"import '" + Prefix + "assets/main.js'",
		"`" + Prefix + "assets/icon.svg?size=2#view`",
		"url(" + Prefix + "assets/font.woff2)",
		"url(" + Prefix + "assets/icon.svg)",
		"url('" + Prefix + "assets/icon.svg')",
		"fetch('/api/channels')",
		"fetch('https://cdn.test/assets/main.js')",
		"fetch('//cdn.test/assets/main.js')",
		"url(https://cdn.test/assets/icon.svg)",
		"url(//cdn.test/assets/icon.svg)",
	} {
		if !strings.Contains(got, expected) {
			t.Fatalf("relocation lost %q: %s", expected, got)
		}
	}
}

func TestArchiveIntegrityStripsOnlyBundledResources(t *testing.T) {
	names := map[string]bool{"assets/main.css": true, "app/main.js": true}
	input := `<!doctype html><html><head><link href=/assets/main.css integrity=local-css rel=stylesheet><script src=./main.js integrity=local-js></script><script src=https://cdn.test/lib.js integrity=external-js crossorigin=anonymous></script><script src=//cdn.test/protocol.js integrity=protocol-js></script><script src=missing.js integrity=unbundled-js></script></head><body>content</body></html>`
	got, err := StripArchiveIntegrity(input, "app/index.html", names)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(got, `integrity="local-css"`) || strings.Contains(got, `integrity="local-js"`) {
		t.Fatalf("bundled SRI retained: %s", got)
	}
	for _, expected := range []string{`integrity="external-js"`, `integrity="protocol-js"`, `integrity="unbundled-js"`, `crossorigin="anonymous"`, `<body>content</body>`} {
		if !strings.Contains(got, expected) {
			t.Fatalf("unrelated HTML attribute changed %q: %s", expected, got)
		}
	}
}

func TestArchiveEntryHTMLNormalizationAllowsUnquotedRootRelocation(t *testing.T) {
	names := map[string]bool{"assets/main.js": true, "assets/main.css": true}
	input := `<script src=/assets/main.js integrity=original></script><link href=/assets/main.css rel=stylesheet>`
	normalized, err := StripArchiveIntegrity(input, "index.html", names)
	if err != nil {
		t.Fatal(err)
	}
	got := RewriteArchiveRoots(normalized, names)
	if !strings.Contains(got, `src="`+Prefix+`assets/main.js"`) || !strings.Contains(got, `href="`+Prefix+`assets/main.css"`) || strings.Contains(got, "integrity=") {
		t.Fatalf("entry root references were not normalized: %s", got)
	}
}
