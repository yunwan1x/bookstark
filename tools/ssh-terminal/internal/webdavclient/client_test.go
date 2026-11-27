package webdavclient

import (
	"context"
	"encoding/xml"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func newMockDAVServer(t *testing.T, user, pass string) *httptest.Server {
	t.Helper()
	var mu sync.Mutex
	files := map[string][]byte{
		"/dav/hello.txt":      []byte("hello webdav"),
		"/dav/sub/config.yml": []byte("port: 8089\n"),
	}
	dirs := map[string]bool{
		"/dav":     true,
		"/dav/sub": true,
	}

	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, p, ok := r.BasicAuth()
		if !ok || u != user || p != pass {
			w.Header().Set("WWW-Authenticate", `Basic realm="test"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		mu.Lock()
		defer mu.Unlock()
		reqPath := strings.TrimSuffix(path.Clean(r.URL.Path), "/")
		if reqPath == "" {
			reqPath = "/"
		}
		switch r.Method {
		case "PROPFIND":
			if !dirs[reqPath] {
				http.NotFound(w, r)
				return
			}
			type rt struct {
				Collection *struct{} `xml:"D:collection,omitempty"`
			}
			type prop struct {
				DisplayName   string `xml:"D:displayname"`
				ResourceType  rt     `xml:"D:resourcetype"`
				ContentLength string `xml:"D:getcontentlength,omitempty"`
				LastModified  string `xml:"D:getlastmodified"`
			}
			type propstat struct {
				Prop   prop   `xml:"D:prop"`
				Status string `xml:"D:status"`
			}
			type respItem struct {
				Href     string   `xml:"D:href"`
				Propstat propstat `xml:"D:propstat"`
			}
			type ms struct {
				XMLName   xml.Name   `xml:"D:multistatus"`
				Xmlns     string     `xml:"xmlns:D,attr"`
				Responses []respItem `xml:"D:response"`
			}
			out := ms{Xmlns: "DAV:"}
			now := time.Now().UTC().Format(http.TimeFormat)
			out.Responses = append(out.Responses, respItem{
				Href: reqPath + "/",
				Propstat: propstat{
					Status: "HTTP/1.1 200 OK",
					Prop:   prop{DisplayName: path.Base(reqPath), ResourceType: rt{Collection: &struct{}{}}, LastModified: now},
				},
			})
			var childDirs []string
			for d := range dirs {
				if d != reqPath && path.Dir(d) == reqPath {
					childDirs = append(childDirs, d)
				}
			}
			sort.Strings(childDirs)
			for _, d := range childDirs {
				out.Responses = append(out.Responses, respItem{
					Href: d + "/",
					Propstat: propstat{
						Status: "HTTP/1.1 200 OK",
						Prop:   prop{DisplayName: path.Base(d), ResourceType: rt{Collection: &struct{}{}}, LastModified: now},
					},
				})
			}
			for f, data := range files {
				if path.Dir(f) == reqPath {
					out.Responses = append(out.Responses, respItem{
						Href: f,
						Propstat: propstat{
							Status: "HTTP/1.1 200 OK",
							Prop:   prop{DisplayName: path.Base(f), ContentLength: strconv.Itoa(len(data)), LastModified: now},
						},
					})
				}
			}
			w.Header().Set("Content-Type", "application/xml; charset=utf-8")
			w.WriteHeader(http.StatusMultiStatus)
			_ = xml.NewEncoder(w).Encode(out)
		case "GET":
			data, ok := files[reqPath]
			if !ok {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Length", strconv.Itoa(len(data)))
			_, _ = w.Write(data)
		case "PUT":
			data, _ := io.ReadAll(r.Body)
			files[reqPath] = data
			w.WriteHeader(http.StatusCreated)
		case "MKCOL":
			dirs[reqPath] = true
			w.WriteHeader(http.StatusCreated)
		case "MOVE":
			dst, err := url.Parse(r.Header.Get("Destination"))
			if err != nil {
				http.Error(w, "bad dest", http.StatusBadRequest)
				return
			}
			dstPath := strings.TrimSuffix(path.Clean(dst.Path), "/")
			if data, ok := files[reqPath]; ok {
				files[dstPath] = data
				delete(files, reqPath)
				w.WriteHeader(http.StatusCreated)
				return
			}
			http.NotFound(w, r)
		case "DELETE":
			delete(files, reqPath)
			delete(dirs, reqPath)
			w.WriteHeader(http.StatusNoContent)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))
}

func TestWebDAVCRUD(t *testing.T) {
	srv := newMockDAVServer(t, "alice", "secret")
	defer srv.Close()

	c, err := New(Config{
		URL:      srv.URL + "/dav",
		User:     "alice",
		Password: "secret",
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer c.Close()

	ctx := context.Background()
	cwd, list, err := c.List(ctx, "/")
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if cwd != "/" || len(list) != 2 {
		t.Fatalf("unexpected list: cwd=%q entries=%+v", cwd, list)
	}
	if !list[0].IsDir || list[0].Name != "sub" || list[1].Name != "hello.txt" {
		t.Fatalf("unexpected sort/entries: %+v", list)
	}

	if err := c.Mkdir(ctx, "/notes"); err != nil {
		t.Fatalf("Mkdir: %v", err)
	}
	if err := c.Write(ctx, "/notes/a.md", []byte("# hi\n"), nil); err != nil {
		t.Fatalf("Write: %v", err)
	}
	data, total, trunc, err := c.Read(ctx, "/notes/a.md", 1024, nil)
	if err != nil || string(data) != "# hi\n" || total != 5 || trunc {
		t.Fatalf("Read: data=%q total=%d trunc=%v err=%v", data, total, trunc, err)
	}
	if err := c.Rename(ctx, "/notes/a.md", "/notes/b.md"); err != nil {
		t.Fatalf("Rename: %v", err)
	}
	if err := c.Delete(ctx, "/notes/b.md"); err != nil {
		t.Fatalf("Delete: %v", err)
	}
}
