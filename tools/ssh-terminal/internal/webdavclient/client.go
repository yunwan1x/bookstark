package webdavclient

import (
	"bytes"
	"context"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"net/url"
	"path"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

type Config struct {
	URL                string
	User               string
	Password           string
	BasePath           string
	InsecureSkipVerify bool
	DialContext        func(ctx context.Context, network, addr string) (net.Conn, error)
}

type Entry struct {
	Name    string `json:"name"`
	Path    string `json:"path"`
	IsDir   bool   `json:"isDir"`
	Size    int64  `json:"size"`
	Mode    string `json:"mode,omitempty"`
	ModTime int64  `json:"modTime"`
	Mime    string `json:"mime,omitempty"`
}

type Client struct {
	cfg       Config
	baseURL   *url.URL
	rootPath  string
	http      *http.Client
	transport *http.Transport
	nc        uint32
}

func New(cfg Config) (*Client, error) {
	raw := strings.TrimSpace(cfg.URL)
	if raw == "" {
		return nil, errors.New("WebDAV URL 不能为空")
	}
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil, errors.New("无效的 WebDAV 地址，请使用 http:// 或 https://")
	}
	u.Fragment = ""
	u.RawQuery = ""
	rootPath := cleanPath(u.Path)
	if strings.TrimSpace(cfg.BasePath) != "" {
		bp := cleanPath(cfg.BasePath)
		if bp != "/" {
			if rootPath == "/" {
				rootPath = bp
			} else if !strings.HasPrefix(bp, rootPath) {
				rootPath = cleanPath(rootPath + "/" + bp)
			} else {
				rootPath = bp
			}
		}
	}
	u.Path = rootPath
	tr := &http.Transport{
		DialContext:         cfg.DialContext,
		MaxIdleConns:        6,
		MaxIdleConnsPerHost: 4,
		IdleConnTimeout:     45 * time.Second,
		TLSHandshakeTimeout: 20 * time.Second,
		TLSClientConfig: &tls.Config{
			ServerName:         u.Hostname(),
			InsecureSkipVerify: cfg.InsecureSkipVerify,
		},
	}
	return &Client{
		cfg:       cfg,
		baseURL:   u,
		rootPath:  rootPath,
		transport: tr,
		http: &http.Client{
			Transport: tr,
			Timeout:   90 * time.Second,
		},
	}, nil
}

func (c *Client) Close() {
	if c.transport != nil {
		c.transport.CloseIdleConnections()
	}
}

func cleanPath(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return "/"
	}
	p = strings.ReplaceAll(p, "\\", "/")
	if !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	c := path.Clean(p)
	if c == "." || c == "" {
		return "/"
	}
	return c
}

// resolveURL builds the full target URL for a user-visible path relative to the WebDAV root.
func (c *Client) resolveURL(rel string, trailingSlash bool) string {
	rel = cleanPath(rel)
	full := c.rootPath
	if rel != "/" {
		if full == "/" {
			full = rel
		} else {
			full = strings.TrimSuffix(full, "/") + rel
		}
	}
	u := *c.baseURL
	u.Path = full
	if trailingSlash && !strings.HasSuffix(u.Path, "/") {
		u.Path += "/"
	}
	return u.String()
}

func (c *Client) do(ctx context.Context, method, targetURL string, headers map[string]string, bodyBytes []byte) (*http.Response, error) {
	makeReq := func(authHeader string) (*http.Request, error) {
		var body io.Reader
		if bodyBytes != nil {
			body = bytes.NewReader(bodyBytes)
		}
		req, err := http.NewRequestWithContext(ctx, method, targetURL, body)
		if err != nil {
			return nil, err
		}
		req.Header.Set("User-Agent", "BookStark-WebDAV/1.1")
		for k, v := range headers {
			req.Header.Set(k, v)
		}
		if authHeader != "" {
			req.Header.Set("Authorization", authHeader)
		} else if c.cfg.User != "" || c.cfg.Password != "" {
			req.SetBasicAuth(c.cfg.User, c.cfg.Password)
		}
		return req, nil
	}

	req, err := makeReq("")
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == http.StatusUnauthorized && (c.cfg.User != "" || c.cfg.Password != "") {
		chal := resp.Header.Get("WWW-Authenticate")
		if strings.HasPrefix(strings.ToLower(strings.TrimSpace(chal)), "digest ") {
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			u, _ := url.Parse(targetURL)
			uri := u.RequestURI()
			auth := c.buildDigestAuth(chal, method, uri)
			if auth != "" {
				req2, err := makeReq(auth)
				if err != nil {
					return nil, err
				}
				return c.http.Do(req2)
			}
		}
	}
	return resp, nil
}

