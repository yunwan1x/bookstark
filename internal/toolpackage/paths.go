package toolpackage

import (
	"bytes"
	"golang.org/x/net/html"
	"net/url"
	"path"
	"regexp"
	"strings"
)

var rootResourceLiteral = regexp.MustCompile("[\"'`](/[^\"'`\\r\\n]+)[\"'`]")

// RewriteArchiveRoots relocates only root URLs naming a file actually present
// in the archive. Runtime API endpoints and external services remain untouched.
var rootCSSResource = regexp.MustCompile(`url\(\s*(/[^\s)]+)\s*\)`)

func RewriteArchiveRoots(s string, names map[string]bool) string {
	s = rootCSSResource.ReplaceAllStringFunc(s, func(match string) string {
		raw := rootCSSResource.FindStringSubmatch(match)[1]
		u, err := url.Parse(raw)
		if err != nil || u.Host != "" || !names[strings.TrimPrefix(u.Path, "/")] {
			return match
		}
		return "url(" + Prefix + strings.TrimPrefix(raw, "/") + ")"
	})
	return rootResourceLiteral.ReplaceAllStringFunc(s, func(match string) string {
		raw := match[1 : len(match)-1]
		u, err := url.Parse(raw)
		if err != nil || u.Host != "" || !names[strings.TrimPrefix(u.Path, "/")] {
			return match
		}
		return match[:1] + Prefix + strings.TrimPrefix(raw, "/") + match[len(match)-1:]
	})
}

// Rewriting a bundled script invalidates the author's original SRI digest.
func StripArchiveIntegrity(s, entry string, names map[string]bool) (string, error) {
	doc, err := html.Parse(strings.NewReader(s))
	if err != nil {
		return "", err
	}
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		local := false
		for _, a := range n.Attr {
			if a.Key == "src" || a.Key == "href" {
				u, e := url.Parse(a.Val)
				if e == nil && u.Scheme == "" && u.Host == "" {
					name := strings.TrimPrefix(u.Path, "/")
					if !strings.HasPrefix(u.Path, "/") {
						name = path.Join(path.Dir(entry), u.Path)
					}
					local = names[name]
				}
			}
		}
		if local {
			attrs := n.Attr[:0]
			for _, a := range n.Attr {
				if a.Key != "integrity" {
					attrs = append(attrs, a)
				}
			}
			n.Attr = attrs
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)
	var out bytes.Buffer
	err = html.Render(&out, doc)
	return out.String(), err
}
