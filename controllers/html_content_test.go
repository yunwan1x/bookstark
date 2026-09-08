package controllers_test

import (
	"compress/gzip"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"bookstark/models"
)

func createHTMLDocument(t *testing.T, router http.Handler, token, suffix string) int64 {
	t.Helper()
	w := adminAssetRequest(router, token, http.MethodPost, "/api/books", map[string]any{
		"book_name": "HTML document limit book " + suffix,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/books status = %d, body=%s", w.Code, w.Body.String())
	}
	var bookResp struct {
		Data struct {
			BookID int64 `json:"book_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &bookResp); err != nil {
		t.Fatalf("decode book response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/books/"+strconv.FormatInt(bookResp.Data.BookID, 10)+"/docs", map[string]any{
		"document_name": "HTML document " + suffix,
		"doc_type":      "html",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/books/:id/docs status = %d, body=%s", w.Code, w.Body.String())
	}
	var docResp struct {
		Data struct {
			DocumentID int64 `json:"document_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &docResp); err != nil {
		t.Fatalf("decode document response: %v", err)
	}
	return docResp.Data.DocumentID
}

func TestUpdateHTMLDocumentCompressesContentAndRawEndpointReturnsHTML(t *testing.T) {
	router, token := initAssetControllerTest(t)
	documentID := createHTMLDocument(t, router, token, "compression")
	html := "<main><h1>Compressed document</h1><p>" + strings.Repeat("x", 500001) + "</p></main>"

	w := adminAssetRequest(router, token, http.MethodPut, "/api/docs/"+strconv.FormatInt(documentID, 10), map[string]any{
		"markdown": html,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("PUT /api/docs/:id status = %d, body=%s", w.Code, w.Body.String())
	}

	doc, err := models.GetDocumentByID(documentID)
	if err != nil {
		t.Fatalf("GetDocumentByID() error = %v", err)
	}
	if !strings.HasPrefix(doc.Markdown, "CMP:v1:gzip:") {
		t.Fatalf("Document markdown should be stored compressed, got prefix %.24q", doc.Markdown)
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/docs/"+strconv.FormatInt(documentID, 10)+"/content/raw", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET raw document HTML status = %d, body=%s", w.Code, w.Body.String())
	}
	if got := w.Header().Get("Content-Encoding"); got != "gzip" {
		t.Fatalf("Content-Encoding = %q, want gzip", got)
	}
	zr, err := gzip.NewReader(w.Body)
	if err != nil {
		t.Fatalf("gzip reader: %v", err)
	}
	defer zr.Close()
	body, err := io.ReadAll(zr)
	if err != nil {
		t.Fatalf("read gzip body: %v", err)
	}
	if string(body) != html {
		t.Fatalf("raw document HTML body mismatch")
	}
}

func TestUpdateHTMLDocumentRejectsContentOverFiveMiB(t *testing.T) {
	router, token := initAssetControllerTest(t)
	documentID := createHTMLDocument(t, router, token, "oversized")

	w := adminAssetRequest(router, token, http.MethodPut, "/api/docs/"+strconv.FormatInt(documentID, 10), map[string]any{
		"markdown": strings.Repeat("x", 5242881),
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("PUT oversized HTML document status = %d, want %d; body=%s", w.Code, http.StatusBadRequest, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "HTML内容不能超过5MB") {
		t.Fatalf("PUT oversized HTML document body = %s, want HTML size limit message", w.Body.String())
	}
}
