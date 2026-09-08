package services

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"bookstark/models"
)

func TestAssetWebDAVManagerListParsesPropfind(t *testing.T) {
	var gotMethod, gotDepth, gotUser, gotPass string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMethod = r.Method
		gotDepth = r.Header.Get("Depth")
		gotUser, gotPass, _ = r.BasicAuth()
		if r.URL.Path != "/dav/docs" {
			t.Fatalf("request path = %q, want /dav/docs", r.URL.Path)
		}
		w.WriteHeader(207)
		_, _ = io.WriteString(w, `<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/docs/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/docs/report.txt</d:href>
    <d:propstat><d:prop><d:displayname>report.txt</d:displayname><d:getcontentlength>42</d:getcontentlength><d:getlastmodified>Mon, 02 Jan 2006 15:04:05 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/docs/projects/</d:href>
    <d:propstat><d:prop><d:displayname>projects</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>`)
	}))
	defer server.Close()

	manager := AssetWebDAVManager{Timeout: time.Second}
	items, err := manager.List(&models.AssetWebDAVServer{
		URL:      server.URL + "/dav",
		RootPath: "/docs",
		Username: "alice",
	}, "secret", ".")
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if gotMethod != "PROPFIND" || gotDepth != "1" {
		t.Fatalf("request method/depth = %s/%s, want PROPFIND/1", gotMethod, gotDepth)
	}
	if gotUser != "alice" || gotPass != "secret" {
		t.Fatalf("basic auth = %q/%q, want alice/secret", gotUser, gotPass)
	}
	if len(items) != 2 {
		t.Fatalf("items len = %d, want 2: %#v", len(items), items)
	}
	if items[0].Name != "report.txt" || items[0].Path != "report.txt" || items[0].Type != "file" || items[0].Size != 42 {
		t.Fatalf("file entry mismatch: %#v", items[0])
	}
	if items[1].Name != "projects" || items[1].Path != "projects" || items[1].Type != "dir" {
		t.Fatalf("dir entry mismatch: %#v", items[1])
	}
}

func TestAssetWebDAVManagerFileOperations(t *testing.T) {
	requests := []string{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		requests = append(requests, r.Method+" "+r.URL.Path+" "+r.Header.Get("Destination")+" "+string(body))
		if r.Method == http.MethodGet {
			_, _ = io.WriteString(w, "hello")
			return
		}
		w.WriteHeader(http.StatusCreated)
	}))
	defer server.Close()

	manager := AssetWebDAVManager{Timeout: time.Second}
	cfg := &models.AssetWebDAVServer{URL: server.URL + "/dav", RootPath: "/docs"}
	var downloaded strings.Builder
	if err := manager.Download(cfg, "", "a.txt", &downloaded); err != nil {
		t.Fatalf("Download() error = %v", err)
	}
	if downloaded.String() != "hello" {
		t.Fatalf("downloaded = %q, want hello", downloaded.String())
	}
	if err := manager.Upload(cfg, "", "b.txt", strings.NewReader("body")); err != nil {
		t.Fatalf("Upload() error = %v", err)
	}
	if err := manager.Mkdir(cfg, "", "folder"); err != nil {
		t.Fatalf("Mkdir() error = %v", err)
	}
	if err := manager.Copy(cfg, "", "b.txt", "c.txt"); err != nil {
		t.Fatalf("Copy() error = %v", err)
	}
	if err := manager.Rename(cfg, "", "c.txt", "d.txt"); err != nil {
		t.Fatalf("Rename() error = %v", err)
	}
	if err := manager.Remove(cfg, "", "d.txt", false); err != nil {
		t.Fatalf("Remove() error = %v", err)
	}
	want := []string{
		"GET /dav/docs/a.txt  ",
		"PUT /dav/docs/b.txt  body",
		"MKCOL /dav/docs/folder  ",
		"COPY /dav/docs/b.txt " + server.URL + "/dav/docs/c.txt ",
		"MOVE /dav/docs/c.txt " + server.URL + "/dav/docs/d.txt ",
		"DELETE /dav/docs/d.txt  ",
	}
	if len(requests) != len(want) {
		t.Fatalf("requests len = %d, want %d: %#v", len(requests), len(want), requests)
	}
	for i := range want {
		if requests[i] != want[i] {
			t.Fatalf("request[%d] = %q, want %q", i, requests[i], want[i])
		}
	}
}

func TestAssetWebDAVManagerOpenReadStreamDoesNotUseTotalTimeout(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Fatalf("request method = %s, want GET", r.Method)
		}
		if got := r.Header.Get("Range"); got != "bytes=0-4" {
			t.Fatalf("Range = %q, want bytes=0-4", got)
		}
		w.Header().Set("Content-Type", "video/mp4")
		w.Header().Set("Content-Length", "5")
		w.Header().Set("Accept-Ranges", "bytes")
		w.WriteHeader(http.StatusPartialContent)
		if flusher, ok := w.(http.Flusher); ok {
			flusher.Flush()
		}
		time.Sleep(50 * time.Millisecond)
		_, _ = io.WriteString(w, "hello")
	}))
	defer server.Close()

	manager := AssetWebDAVManager{Timeout: 20 * time.Millisecond}
	stream, err := manager.OpenReadStream(
		&models.AssetWebDAVServer{URL: server.URL + "/dav", RootPath: "/docs"},
		"",
		"movie.mp4",
		"bytes=0-4",
	)
	if err != nil {
		t.Fatalf("OpenReadStream() error = %v", err)
	}
	defer stream.Body.Close()

	body, err := io.ReadAll(stream.Body)
	if err != nil {
		t.Fatalf("ReadAll(stream.Body) error = %v", err)
	}
	if string(body) != "hello" {
		t.Fatalf("stream body = %q, want hello", body)
	}
}
