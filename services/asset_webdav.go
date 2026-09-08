package services

import (
	"encoding/xml"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"path"
	"strconv"
	"strings"
	"time"

	"bookstark/models"
)

type AssetWebDAVManager struct {
	Timeout time.Duration
}

type AssetWebDAVReadStream struct {
	Body       io.ReadCloser
	Header     http.Header
	StatusCode int
}

type webDAVMultistatus struct {
	Responses []webDAVResponse `xml:"response"`
}

type webDAVResponse struct {
	Href     string           `xml:"href"`
	Propstat []webDAVPropstat `xml:"propstat"`
}

type webDAVPropstat struct {
	Status string     `xml:"status"`
	Prop   webDAVProp `xml:"prop"`
}

type webDAVProp struct {
	DisplayName      string             `xml:"displayname"`
	GetContentLength string             `xml:"getcontentlength"`
	GetLastModified  string             `xml:"getlastmodified"`
	ResourceType     webDAVResourceType `xml:"resourcetype"`
}

type webDAVResourceType struct {
	Collection []struct{} `xml:"collection"`
}

func (m AssetWebDAVManager) Test(server *models.AssetWebDAVServer, credential string) error {
	_, err := m.List(server, credential, ".")
	return err
}

func (m AssetWebDAVManager) List(server *models.AssetWebDAVServer, credential, remotePath string) ([]AssetFileEntry, error) {
	reqURL, relPath, err := m.resourceURL(server, remotePath)
	if err != nil {
		return nil, err
	}
	body := strings.NewReader(`<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>`)
	req, err := http.NewRequest("PROPFIND", reqURL, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Depth", "1")
	req.Header.Set("Content-Type", "application/xml; charset=utf-8")
	m.applyAuth(req, server, credential)
	resp, err := m.client().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("WebDAV PROPFIND failed: %s", resp.Status)
	}
	var data webDAVMultistatus
	if err := xml.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil, fmt.Errorf("parse WebDAV response: %w", err)
	}
	baseURLPath, err := m.webDAVURLPath(server, relPath)
	if err != nil {
		return nil, err
	}
	result := make([]AssetFileEntry, 0, len(data.Responses))
	seen := map[string]bool{}
	for _, item := range data.Responses {
		entry, ok := webDAVResponseEntry(item, baseURLPath, relPath)
		if !ok {
			continue
		}
		if seen[entry.Path] {
			continue
		}
		seen[entry.Path] = true
		result = append(result, entry)
	}
	return result, nil
}

func (m AssetWebDAVManager) Download(server *models.AssetWebDAVServer, credential, remotePath string, w io.Writer) error {
	return m.requestBodyToWriter(http.MethodGet, server, credential, remotePath, nil, w)
}

func (m AssetWebDAVManager) OpenReadStream(server *models.AssetWebDAVServer, credential, remotePath, rangeHeader string) (*AssetWebDAVReadStream, error) {
	reqURL, _, err := m.resourceURL(server, remotePath)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(rangeHeader) != "" {
		req.Header.Set("Range", strings.TrimSpace(rangeHeader))
	}
	m.applyAuth(req, server, credential)
	resp, err := m.streamClient().Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		status := resp.Status
		_ = resp.Body.Close()
		return nil, fmt.Errorf("WebDAV GET failed: %s", status)
	}
	return &AssetWebDAVReadStream{
		Body:       resp.Body,
		Header:     resp.Header,
		StatusCode: resp.StatusCode,
	}, nil
}

func (m AssetWebDAVManager) Upload(server *models.AssetWebDAVServer, credential, remotePath string, r io.Reader) error {
	return m.requestNoBody(http.MethodPut, server, credential, remotePath, r)
}

func (m AssetWebDAVManager) Mkdir(server *models.AssetWebDAVServer, credential, remotePath string) error {
	return m.requestNoBody("MKCOL", server, credential, remotePath, nil)
}

func (m AssetWebDAVManager) Rename(server *models.AssetWebDAVServer, credential, oldPath, newPath string) error {
	return m.requestWithDestination("MOVE", server, credential, oldPath, newPath)
}

