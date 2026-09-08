package controllers_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAnonymousHeaderHidesEmptyCollectionsMenu(t *testing.T) {
	router, _ := initAssetControllerTest(t)

	req := httptest.NewRequest(http.MethodGet, "/bookmarks", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /bookmarks status = %d body=%s", w.Code, w.Body.String())
	}
	body := w.Body.String()
	headerStart := strings.Index(body, "<header ")
	headerEnd := strings.Index(body, "</header>")
	if headerStart == -1 || headerEnd == -1 || headerEnd <= headerStart {
		t.Fatalf("GET /bookmarks should render header")
	}
	header := body[headerStart : headerEnd+len("</header>")]
	for _, forbidden := range []string{
		`data-header-menu-id="header-collections-menu"`,
		`id="header-collections-menu"`,
		`专题`,
	} {
		if strings.Contains(header, forbidden) {
			t.Fatalf("anonymous header should hide empty collections menu, found %q", forbidden)
		}
	}
	for _, required := range []string{
		`id="header-knowledge-menu"`,
		`href="/bookmarks"`,
		`id="header-assets-menu"`,
		`href="/shares"`,
	} {
		if !strings.Contains(header, required) {
			t.Fatalf("anonymous header should keep public menu item %q", required)
		}
	}
}
