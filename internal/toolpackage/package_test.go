package toolpackage

import (
	"context"
	"fmt"
	"net/url"
	"strings"
	"testing"
)

func TestStaticDependencyGraph(t *testing.T) {
	fixtures := map[string]string{
		"/style.css": `@import './theme.css'; .hero {background:url('./image.svg')}`,
		"/theme.css": `@font-face {src:url('./font.woff2')}`,
		"/app.js":    `import './lib.js'; fetch('/api/live');`,
		"/lib.js":    `export const icon=new URL('./image.svg',import.meta.url);`,
		"/image.svg": "<svg/>", "/font.woff2": "font",
	}
	calls := map[string]int{}
	fetch := func(_ context.Context, u *url.URL) ([]byte, string, error) {
		calls[u.Path]++
		s, ok := fixtures[u.Path]
		if !ok {
			return nil, "", fmt.Errorf("missing")
		}
		return []byte(s), "text/plain", nil
	}
	doc, assets, err := Build(context.Background(), `<base href="/"><link rel="stylesheet" href="style.css"><script type="module" src="app.js"></script><img src="image.svg"><img srcset="image.svg 1x, image.svg 2x"><video src="https://live.test/channel.m3u8"></video>`, "https://source.test/shares/a", fetch)
	if err != nil {
		t.Fatal(err)
	}
	if len(assets) != 6 {
		t.Fatalf("assets %d", len(assets))
	}
	for p, n := range calls {
		if n != 1 {
			t.Fatalf("duplicate fetch %s", p)
		}
	}
	if strings.Contains(doc, `href="style.css"`) || !strings.Contains(doc, Prefix) || !strings.Contains(doc, "https://live.test/channel.m3u8") {
		t.Fatal(doc)
	}
	for _, a := range assets {
		if strings.HasSuffix(a.Name, ".js") && strings.Contains(string(a.Data), "fetch") && !strings.Contains(string(a.Data), "fetch('/api/live')") {
			t.Fatal("runtime API rewritten")
		}
	}
}
func TestStaticDependencyFailureAndCycles(t *testing.T) {
	_, _, err := Build(context.Background(), `<img src="missing.png">`, "https://source.test/", func(context.Context, *url.URL) ([]byte, string, error) { return nil, "", fmt.Errorf("404") })
	if err == nil {
		t.Fatal("missing resource silently accepted")
	}
	_, assets, err := Build(context.Background(), `<link rel="stylesheet" href="a.css">`, "https://source.test/", func(_ context.Context, u *url.URL) ([]byte, string, error) {
		if u.Path == "/a.css" {
			return []byte(`@import 'b.css';`), "text/css", nil
		}
		return []byte(`@import 'a.css';`), "text/css", nil
	})
	if err != nil || len(assets) != 2 {
		t.Fatalf("cycle %d %v", len(assets), err)
	}
}

func TestDependencyExamplesAndCommentsAreNotFetched(t *testing.T) {
	source := `<style>/* url('missing.png') */ .x::after{content:"url('example.png')"}</style><script>// import './missing.js';
 const example="import './example.js'"; /* from './comment.js' */</script>`
	_, assets, err := Build(context.Background(), source, "https://source.test/", func(context.Context, *url.URL) ([]byte, string, error) {
		return nil, "", fmt.Errorf("should not fetch")
	})
	if err != nil || len(assets) != 0 {
		t.Fatalf("comment/example treated as a dependency: %v", err)
	}
}

func TestImportMapModulesAreLocalized(t *testing.T) {
	source := `<script type="importmap">{"imports":{"lib":"https://cdn.test/lib.js","pkg/":"https://cdn.test/pkg/"}}</script><script type="module">import {x} from 'lib'; import 'pkg/a.js';</script>`
	content, assets, err := Build(context.Background(), source, "https://source.test/", func(_ context.Context, u *url.URL) ([]byte, string, error) {
		return []byte(`export const x=1;`), "text/javascript", nil
	})
	if err != nil || len(assets) != 2 || strings.Contains(content, "from 'lib'") || strings.Contains(content, "import 'pkg/") {
		t.Fatalf("import map %s: %v", content, err)
	}
}