func (c *Client) buildDigestAuth(header, method, uri string) string {
	params := parseDigestChallenge(header)
	realm := params["realm"]
	nonce := params["nonce"]
	if realm == "" || nonce == "" {
		return ""
	}
	alg := strings.ToUpper(params["algorithm"])
	hashFn := func(s string) string {
		if strings.HasPrefix(alg, "SHA-256") {
			sum := sha256.Sum256([]byte(s))
			return hex.EncodeToString(sum[:])
		}
		sum := md5.Sum([]byte(s))
		return hex.EncodeToString(sum[:])
	}
	ha1 := hashFn(fmt.Sprintf("%s:%s:%s", c.cfg.User, realm, c.cfg.Password))
	ha2 := hashFn(fmt.Sprintf("%s:%s", method, uri))
	qop := params["qop"]
	var respHash string
	var cnonce, ncStr string
	if qop != "" {
		chosenQop := "auth"
		for _, q := range strings.Split(qop, ",") {
			if strings.TrimSpace(q) == "auth" {
				chosenQop = "auth"
				break
			}
		}
		var rb [8]byte
		_, _ = rand.Read(rb[:])
		cnonce = hex.EncodeToString(rb[:])
		nc := atomic.AddUint32(&c.nc, 1)
		ncStr = fmt.Sprintf("%08x", nc)
		respHash = hashFn(fmt.Sprintf("%s:%s:%s:%s:%s:%s", ha1, nonce, ncStr, cnonce, chosenQop, ha2))
		parts := []string{
			fmt.Sprintf(`username="%s"`, escapeQuoted(c.cfg.User)),
			fmt.Sprintf(`realm="%s"`, escapeQuoted(realm)),
			fmt.Sprintf(`nonce="%s"`, escapeQuoted(nonce)),
			fmt.Sprintf(`uri="%s"`, escapeQuoted(uri)),
			fmt.Sprintf(`qop=%s`, chosenQop),
			fmt.Sprintf(`nc=%s`, ncStr),
			fmt.Sprintf(`cnonce="%s"`, cnonce),
			fmt.Sprintf(`response="%s"`, respHash),
		}
		if opaque := params["opaque"]; opaque != "" {
			parts = append(parts, fmt.Sprintf(`opaque="%s"`, escapeQuoted(opaque)))
		}
		if alg != "" {
			parts = append(parts, fmt.Sprintf(`algorithm=%s`, alg))
		}
		return "Digest " + strings.Join(parts, ", ")
	}
	respHash = hashFn(fmt.Sprintf("%s:%s:%s", ha1, nonce, ha2))
	parts := []string{
		fmt.Sprintf(`username="%s"`, escapeQuoted(c.cfg.User)),
		fmt.Sprintf(`realm="%s"`, escapeQuoted(realm)),
		fmt.Sprintf(`nonce="%s"`, escapeQuoted(nonce)),
		fmt.Sprintf(`uri="%s"`, escapeQuoted(uri)),
		fmt.Sprintf(`response="%s"`, respHash),
	}
	if opaque := params["opaque"]; opaque != "" {
		parts = append(parts, fmt.Sprintf(`opaque="%s"`, escapeQuoted(opaque)))
	}
	return "Digest " + strings.Join(parts, ", ")
}

func escapeQuoted(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, `\`, `\\`), `"`, `\"`)
}

