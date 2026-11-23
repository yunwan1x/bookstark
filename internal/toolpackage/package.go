// Package toolpackage localizes static dependencies without fetching runtime APIs.
package toolpackage

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/url"
	"path"
	"regexp"
	"strings"

	"golang.org/x/net/html"
)

const Prefix = "__BOOKSTARK_TOOL_ASSETS__/"
const MaxBytes = 100 << 20
const MaxFile = 20 << 20
const MaxFiles = 256

type Asset struct {
	Name, MIME string
	Data       []byte
}
type Fetch func(context.Context, *url.URL) ([]byte, string, error)
type builder struct {
	ctx     context.Context
	fetch   Fetch
	seen    map[string]string
	assets  []Asset
	size    int
	imports map[string]string
}

func Build(ctx context.Context, content, base string, fetch Fetch) (string, []Asset, error) {
	u, err := url.Parse(base)
	if err != nil {
		return "", nil, err
	}
	b := &builder{ctx: ctx, fetch: fetch, seen: map[string]string{}, imports: map[string]string{}}
	doc, err := html.Parse(strings.NewReader(content))
	if err != nil {
		return "", nil, err
	}
	// Honor the original base before removing it from the installed document.
	var findBase func(*html.Node)
	findBase = func(n *html.Node) {
		if n.Type == html.ElementNode && n.Data == "base" {
			for _, a := range n.Attr {
				if a.Key == "href" {
					if v, e := url.Parse(a.Val); e == nil {
						u = u.ResolveReference(v)
					}
					return
				}
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			findBase(c)
		}
	}
	findBase(doc)
	var collectImports func(*html.Node) error
	collectImports = func(n *html.Node) error {
		if isImportMap(n) {
			for c := n.FirstChild; c != nil; c = c.NextSibling {
				if c.Type == html.TextNode {
					var mapping struct {
						Imports map[string]string `json:"imports"`
						Scopes  map[string]any    `json:"scopes"`
					}
					if err := json.Unmarshal([]byte(c.Data), &mapping); err != nil {
						return err
					}
					if len(mapping.Scopes) > 0 {
						return fmt.Errorf("scoped import maps require explicit module URLs")
					}
					for k, v := range mapping.Imports {
						parsed, err := url.Parse(v)
						if err != nil {
							return err
						}
						b.imports[k] = u.ResolveReference(parsed).String()
					}
				}
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			if err := collectImports(c); err != nil {
				return err
			}
		}
		return nil
	}
	if err = collectImports(doc); err != nil {
		return "", nil, err
	}

	err = b.walk(doc, u)
	if err != nil {
		return "", nil, err
	}
	var out bytes.Buffer
	err = html.Render(&out, doc)
	return out.String(), b.assets, err
}

func (b *builder) asset(raw string, base *url.URL) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" || strings.HasPrefix(raw, "#") {
		return raw, nil
	}
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	u = base.ResolveReference(u)
	if u.Scheme == "data" || u.Scheme == "blob" {
		return raw, nil
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return "", fmt.Errorf("unsupported resource scheme")
	}
	fragment := u.Fragment
	u.Fragment = ""
	key := u.String()
	ext := strings.ToLower(path.Ext(u.Path))
	// Streaming endpoints are services, not downloadable static assets.
	if ext == ".m3u8" || ext == ".mpd" {
		return u.String(), nil
	}
	if name, ok := b.seen[key]; ok {
		if fragment != "" {
			name += "#" + fragment
		}
		return name, nil
	}
	if len(b.seen) >= MaxFiles {
		return "", fmt.Errorf("too many tool resources")
	}
	if len(ext) > 12 {
		ext = ""
	}
	name := fmt.Sprintf("%x%s", sha256.Sum256([]byte(key)), ext)
	local := Prefix + name
	b.seen[key] = local
	data, mime, err := b.fetch(b.ctx, u)
	if err != nil {
		return "", fmt.Errorf("resource %s: %w", u.Redacted(), err)
	}
	b.size += len(data)
	if len(data) > MaxFile || b.size > MaxBytes {
		return "", fmt.Errorf("tool resources too large")
	}
	if ext == ".css" || strings.Contains(mime, "text/css") {
		s, e := b.css(string(data), u)
		if e != nil {
			return "", e
		}
		data = []byte(s)
	}
	if ext == ".js" || ext == ".mjs" || strings.Contains(mime, "javascript") {
		s, e := b.modules(string(data), u)
		if e != nil {
			return "", e
		}
		data = []byte(s)
	}
	b.assets = append(b.assets, Asset{name, mime, data})
	if fragment != "" {
		local += "#" + fragment
	}
	return local, nil
}

var cssRefs = regexp.MustCompile(`(?i)url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)]*))\s*\)|@import\s+(?:"([^"]*)"|'([^']*)')`)
var moduleRefs = regexp.MustCompile(`(?:\bfrom\s*|\bimport\s*\(?\s*|new\s+URL\(\s*)["']([^"'\r\n]+)["']`)

