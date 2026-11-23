package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// Resource requests never forward cookies, credentials, or arbitrary local paths.
func toolHTTPClient() *http.Client {
	return &http.Client{Timeout: 45 * time.Second, Transport: &http.Transport{Proxy: nil, DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		host, port, err := net.SplitHostPort(address)
		if err != nil {
			return nil, err
		}
		ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		if err != nil {
			return nil, err
		}
		if len(ips) == 0 {
			return nil, fmt.Errorf("no resource address")
		}
		for _, ip := range ips {
			if !ip.IP.IsGlobalUnicast() || !isPublicIP(ip.IP) {
				return nil, fmt.Errorf("private resource address blocked")
			}
		}
		return (&net.Dialer{Timeout: 10 * time.Second}).DialContext(ctx, network, net.JoinHostPort(ips[0].IP.String(), port))
	}}, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return fmt.Errorf("too many redirects")
		}
		if req.URL.Scheme != "https" && req.URL.Scheme != "http" {
			return fmt.Errorf("invalid redirect")
		}
		return nil
	}}
}

var toolClientFactory = toolHTTPClient

func fetchToolURL(ctx context.Context, u *url.URL) ([]byte, string, error) {
	if u.User != nil || (u.Scheme != "https" && u.Scheme != "http") {
		return nil, "", fmt.Errorf("invalid resource URL")
	}
	req, err := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	if err != nil {
		return nil, "", err
	}
	client := toolClientFactory()
	defer client.CloseIdleConnections()
	resp, err := client.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, "", fmt.Errorf("resource returned %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, toolpackage.MaxFile+1))
	if len(data) > toolpackage.MaxFile {
		return nil, "", fmt.Errorf("resource too large")
	}
	return data, resp.Header.Get("Content-Type"), err
}

func publicToolResourcePath(p string) bool {
	if path.Clean(p) != p || strings.Contains(p, "\\") {
		return false
	}
	return strings.HasPrefix(p, "/dav-public/") || strings.HasPrefix(p, "/upload-files/") || strings.HasPrefix(p, "/static/")
}

// A configured LAN marketplace can also serve its public static resources.
// No marketplace/workspace credentials are sent, and redirects cannot escape
// the explicitly configured origin or the public resource handlers.
func marketResourceFetch(origin string) toolpackage.Fetch {
	return func(ctx context.Context, u *url.URL) ([]byte, string, error) {
		if u.Scheme+"://"+u.Host != origin {
			return fetchToolURL(ctx, u)
		}
		if u.User != nil || !publicToolResourcePath(u.Path) {
			return nil, "", fmt.Errorf("not a public market resource")
		}
		client := marketplaceHTTPClient()
		defer client.CloseIdleConnections()
		client.CheckRedirect = func(r *http.Request, via []*http.Request) error { return http.ErrUseLastResponse }
		req, err := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
		if err != nil {
			return nil, "", err
		}
		response, err := client.Do(req)
		if err != nil {
			return nil, "", err
		}
		defer response.Body.Close()
		if response.StatusCode != 200 {
			return nil, "", fmt.Errorf("resource returned %d", response.StatusCode)
		}
		data, err := io.ReadAll(io.LimitReader(response.Body, toolpackage.MaxFile+1))
		if len(data) > toolpackage.MaxFile {
			return nil, "", fmt.Errorf("resource too large")
		}
		return data, response.Header.Get("Content-Type"), err
	}
}

// Local public resources are read through the same public handlers, without loopback networking.
func localToolFetch(router http.Handler, origin string) toolpackage.Fetch {
	return func(ctx context.Context, u *url.URL) ([]byte, string, error) {
		if !strings.HasSuffix(origin, "://"+u.Host) {
			return fetchToolURL(ctx, u)
		}
		if !publicToolResourcePath(u.Path) {
			return nil, "", fmt.Errorf("not a public static resource")
		}
		req := httptest.NewRequest("GET", u.String(), nil).WithContext(ctx)
		w := &toolResourceResponse{headers: make(http.Header), code: 200}
		router.ServeHTTP(w, req)
		if w.code != 200 {
			return nil, "", fmt.Errorf("resource returned %d", w.code)
		}
		if w.overflow {
			return nil, "", fmt.Errorf("resource too large")
		}
		return w.body.Bytes(), w.Header().Get("Content-Type"), nil
	}
}
func requestToolOrigin(c *gin.Context) string {
	scheme := "http"
	if c.Request.TLS != nil {
		scheme = "https"
	}
	return scheme + "://" + c.Request.Host
}

// An unguessable installation/epoch pair grants read access only to that asset set.
// Sandbox/CORS headers also allow module scripts in the opaque tool iframe.
func ServeToolAsset(c *gin.Context) {
	instance, epoch := c.Param("instance"), c.Param("epoch")
	if len(instance) != 32 || len(epoch) != 32 {
		c.Status(404)
		return
	}
	var member int64
	var root string
	err := models.DB.QueryRow("SELECT member_id,assets FROM md_tool_installs WHERE instance=? AND assets=?", instance, "/BookStark/tools/"+instance+"/assets/"+epoch).Scan(&member, &root)
	if err != nil {
		c.Status(404)
		return
	}
	p, err := models.ToolResourcePath(&models.InstalledTool{Assets: root}, "assets", c.Param("filepath"))
	if err != nil {
		c.Status(404)
		return
	}
	node, blob, reader, err := models.ReadDAVFileContext(c.Request.Context(), member, p)
	if err != nil {
		c.Status(404)
		return
	}
	defer reader.Close()
	c.Header("Cache-Control", "no-store")
	c.Header("Access-Control-Allow-Origin", "*")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Content-Security-Policy", "sandbox allow-scripts")
	c.Header("Referrer-Policy", "no-referrer")
	c.DataFromReader(200, blob.OriginalSize, node.MIMEType, reader, nil)
}

// Bound local reads as well as network reads, including streamed WebDAV files.
type toolResourceResponse struct {
	headers  http.Header
	code     int
	body     bytes.Buffer
	overflow bool
}

func (w *toolResourceResponse) Header() http.Header  { return w.headers }
func (w *toolResourceResponse) WriteHeader(code int) { w.code = code }
func (w *toolResourceResponse) Write(p []byte) (int, error) {
	if w.body.Len()+len(p) > toolpackage.MaxFile {
		w.overflow = true
		return 0, fmt.Errorf("resource too large")
	}
	return w.body.Write(p)
}