func (m AssetWebDAVManager) Copy(server *models.AssetWebDAVServer, credential, srcPath, dstPath string) error {
	return m.requestWithDestination("COPY", server, credential, srcPath, dstPath)
}

func (m AssetWebDAVManager) Remove(server *models.AssetWebDAVServer, credential, remotePath string, recursive bool) error {
	return m.requestNoBody(http.MethodDelete, server, credential, remotePath, nil)
}

func (m AssetWebDAVManager) requestBodyToWriter(method string, server *models.AssetWebDAVServer, credential, remotePath string, body io.Reader, w io.Writer) error {
	reqURL, _, err := m.resourceURL(server, remotePath)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(method, reqURL, body)
	if err != nil {
		return err
	}
	m.applyAuth(req, server, credential)
	resp, err := m.client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("WebDAV %s failed: %s", method, resp.Status)
	}
	_, err = io.Copy(w, resp.Body)
	return err
}

func (m AssetWebDAVManager) requestNoBody(method string, server *models.AssetWebDAVServer, credential, remotePath string, body io.Reader) error {
	reqURL, _, err := m.resourceURL(server, remotePath)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(method, reqURL, body)
	if err != nil {
		return err
	}
	m.applyAuth(req, server, credential)
	resp, err := m.client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("WebDAV %s failed: %s", method, resp.Status)
	}
	return nil
}

func (m AssetWebDAVManager) requestWithDestination(method string, server *models.AssetWebDAVServer, credential, srcPath, dstPath string) error {
	reqURL, _, err := m.resourceURL(server, srcPath)
	if err != nil {
		return err
	}
	dstURL, _, err := m.resourceURL(server, dstPath)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(method, reqURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Destination", dstURL)
	req.Header.Set("Overwrite", "T")
	m.applyAuth(req, server, credential)
	resp, err := m.client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("WebDAV %s failed: %s", method, resp.Status)
	}
	return nil
}

func (m AssetWebDAVManager) resourceURL(server *models.AssetWebDAVServer, remotePath string) (string, string, error) {
	u, err := parseWebDAVBaseURL(server.URL)
	if err != nil {
		return "", "", err
	}
	relPath := normalizeWebDAVRelativePath(remotePath)
	urlPath, err := m.webDAVURLPath(server, relPath)
	if err != nil {
		return "", "", err
	}
	u.Path = urlPath
	return u.String(), relPath, nil
}

func (m AssetWebDAVManager) webDAVURLPath(server *models.AssetWebDAVServer, relPath string) (string, error) {
	u, err := parseWebDAVBaseURL(server.URL)
	if err != nil {
		return "", err
	}
	rootPath := normalizeWebDAVRootPath(server.RootPath)
	parts := []string{u.Path, rootPath}
	if relPath != "." {
		parts = append(parts, relPath)
	}
	joined := cleanURLPath(parts...)
	if joined == "" {
		return "/", nil
	}
	return joined, nil
}

func (m AssetWebDAVManager) applyAuth(req *http.Request, server *models.AssetWebDAVServer, credential string) {
	if server.Username != "" || credential != "" {
		req.SetBasicAuth(server.Username, credential)
	}
}

func (m AssetWebDAVManager) client() *http.Client {
	timeout := m.Timeout
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	return &http.Client{Timeout: timeout}
}

func (m AssetWebDAVManager) streamClient() *http.Client {
	timeout := m.Timeout
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	return &http.Client{
		Transport: &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			DialContext: (&net.Dialer{
				Timeout:   timeout,
				KeepAlive: 30 * time.Second,
			}).DialContext,
			ResponseHeaderTimeout: timeout,
		},
	}
}

func parseWebDAVBaseURL(value string) (*url.URL, error) {
	u, err := url.Parse(strings.TrimSpace(value))
	if err != nil {
		return nil, fmt.Errorf("WebDAV URL 无效")
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return nil, fmt.Errorf("WebDAV URL 必须是 http 或 https")
	}
	if u.Host == "" {
		return nil, fmt.Errorf("WebDAV URL 缺少主机")
	}
	return u, nil
}