func parseDigestChallenge(h string) map[string]string {
	out := map[string]string{}
	idx := strings.Index(strings.ToLower(h), "digest ")
	if idx < 0 {
		return out
	}
	rest := strings.TrimSpace(h[idx+7:])
	for len(rest) > 0 {
		eq := strings.IndexByte(rest, '=')
		if eq < 0 {
			break
		}
		k := strings.ToLower(strings.TrimSpace(rest[:eq]))
		rest = strings.TrimSpace(rest[eq+1:])
		var v string
		if strings.HasPrefix(rest, `"`) {
			rest = rest[1:]
			var sb strings.Builder
			escaped := false
			i := 0
			for ; i < len(rest); i++ {
				ch := rest[i]
				if escaped {
					sb.WriteByte(ch)
					escaped = false
					continue
				}
				if ch == '\\' {
					escaped = true
					continue
				}
				if ch == '"' {
					i++
					break
				}
				sb.WriteByte(ch)
			}
			v = sb.String()
			rest = strings.TrimLeft(rest[i:], ", ")
		} else {
			comma := strings.IndexByte(rest, ',')
			if comma < 0 {
				v = strings.TrimSpace(rest)
				rest = ""
			} else {
				v = strings.TrimSpace(rest[:comma])
				rest = strings.TrimSpace(rest[comma+1:])
			}
		}
		out[k] = v
	}
	return out
}

const propfindBody = `<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:getcontenttype/>
  </d:prop>
</d:propfind>`

type multistatus struct {
	Responses []davResponse `xml:"response"`
}

type davResponse struct {
	Href      string        `xml:"href"`
	Propstats []davPropstat `xml:"propstat"`
}

type davPropstat struct {
	Status string   `xml:"status"`
	Prop   davProps `xml:"prop"`
}

type davProps struct {
	DisplayName   string          `xml:"displayname"`
	ResourceType  davResourceType `xml:"resourcetype"`
	ContentLength string          `xml:"getcontentlength"`
	LastModified  string          `xml:"getlastmodified"`
	ContentType   string          `xml:"getcontenttype"`
}

type davResourceType struct {
	Collection *struct{} `xml:"collection"`
}

func (c *Client) List(ctx context.Context, relPath string) (string, []Entry, error) {
	cwd := cleanPath(relPath)
	target := c.resolveURL(cwd, true)
	resp, err := c.do(ctx, "PROPFIND", target, map[string]string{
		"Depth":        "1",
		"Content-Type": "application/xml; charset=utf-8",
	}, []byte(propfindBody))
	if err != nil {
		return cwd, nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return cwd, nil, fmt.Errorf("认证失败（HTTP %d），请检查用户名和密码", resp.StatusCode)
	}
	if resp.StatusCode == http.StatusNotFound {
		return cwd, nil, fmt.Errorf("目录不存在：%s", cwd)
	}
	if resp.StatusCode != http.StatusMultiStatus && (resp.StatusCode < 200 || resp.StatusCode >= 300) {
		return cwd, nil, fmt.Errorf("WebDAV 请求失败（HTTP %d）", resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8*1024*1024))
	if err != nil {
		return cwd, nil, err
	}
	var ms multistatus
	if err := xml.Unmarshal(raw, &ms); err != nil {
		return cwd, nil, fmt.Errorf("解析 WebDAV 目录失败：%w", err)
	}

	reqFull := strings.TrimSuffix(cleanPath(c.fullPath(cwd)), "/")
	rootClean := strings.TrimSuffix(c.rootPath, "/")
	entries := make([]Entry, 0, len(ms.Responses))
	seen := map[string]bool{}

	for _, r := range ms.Responses {
		hrefPath := extractHrefPath(r.Href)
		hrefClean := strings.TrimSuffix(cleanPath(hrefPath), "/")
		if hrefClean == reqFull || hrefClean == "" && reqFull == "" {
			continue
		}
		// Compute relative path under rootPath
		rel := hrefClean
		if rootClean != "" && rootClean != "/" {
			if strings.HasPrefix(hrefClean, rootClean+"/") {
				rel = hrefClean[len(rootClean):]
			} else if hrefClean == rootClean {
				continue
			}
		}
		rel = cleanPath(rel)
		if rel == cwd || seen[rel] {
			continue
		}
		seen[rel] = true

		props := pickOKProps(r.Propstats)
		isDir := props.ResourceType.Collection != nil || strings.HasSuffix(r.Href, "/")
		name := path.Base(rel)
		if name == "" || name == "/" || name == "." {
			if props.DisplayName != "" {
				name = props.DisplayName
			} else {
				continue
			}
		}
		size, _ := strconv.ParseInt(strings.TrimSpace(props.ContentLength), 10, 64)
		var modUnix int64
		if lm := strings.TrimSpace(props.LastModified); lm != "" {
			if t, err := http.ParseTime(lm); err == nil {
				modUnix = t.Unix()
			} else if t, err := time.Parse(time.RFC3339, lm); err == nil {
				modUnix = t.Unix()
			}
		}
		mt := strings.TrimSpace(props.ContentType)
		if !isDir && mt == "" {
			mt = mime.TypeByExtension(path.Ext(name))
		}
		entries = append(entries, Entry{
			Name:    name,
			Path:    rel,
			IsDir:   isDir,
			Size:    size,
			ModTime: modUnix,
			Mime:    mt,
		})
	}

	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir != entries[j].IsDir {
			return entries[i].IsDir
		}
		return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
	})
	return cwd, entries, nil
}