// Literal/comment masking prevents example code and commented dependencies from being fetched.
func codeMask(s string, js bool) []bool {
	mask := make([]bool, len(s))
	for i := 0; i < len(s); {
		if i+1 < len(s) && s[i:i+2] == "/*" {
			end := strings.Index(s[i+2:], "*/")
			if end < 0 {
				break
			}
			i += end + 4
			continue
		}
		if js && i+1 < len(s) && s[i:i+2] == "//" {
			end := strings.IndexByte(s[i:], '\n')
			if end < 0 {
				break
			}
			i += end
			continue
		}
		if s[i] == '\'' || s[i] == '"' || (js && s[i] == '`') {
			quote := s[i]
			i++
			for i < len(s) {
				if s[i] == '\\' {
					i += 2
					continue
				}
				if s[i] == quote {
					i++
					break
				}
				i++
			}
			continue
		}
		mask[i] = true
		i++
	}
	return mask
}
func (b *builder) rewrite(s string, base *url.URL, re *regexp.Regexp, css bool) (string, error) {
	mask := codeMask(s, !css)
	var out strings.Builder
	last := 0
	for _, indices := range re.FindAllStringSubmatchIndex(s, -1) {
		start, end := indices[0], indices[1]
		if !mask[start] {
			continue
		}
		raw := ""
		rawStart, rawEnd := 0, 0
		for j := 2; j < len(indices); j += 2 {
			if indices[j] >= 0 && indices[j+1] > indices[j] {
				rawStart, rawEnd = indices[j], indices[j+1]
				raw = s[rawStart:rawEnd]
				break
			}
		}
		if !css && !strings.HasPrefix(raw, ".") && !strings.HasPrefix(raw, "/") && !strings.HasPrefix(raw, "http") {
			if mapped, ok := b.imports[raw]; ok {
				raw = mapped
			} else {
				key := ""
				for k := range b.imports {
					if strings.HasSuffix(k, "/") && strings.HasPrefix(raw, k) && len(k) > len(key) {
						key = k
					}
				}
				if key == "" {
					continue
				}
				raw = b.imports[key] + strings.TrimPrefix(raw, key)
			}
		}
		if strings.Contains(raw, "\\") {
			return "", fmt.Errorf("escaped resource URL is not supported")
		}
		value, err := b.asset(raw, base)
		if err != nil {
			return "", err
		}
		out.WriteString(s[last:start])
		out.WriteString(s[start:rawStart])
		out.WriteString(value)
		out.WriteString(s[rawEnd:end])
		last = end
	}
	out.WriteString(s[last:])
	return out.String(), nil
}
func (b *builder) css(s string, base *url.URL) (string, error) {
	return b.rewrite(s, base, cssRefs, true)
}
func (b *builder) modules(s string, base *url.URL) (string, error) {
	return b.rewrite(s, base, moduleRefs, false)
}
func (b *builder) walk(n *html.Node, base *url.URL) error {
	if n.Type == html.ElementNode {
		if n.Data == "base" {
			n.Attr = nil
			return nil
		}
		for i := range n.Attr {
			a := &n.Attr[i]
			var err error
			if a.Key == "style" {
				a.Val, err = b.css(a.Val, base)
			}
			static := a.Key == "poster" || (a.Key == "src" && (n.Data == "script" || n.Data == "img" || n.Data == "source" || n.Data == "video" || n.Data == "audio" || n.Data == "track"))
			if n.Data == "link" && a.Key == "href" {
				for _, r := range n.Attr {
					if r.Key == "rel" && (strings.Contains(r.Val, "stylesheet") || strings.Contains(r.Val, "icon") || strings.Contains(r.Val, "preload")) {
						static = true
					}
				}
			}
			if static {
				a.Val, err = b.asset(a.Val, base)
			}
			if a.Key == "srcset" && !strings.Contains(a.Val, "data:") {
				parts := strings.Split(a.Val, ",")
				for j, p := range parts {
					fields := strings.Fields(p)
					if len(fields) > 0 {
						fields[0], err = b.asset(fields[0], base)
						if err != nil {
							return err
						}
						parts[j] = strings.Join(fields, " ")
					}
				}
				a.Val = strings.Join(parts, ", ")
			}
			if err != nil {
				return err
			}
		}
		// Rewritten CSS/modules no longer match the author's integrity digest.
		attrs := n.Attr[:0]
		for _, a := range n.Attr {
			if a.Key != "integrity" {
				attrs = append(attrs, a)
			}
		}
		n.Attr = attrs
		if n.Data == "style" || n.Data == "script" {
			for c := n.FirstChild; c != nil; c = c.NextSibling {
				if c.Type == html.TextNode {
					var err error
					if isImportMap(n) {
						imports := map[string]string{}
						for k, v := range b.imports {
							if strings.HasSuffix(k, "/") {
								imports[k] = v
								continue
							}
							imports[k], err = b.asset(v, base)
							if err != nil {
								return err
							}
						}
						data, e := json.Marshal(map[string]any{"imports": imports})
						err = e
						c.Data = string(data)
					} else if n.Data == "style" {
						c.Data, err = b.css(c.Data, base)
					} else {
						c.Data, err = b.modules(c.Data, base)
					}
					if err != nil {
						return err
					}
				}
			}
		}
	}
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		if err := b.walk(c, base); err != nil {
			return err
		}
	}
	return nil
}

func isImportMap(n *html.Node) bool {
	if n.Type != html.ElementNode || n.Data != "script" {
		return false
	}
	for _, a := range n.Attr {
		if a.Key == "type" && a.Val == "importmap" {
			return true
		}
	}
	return false
}