func normalizeWebDAVRootPath(value string) string {
	root := strings.TrimSpace(value)
	if root == "" || root == "." {
		return "/"
	}
	root = path.Clean("/" + strings.Trim(root, "/"))
	if root == "." {
		return "/"
	}
	return root
}

func normalizeWebDAVRelativePath(value string) string {
	remotePath := strings.TrimSpace(value)
	if remotePath == "" || remotePath == "." || remotePath == "/" {
		return "."
	}
	cleaned := path.Clean("/" + strings.TrimLeft(remotePath, "/"))
	rel := strings.Trim(cleaned, "/")
	if rel == "" {
		return "."
	}
	return rel
}

func cleanURLPath(parts ...string) string {
	segments := []string{}
	for _, part := range parts {
		for _, piece := range strings.Split(part, "/") {
			if piece != "" {
				segments = append(segments, piece)
			}
		}
	}
	if len(segments) == 0 {
		return "/"
	}
	return "/" + strings.Join(segments, "/")
}

func webDAVResponseEntry(item webDAVResponse, baseURLPath, currentRelPath string) (AssetFileEntry, bool) {
	prop, ok := item.successProp()
	if !ok {
		return AssetFileEntry{}, false
	}
	hrefPath := webDAVHrefPath(item.Href)
	if hrefPath == "" {
		return AssetFileEntry{}, false
	}
	baseClean := strings.TrimRight(path.Clean("/"+strings.TrimLeft(baseURLPath, "/")), "/")
	hrefClean := strings.TrimRight(path.Clean("/"+strings.TrimLeft(hrefPath, "/")), "/")
	if baseClean == "" {
		baseClean = "/"
	}
	if hrefClean == baseClean {
		return AssetFileEntry{}, false
	}
	name := strings.TrimSpace(prop.DisplayName)
	if name == "" {
		name = path.Base(hrefClean)
	}
	if name == "." || name == "/" || name == "" {
		return AssetFileEntry{}, false
	}
	rel := joinWebDAVDisplayPath(currentRelPath, name)
	size, _ := strconv.ParseInt(strings.TrimSpace(prop.GetContentLength), 10, 64)
	modTime := parseWebDAVTime(prop.GetLastModified)
	entryType := "file"
	mode := "-rw-r--r--"
	if len(prop.ResourceType.Collection) > 0 || strings.HasSuffix(item.Href, "/") {
		entryType = "dir"
		mode = "drwxr-xr-x"
	}
	return AssetFileEntry{
		Name:    name,
		Path:    rel,
		Type:    entryType,
		Size:    size,
		Mode:    mode,
		ModTime: modTime,
	}, true
}

func (r webDAVResponse) successProp() (webDAVProp, bool) {
	for _, propstat := range r.Propstat {
		if strings.Contains(propstat.Status, " 200 ") || strings.HasSuffix(propstat.Status, " 200 OK") {
			return propstat.Prop, true
		}
	}
	if len(r.Propstat) == 1 && r.Propstat[0].Status == "" {
		return r.Propstat[0].Prop, true
	}
	return webDAVProp{}, false
}

func webDAVHrefPath(href string) string {
	value := strings.TrimSpace(href)
	if value == "" {
		return ""
	}
	if u, err := url.Parse(value); err == nil && u.Path != "" {
		value = u.Path
	}
	decoded, err := url.PathUnescape(value)
	if err != nil {
		return value
	}
	return decoded
}

func joinWebDAVDisplayPath(base, name string) string {
	current := normalizeWebDAVRelativePath(base)
	if current == "." {
		return name
	}
	return path.Join(current, name)
}

func parseWebDAVTime(value string) time.Time {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}
	}
	if t, err := http.ParseTime(value); err == nil {
		return t
	}
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04:05Z07:00"} {
		if t, err := time.Parse(layout, value); err == nil {
			return t
		}
	}
	return time.Time{}
}