func (c *Client) fullPath(rel string) string {
	rel = cleanPath(rel)
	if c.rootPath == "/" {
		return rel
	}
	if rel == "/" {
		return c.rootPath
	}
	return strings.TrimSuffix(c.rootPath, "/") + rel
}

func extractHrefPath(href string) string {
	href = strings.TrimSpace(href)
	if u, err := url.Parse(href); err == nil && u.Path != "" {
		if decoded, err := url.PathUnescape(u.Path); err == nil {
			return decoded
		}
		return u.Path
	}
	if decoded, err := url.PathUnescape(href); err == nil {
		return decoded
	}
	return href
}

func pickOKProps(list []davPropstat) davProps {
	for _, ps := range list {
		if strings.Contains(ps.Status, " 200") || ps.Status == "" {
			return ps.Prop
		}
	}
	if len(list) > 0 {
		return list[0].Prop
	}
	return davProps{}
}

func (c *Client) Read(ctx context.Context, relPath string, maxBytes int64, onProgress func(done, total int64)) ([]byte, int64, bool, error) {
	target := c.resolveURL(relPath, false)
	resp, err := c.do(ctx, "GET", target, nil, nil)
	if err != nil {
		return nil, 0, false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, 0, false, fmt.Errorf("读取文件失败（HTTP %d）", resp.StatusCode)
	}
	total := resp.ContentLength
	var buf bytes.Buffer
	chunk := make([]byte, 32*1024)
	var done int64
	truncated := false
	for {
		n, rerr := resp.Body.Read(chunk)
		if n > 0 {
			if maxBytes > 0 && done+int64(n) > maxBytes {
				remain := maxBytes - done
				if remain > 0 {
					buf.Write(chunk[:remain])
					done += remain
				}
				truncated = true
				break
			}
			buf.Write(chunk[:n])
			done += int64(n)
			if onProgress != nil {
				onProgress(done, total)
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return nil, done, truncated, rerr
		}
	}
	if total < 0 {
		total = done
	}
	return buf.Bytes(), total, truncated, nil
}

func (c *Client) Write(ctx context.Context, relPath string, data []byte, onProgress func(done, total int64)) error {
	target := c.resolveURL(relPath, false)
	total := int64(len(data))
	if onProgress != nil {
		onProgress(0, total)
	}
	resp, err := c.do(ctx, "PUT", target, map[string]string{
		"Content-Type": "application/octet-stream",
	}, data)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("写入文件失败（HTTP %d）", resp.StatusCode)
	}
	if onProgress != nil {
		onProgress(total, total)
	}
	return nil
}

func (c *Client) Mkdir(ctx context.Context, relPath string) error {
	target := c.resolveURL(relPath, true)
	resp, err := c.do(ctx, "MKCOL", target, nil, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("创建目录失败（HTTP %d）", resp.StatusCode)
	}
	return nil
}

func (c *Client) Rename(ctx context.Context, fromPath, toPath string) error {
	src := c.resolveURL(fromPath, false)
	dst := c.resolveURL(toPath, false)
	resp, err := c.do(ctx, "MOVE", src, map[string]string{
		"Destination": dst,
		"Overwrite":   "T",
	}, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("重命名/移动失败（HTTP %d）", resp.StatusCode)
	}
	return nil
}

func (c *Client) Delete(ctx context.Context, relPath string) error {
	target := c.resolveURL(relPath, false)
	resp, err := c.do(ctx, "DELETE", target, nil, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("删除失败（HTTP %d）", resp.StatusCode)
	}
	return nil
}
