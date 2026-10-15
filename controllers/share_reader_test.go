package controllers_test

import (
	"bookstark/models"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestShareReaderTemplatesForAllDocumentTypes(t *testing.T) {
	router, token := initAssetControllerTest(t)
	paths := map[string]string{}
	for _, kind := range []string{"markdown", "html", "richdoc", "spreadsheet", "presentation", "drawing", "mindmap"} {
		blog := &models.Blog{BlogTitle: "Reader " + kind, BlogIdentify: "reader-" + kind, BlogType: "article", EditorType: kind, MemberID: 1, Visibility: 1, BlogContent: "# Test heading"}
		if err := blog.Insert(); err != nil {
			t.Fatal(err)
		}
		paths[kind] = "/shares/" + blog.BlogIdentify
	}
	book := &models.Book{BookName: "Reader book", Identify: "reader-book", MemberID: 1}
	if err := book.Insert(); err != nil {
		t.Fatal(err)
	}
	share, err := models.CreateShare("book", book.BookID, 1, "")
	if err != nil {
		t.Fatal(err)
	}
	paths["book"] = "/shares/" + share.ShareIdentify
	for _, auth := range []string{"", token} {
		w := adminAssetRequest(router, auth, "GET", "/shares?type=article", nil)
		if w.Code != http.StatusOK {
			t.Fatal(w.Code, w.Body.String())
		}
		for kind, path := range paths {
			if kind != "book" && !strings.Contains(w.Body.String(), `href="`+path+`" target="_blank" rel="noopener noreferrer"`) {
				t.Fatalf("%s article must open in a new tab (authenticated=%v)", kind, auth != "")
			}
		}
	}
	for kind, path := range paths {
		for _, lang := range []string{"zh", "en"} {
			req := httptest.NewRequest(http.MethodGet, path, nil)
			req.AddCookie(&http.Cookie{Name: "lang", Value: lang})
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)
			if w.Code != http.StatusOK {
				t.Fatalf("%s: %d %s", kind, w.Code, w.Body.String())
			}
			body := w.Body.String()
			if !strings.Contains(body, `id="share-reader-fullscreen-btn" hidden`) || !strings.Contains(body, `role="tab" hidden`) {
				t.Fatalf("%s: controls must start hidden until capability detection", kind)
			}
			if kind == "book" && !strings.Contains(body, `id="share-book-tree"`) {
				t.Fatal("missing chapter tree")
			}
			if dir := os.Getenv("SHARE_READER_SNAPSHOT_DIR"); dir != "" {
				if err := os.WriteFile(filepath.Join(dir, "share-reader-"+kind+"-"+lang+".html"), w.Body.Bytes(), 0600); err != nil {
					t.Fatal(err)
				}
			}
		}
	}
}
