package controllers_test

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"bookstark/conf"
	"bookstark/models"
)

type failingDAVRequestReader struct {
	content []byte
	sent    bool
}

func (r *failingDAVRequestReader) Read(buffer []byte) (int, error) {
	if !r.sent {
		r.sent = true
		return copy(buffer, r.content), nil
	}
	return 0, errors.New("simulated request body failure")
}

type opaqueDAVRequestReader struct {
	io.Reader
}

func setupLocalDAVControllerTest(t *testing.T) (http.Handler, string, string) {
	t.Helper()
	router, token := initAssetControllerTest(t)
	if models.WebDAVDB != nil {
		_ = models.WebDAVDB.Close()
		models.WebDAVDB = nil
	}
	if err := models.InitWebDAVDB(filepath.Join(t.TempDir(), "webdav.db")); err != nil {
		t.Fatalf("InitWebDAVDB() error = %v", err)
	}
	t.Cleanup(func() {
		if models.WebDAVDB != nil {
			_ = models.WebDAVDB.Close()
			models.WebDAVDB = nil
		}
	})
	admin, err := models.GetMemberByAccount(conf.App.AdminAccount)
	if err != nil {
		t.Fatalf("GetMemberByAccount() error = %v", err)
	}
	return router, token, admin.Account
}

func TestLocalDAVProtocolAndPublicAssetFlow(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)

	reset := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/app-password/reset", nil)
	if reset.Code != http.StatusOK {
		t.Fatalf("reset password status=%d body=%s", reset.Code, reset.Body.String())
	}
	var resetBody struct {
		Data struct {
			Password string `json:"app_password"`
		} `json:"data"`
	}
	if err := json.Unmarshal(reset.Body.Bytes(), &resetBody); err != nil || resetBody.Data.Password == "" {
		t.Fatalf("reset password response=%s error=%v", reset.Body.String(), err)
	}

	mkcol := davProtocolRequest(router, account, resetBody.Data.Password, "MKCOL", "/dav/docs", "")
	if mkcol.Code != http.StatusCreated {
		t.Fatalf("MKCOL status=%d body=%s", mkcol.Code, mkcol.Body.String())
	}
	put := davProtocolRequest(router, account, resetBody.Data.Password, http.MethodPut, "/dav/docs/app.js", "console.log('dav');\n")
	if put.Code != http.StatusCreated && put.Code != http.StatusNoContent {
		t.Fatalf("PUT status=%d body=%s", put.Code, put.Body.String())
	}
	propfind := davProtocolRequest(router, account, resetBody.Data.Password, "PROPFIND", "/dav/docs", "")
	if propfind.Code != http.StatusMultiStatus || !strings.Contains(propfind.Body.String(), "app.js") {
		t.Fatalf("PROPFIND status=%d body=%s", propfind.Code, propfind.Body.String())
	}
	get := davProtocolRequest(router, account, resetBody.Data.Password, http.MethodGet, "/dav/docs/app.js", "")
	if get.Code != http.StatusOK || get.Body.String() != "console.log('dav');\n" {
		t.Fatalf("GET status=%d body=%q", get.Code, get.Body.String())
	}
	copyReq := davProtocolRequestWithHeaders(router, account, resetBody.Data.Password, "COPY", "/dav/docs/app.js", "", map[string]string{
		"Destination": "/dav/docs/app-copy.js",
	})
	if copyReq.Code != http.StatusCreated && copyReq.Code != http.StatusNoContent {
		t.Fatalf("COPY status=%d body=%s", copyReq.Code, copyReq.Body.String())
	}
	moveReq := davProtocolRequestWithHeaders(router, account, resetBody.Data.Password, "MOVE", "/dav/docs/app-copy.js", "", map[string]string{
		"Destination": "/dav/docs/应用.js",
	})
	if moveReq.Code != http.StatusCreated && moveReq.Code != http.StatusNoContent {
		t.Fatalf("MOVE status=%d body=%s", moveReq.Code, moveReq.Body.String())
	}
	unicodeGet := davProtocolRequest(router, account, resetBody.Data.Password, http.MethodGet, "/dav/docs/%E5%BA%94%E7%94%A8.js", "")
	if unicodeGet.Code != http.StatusOK || unicodeGet.Body.String() != "console.log('dav');\n" {
		t.Fatalf("GET unicode status=%d body=%q", unicodeGet.Code, unicodeGet.Body.String())
	}

	publish := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/files/public", map[string]any{
		"path":        "docs/app.js",
		"public_path": "vendor/app.js",
	})
	if publish.Code != http.StatusOK {
		t.Fatalf("publish status=%d body=%s", publish.Code, publish.Body.String())
	}
	publicReq := httptest.NewRequest(http.MethodGet, "/dav-public/"+account+"/vendor/app.js", nil)
	publicReq.Header.Set("Accept-Encoding", "gzip")
	public := httptest.NewRecorder()
	router.ServeHTTP(public, publicReq)
	if public.Code != http.StatusOK || public.Header().Get("Cache-Control") == "" {
		t.Fatalf("public asset status=%d headers=%v body=%s", public.Code, public.Header(), public.Body.String())
	}

	deleteReq := davProtocolRequest(router, account, resetBody.Data.Password, http.MethodDelete, "/dav/docs/app.js", "")
	if deleteReq.Code != http.StatusNoContent && deleteReq.Code != http.StatusOK {
		t.Fatalf("DELETE status=%d body=%s", deleteReq.Code, deleteReq.Body.String())
	}
	missing := davProtocolRequest(router, account, resetBody.Data.Password, http.MethodGet, "/dav/docs/app.js", "")
	if missing.Code != http.StatusNotFound {
		t.Fatalf("GET deleted file status=%d, want 404", missing.Code)
	}
}

func TestLocalDAVCustomAppPasswordAndValidation(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	const firstPassword = "custom-dav-password"
	reset := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/app-password/reset", map[string]any{
		"password": firstPassword,
	})
	if reset.Code != http.StatusOK {
		t.Fatalf("set custom password status=%d body=%s", reset.Code, reset.Body.String())
	}
	if response := davProtocolRequest(router, account, firstPassword, "PROPFIND", "/dav", ""); response.Code != http.StatusMultiStatus {
		t.Fatalf("custom password PROPFIND status=%d body=%s", response.Code, response.Body.String())
	}

	const secondPassword = "replacement-dav-password"
	replaced := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/app-password/reset", map[string]any{
		"password": secondPassword,
	})
	if replaced.Code != http.StatusOK {
		t.Fatalf("replace custom password status=%d body=%s", replaced.Code, replaced.Body.String())
	}
	if response := davProtocolRequest(router, account, firstPassword, "PROPFIND", "/dav", ""); response.Code != http.StatusUnauthorized {
		t.Fatalf("old custom password status=%d, want %d", response.Code, http.StatusUnauthorized)
	}
	if response := davProtocolRequest(router, account, secondPassword, "PROPFIND", "/dav", ""); response.Code != http.StatusMultiStatus {
		t.Fatalf("replacement password PROPFIND status=%d body=%s", response.Code, response.Body.String())
	}

	invalid := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/app-password/reset", map[string]any{
		"password": "short",
	})
	if invalid.Code != http.StatusBadRequest {
		t.Fatalf("short password status=%d body=%s", invalid.Code, invalid.Body.String())
	}
}

func TestLocalDAVFailedOrOversizedPUTDoesNotCommitPartialFile(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	password := resetDAVPasswordForTest(t, router, token)
	if result := davProtocolRequest(router, account, password, "MKCOL", "/dav/uploads", ""); result.Code != http.StatusCreated {
		t.Fatalf("MKCOL status=%d body=%s", result.Code, result.Body.String())
	}

	failedRequest := httptest.NewRequest(
		http.MethodPut,
		"/dav/uploads/interrupted.bin",
		&failingDAVRequestReader{content: []byte("partial-data")},
	)
	failedRequest.SetBasicAuth(account, password)
	failedResponse := httptest.NewRecorder()
	router.ServeHTTP(failedResponse, failedRequest)
	if failedResponse.Code >= 200 && failedResponse.Code < 300 {
		t.Fatalf("interrupted PUT status=%d, want failure", failedResponse.Code)
	}
	if result := davProtocolRequest(router, account, password, http.MethodGet, "/dav/uploads/interrupted.bin", ""); result.Code != http.StatusNotFound {
		t.Fatalf("GET interrupted file status=%d body=%q, want 404", result.Code, result.Body.String())
	}

	if err := models.BatchUpdateSettings(map[string]string{
		"webdav_file_max_bytes": strconv.Itoa(1 << 20),
	}); err != nil {
		t.Fatalf("set WebDAV file limit: %v", err)
	}
	oversized := bytes.Repeat([]byte("x"), (1<<20)+1)
	oversizedRequest := httptest.NewRequest(
		http.MethodPut,
		"/dav/uploads/oversized.bin",
		opaqueDAVRequestReader{Reader: bytes.NewReader(oversized)},
	)
	oversizedRequest.SetBasicAuth(account, password)
	oversizedResponse := httptest.NewRecorder()
	router.ServeHTTP(oversizedResponse, oversizedRequest)
	if oversizedResponse.Code >= 200 && oversizedResponse.Code < 300 {
		t.Fatalf("oversized PUT status=%d, want failure", oversizedResponse.Code)
	}
	if result := davProtocolRequest(router, account, password, http.MethodGet, "/dav/uploads/oversized.bin", ""); result.Code != http.StatusNotFound {
		t.Fatalf("GET oversized file status=%d body=%q, want 404", result.Code, result.Body.String())
	}
}

func TestLocalDAVCOPYCompletesWithSingleTransferSlot(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	password := resetDAVPasswordForTest(t, router, token)
	if err := models.BatchUpdateSettings(map[string]string{
		"webdav_max_concurrent_transfers": "1",
	}); err != nil {
		t.Fatalf("set WebDAV transfer limit: %v", err)
	}
	if result := davProtocolRequest(router, account, password, "MKCOL", "/dav/copy", ""); result.Code != http.StatusCreated {
		t.Fatalf("MKCOL status=%d body=%s", result.Code, result.Body.String())
	}
	content := strings.Repeat("copy-with-one-slot\n", 1024)
	if result := davProtocolRequest(router, account, password, http.MethodPut, "/dav/copy/source.txt", content); result.Code != http.StatusCreated {
		t.Fatalf("PUT source status=%d body=%s", result.Code, result.Body.String())
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	request := httptest.NewRequest("COPY", "/dav/copy/source.txt", nil).WithContext(ctx)
	request.SetBasicAuth(account, password)
	request.Header.Set("Destination", "/dav/copy/target.txt")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusCreated && response.Code != http.StatusNoContent {
		t.Fatalf("COPY status=%d body=%s", response.Code, response.Body.String())
	}
	target := davProtocolRequest(router, account, password, http.MethodGet, "/dav/copy/target.txt", "")
	if target.Code != http.StatusOK || target.Body.String() != content {
		t.Fatalf("GET copied target status=%d size=%d", target.Code, target.Body.Len())
	}
}

func TestLocalDAVPublicAssetHTTPBehavior(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	password := resetDAVPasswordForTest(t, router, token)
	if result := davProtocolRequest(router, account, password, "MKCOL", "/dav/assets", ""); result.Code != http.StatusCreated {
		t.Fatalf("MKCOL status=%d body=%s", result.Code, result.Body.String())
	}
	css := strings.Repeat(".card{color:#123;background:#fff}\n", 512)
	if result := davProtocolRequest(router, account, password, http.MethodPut, "/dav/assets/app.css", css); result.Code != http.StatusCreated {
		t.Fatalf("PUT css status=%d body=%s", result.Code, result.Body.String())
	}
	binary := strings.Repeat("PNG-RANGE-", models.DAVChunkSize/len("PNG-RANGE-")+128)
	if result := davProtocolRequest(router, account, password, http.MethodPut, "/dav/assets/image.png", binary); result.Code != http.StatusCreated {
		t.Fatalf("PUT binary status=%d body=%s", result.Code, result.Body.String())
	}
	for _, item := range []struct{ path, publicPath string }{
		{"assets/app.css", "styles/app.css"},
		{"assets/image.png", "images/image.png"},
	} {
		response := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/files/public", map[string]any{
			"path": item.path, "public_path": item.publicPath,
		})
		if response.Code != http.StatusOK {
			t.Fatalf("publish %s status=%d body=%s", item.path, response.Code, response.Body.String())
		}
	}

	publicPath := "/dav-public/" + account + "/styles/app.css"
	gzipResponse := publicDAVRequest(router, http.MethodGet, publicPath, map[string]string{"Accept-Encoding": "gzip"})
	if gzipResponse.Code != http.StatusOK || gzipResponse.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("gzip public status=%d headers=%v", gzipResponse.Code, gzipResponse.Header())
	}
	reader, err := gzip.NewReader(gzipResponse.Body)
	if err != nil {
		t.Fatalf("gzip.NewReader() error=%v", err)
	}
	decoded, err := io.ReadAll(reader)
	_ = reader.Close()
	if err != nil || string(decoded) != css {
		t.Fatalf("decoded public content mismatch: error=%v size=%d", err, len(decoded))
	}
	etag := gzipResponse.Header().Get("ETag")
	notModified := publicDAVRequest(router, http.MethodGet, publicPath, map[string]string{"If-None-Match": etag})
	if notModified.Code != http.StatusNotModified || notModified.Body.Len() != 0 {
		t.Fatalf("conditional GET status=%d body size=%d", notModified.Code, notModified.Body.Len())
	}
	head := publicDAVRequest(router, http.MethodHead, publicPath, map[string]string{"Accept-Encoding": "gzip"})
	if head.Code != http.StatusOK || head.Body.Len() != 0 || head.Header().Get("Content-Length") != "" ||
		head.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("HEAD status=%d headers=%v body size=%d", head.Code, head.Header(), head.Body.Len())
	}

	rangeStart := models.DAVChunkSize - 4
	rangeEnd := rangeStart + 15
	rangeResponse := publicDAVRequest(router, http.MethodGet, "/dav-public/"+account+"/images/image.png", map[string]string{
		"Range": "bytes=" + strconv.Itoa(rangeStart) + "-" + strconv.Itoa(rangeEnd),
	})
	if rangeResponse.Code != http.StatusPartialContent || rangeResponse.Body.String() != binary[rangeStart:rangeEnd+1] {
		t.Fatalf("Range status=%d headers=%v body=%q", rangeResponse.Code, rangeResponse.Header(), rangeResponse.Body.String())
	}

	if err := models.BatchUpdateSettings(map[string]string{
		"webdav_public_file_max_bytes": strconv.Itoa(1 << 20),
	}); err != nil {
		t.Fatalf("set public file limit: %v", err)
	}
	oversizedUpdate := strings.Repeat("x", (1<<20)+1)
	update := davProtocolRequest(router, account, password, http.MethodPut, "/dav/assets/app.css", oversizedUpdate)
	if update.Code >= 200 && update.Code < 300 {
		t.Fatalf("oversized update of public file status=%d, want failure", update.Code)
	}
	unchanged := publicDAVRequest(router, http.MethodGet, publicPath, nil)
	if unchanged.Code != http.StatusOK || unchanged.Body.String() != css {
		t.Fatalf("public file changed after rejected oversized update: status=%d size=%d", unchanged.Code, unchanged.Body.Len())
	}
}

func TestLocalDAVPasswordResetInvalidatesOldPassword(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	oldPassword := resetDAVPasswordForTest(t, router, token)
	cachedRequest := davProtocolRequest(router, account, oldPassword, "PROPFIND", "/dav", "")
	if cachedRequest.Code != http.StatusMultiStatus {
		t.Fatalf("initial app password status=%d body=%s", cachedRequest.Code, cachedRequest.Body.String())
	}
	newPassword := resetDAVPasswordForTest(t, router, token)
	oldRequest := davProtocolRequest(router, account, oldPassword, "PROPFIND", "/dav", "")
	if oldRequest.Code != http.StatusUnauthorized {
		t.Fatalf("old app password status=%d, want 401", oldRequest.Code)
	}
	newRequest := davProtocolRequest(router, account, newPassword, "PROPFIND", "/dav", "")
	if newRequest.Code != http.StatusMultiStatus {
		t.Fatalf("new app password status=%d body=%s", newRequest.Code, newRequest.Body.String())
	}
}

func TestLocalDAVLocksAreIsolatedByMember(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	hostPassword := resetDAVPasswordForTest(t, router, token)
	peer := &models.Member{
		Account:     "dav-lock-peer",
		Password:    "unused-login-password",
		Email:       "dav-lock-peer@example.test",
		Role:        0,
		Status:      1,
		CreateTime:  time.Now(),
		CreateAt:    time.Now().Unix(),
		DefaultHome: models.DefaultHomeNotes,
	}
	if err := peer.Insert(); err != nil {
		t.Fatalf("insert peer member: %v", err)
	}
	peerPassword, err := models.ResetDAVAppPassword(peer.MemberID)
	if err != nil {
		t.Fatalf("ResetDAVAppPassword(peer) error = %v", err)
	}
	const requestPath = "/dav/member-lock-isolation.txt"
	for _, credentials := range []struct {
		account  string
		password string
	}{
		{account, hostPassword},
		{peer.Account, peerPassword},
	} {
		response := davProtocolRequest(router, credentials.account, credentials.password, http.MethodPut, requestPath, "initial")
		if response.Code != http.StatusCreated && response.Code != http.StatusNoContent {
			t.Fatalf("initial PUT for %s status=%d body=%s", credentials.account, response.Code, response.Body.String())
		}
	}

	lockBody := `<?xml version="1.0" encoding="utf-8"?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner><D:href>bookstark-test</D:href></D:owner>
</D:lockinfo>`
	lockResponse := davProtocolRequestWithHeaders(router, account, hostPassword, "LOCK", requestPath, lockBody, map[string]string{
		"Content-Type": "application/xml",
		"Depth":        "0",
		"Timeout":      "Second-3600",
	})
	if lockResponse.Code != http.StatusOK {
		t.Fatalf("LOCK status=%d headers=%v body=%s", lockResponse.Code, lockResponse.Header(), lockResponse.Body.String())
	}
	hostBlocked := davProtocolRequest(router, account, hostPassword, http.MethodPut, requestPath, "blocked")
	if hostBlocked.Code != 423 {
		t.Fatalf("locked host PUT status=%d, want 423; body=%s", hostBlocked.Code, hostBlocked.Body.String())
	}
	peerWrite := davProtocolRequest(router, peer.Account, peerPassword, http.MethodPut, requestPath, "peer update")
	if peerWrite.Code != http.StatusNoContent && peerWrite.Code != http.StatusCreated {
		t.Fatalf("peer PUT should ignore another member lock: status=%d body=%s", peerWrite.Code, peerWrite.Body.String())
	}
	if lockToken := lockResponse.Header().Get("Lock-Token"); lockToken != "" {
		unlock := davProtocolRequestWithHeaders(router, account, hostPassword, "UNLOCK", requestPath, "", map[string]string{
			"Lock-Token": lockToken,
		})
		if unlock.Code != http.StatusNoContent {
			t.Fatalf("UNLOCK status=%d body=%s", unlock.Code, unlock.Body.String())
		}
	}
}

func TestLocalDAVRejectsLoginPasswordAndInvalidPublicPath(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	unauthorized := davProtocolRequest(router, account, conf.App.AdminPassword, "PROPFIND", "/dav", "")
	if unauthorized.Code != http.StatusUnauthorized || unauthorized.Header().Get("WWW-Authenticate") == "" {
		t.Fatalf("login password status=%d headers=%v", unauthorized.Code, unauthorized.Header())
	}
	badPublish := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/files/public", map[string]any{
		"path":        "missing.js",
		"public_path": "../bad.js",
	})
	if badPublish.Code != http.StatusNotFound {
		t.Fatalf("missing publish status=%d body=%s", badPublish.Code, badPublish.Body.String())
	}
}

func TestLocalDAVRateLimitsRepeatedAuthenticationFailures(t *testing.T) {
	router, _, _ := setupLocalDAVControllerTest(t)
	account := createDAVRateLimitMember(t, "dav-rate-sequential")
	const remoteAddress = "203.0.113.77:43120"
	for attempt := 0; attempt < 20; attempt++ {
		request := httptest.NewRequest("PROPFIND", "/dav", nil)
		request.RemoteAddr = remoteAddress
		request.SetBasicAuth(account, "invalid-app-password")
		request.Header.Set("Depth", "1")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d status=%d, want 401", attempt+1, response.Code)
		}
	}
	blockedRequest := httptest.NewRequest("PROPFIND", "/dav", nil)
	blockedRequest.RemoteAddr = remoteAddress
	blockedRequest.SetBasicAuth(account, "invalid-app-password")
	blockedRequest.Header.Set("Depth", "1")
	blockedResponse := httptest.NewRecorder()
	router.ServeHTTP(blockedResponse, blockedRequest)
	if blockedResponse.Code != http.StatusTooManyRequests || blockedResponse.Header().Get("Retry-After") == "" {
		t.Fatalf("blocked status=%d headers=%v, want 429 with Retry-After", blockedResponse.Code, blockedResponse.Header())
	}
}

func TestLocalDAVRateLimitClosesConcurrentAuthenticationWindow(t *testing.T) {
	router, _, _ := setupLocalDAVControllerTest(t)
	account := createDAVRateLimitMember(t, "dav-rate-concurrent")
	const (
		requestCount  = 40
		failureLimit  = 20
		remoteAddress = "203.0.113.78:43120"
	)
	var unauthorized atomic.Int32
	var rateLimited atomic.Int32
	var unexpected atomic.Int32
	var wait sync.WaitGroup
	start := make(chan struct{})
	wait.Add(requestCount)
	for attempt := 0; attempt < requestCount; attempt++ {
		go func() {
			defer wait.Done()
			<-start
			request := httptest.NewRequest("PROPFIND", "/dav", nil)
			request.RemoteAddr = remoteAddress
			request.SetBasicAuth(account, "invalid-app-password")
			request.Header.Set("Depth", "1")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			switch response.Code {
			case http.StatusUnauthorized:
				unauthorized.Add(1)
			case http.StatusTooManyRequests:
				rateLimited.Add(1)
			default:
				unexpected.Add(1)
			}
		}()
	}
	close(start)
	wait.Wait()
	if unexpected.Load() != 0 || unauthorized.Load() != failureLimit ||
		rateLimited.Load() != requestCount-failureLimit {
		t.Fatalf("concurrent auth statuses: unauthorized=%d rate_limited=%d unexpected=%d",
			unauthorized.Load(), rateLimited.Load(), unexpected.Load())
	}
}

func TestLocalDAVRateLimitCannotBeBypassedByForwardedIPRotation(t *testing.T) {
	router, _, _ := setupLocalDAVControllerTest(t)
	account := createDAVRateLimitMember(t, "dav-rate-forwarded")
	const remoteAddress = "203.0.113.79:43120"
	for attempt := 0; attempt < 21; attempt++ {
		request := httptest.NewRequest("PROPFIND", "/dav", nil)
		request.RemoteAddr = remoteAddress
		request.Header.Set("X-Forwarded-For", "198.51.100."+strconv.Itoa(attempt+1))
		request.SetBasicAuth(account, "invalid-app-password")
		request.Header.Set("Depth", "1")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		want := http.StatusUnauthorized
		if attempt == 20 {
			want = http.StatusTooManyRequests
		}
		if response.Code != want {
			t.Fatalf("rotated forwarded IP attempt %d status=%d, want %d", attempt+1, response.Code, want)
		}
	}
}

func TestLocalDAVRejectsJoinedPathTraversalNames(t *testing.T) {
	router, token, _ := setupLocalDAVControllerTest(t)

	mkdir := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/files/mkdir", map[string]any{
		"path": "safe",
		"name": "../escaped",
	})
	if mkdir.Code != http.StatusBadRequest {
		t.Fatalf("mkdir traversal status=%d body=%s", mkdir.Code, mkdir.Body.String())
	}

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	if err := writer.WriteField("path", "../escaped"); err != nil {
		t.Fatalf("WriteField() error = %v", err)
	}
	filePart, err := writer.CreateFormFile("file", "safe.txt")
	if err != nil {
		t.Fatalf("CreateFormFile() error = %v", err)
	}
	_, _ = filePart.Write([]byte("must not escape"))
	_ = writer.Close()
	request := httptest.NewRequest(http.MethodPost, "/api/webdav/files/upload", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	request.Header.Set("Authorization", "Token "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("invalid multipart upload status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestLocalDAVCompressedPublicResponseAlwaysVariesByEncoding(t *testing.T) {
	router, token, account := setupLocalDAVControllerTest(t)
	password := resetDAVPasswordForTest(t, router, token)
	if response := davProtocolRequest(router, account, password, "MKCOL", "/dav/assets", ""); response.Code != http.StatusCreated {
		t.Fatalf("MKCOL status=%d body=%s", response.Code, response.Body.String())
	}
	content := strings.Repeat("body{color:#123}\n", 1024)
	if response := davProtocolRequest(router, account, password, http.MethodPut, "/dav/assets/theme.css", content); response.Code != http.StatusCreated {
		t.Fatalf("PUT status=%d body=%s", response.Code, response.Body.String())
	}
	if response := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/files/public", map[string]any{
		"path": "assets/theme.css", "public_path": "theme.css",
	}); response.Code != http.StatusOK {
		t.Fatalf("publish status=%d body=%s", response.Code, response.Body.String())
	}
	response := publicDAVRequest(router, http.MethodGet, "/dav-public/"+account+"/theme.css", nil)
	if response.Code != http.StatusOK || response.Header().Get("Vary") != "Accept-Encoding" ||
		response.Header().Get("Content-Encoding") != "" || response.Body.String() != content {
		t.Fatalf("plain compressed-source response status=%d headers=%v size=%d", response.Code, response.Header(), response.Body.Len())
	}
	disabledGzip := publicDAVRequest(router, http.MethodGet, "/dav-public/"+account+"/theme.css", map[string]string{
		"Accept-Encoding": "br, gzip;q=0",
	})
	if disabledGzip.Code != http.StatusOK || disabledGzip.Header().Get("Content-Encoding") != "" ||
		disabledGzip.Body.String() != content {
		t.Fatalf("gzip;q=0 response status=%d headers=%v size=%d", disabledGzip.Code, disabledGzip.Header(), disabledGzip.Body.Len())
	}
	enabledGzip := publicDAVRequest(router, http.MethodGet, "/dav-public/"+account+"/theme.css", map[string]string{
		"Accept-Encoding": "br, GZip; q=0.5",
	})
	if enabledGzip.Code != http.StatusOK || enabledGzip.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("gzip;q=0.5 response status=%d headers=%v", enabledGzip.Code, enabledGzip.Header())
	}
}

func davProtocolRequest(router http.Handler, account, password, method, requestPath, body string) *httptest.ResponseRecorder {
	return davProtocolRequestWithHeaders(router, account, password, method, requestPath, body, nil)
}

func davProtocolRequestWithHeaders(router http.Handler, account, password, method, requestPath, body string, headers map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, requestPath, strings.NewReader(body))
	req.SetBasicAuth(account, password)
	if method == "PROPFIND" {
		req.Header.Set("Depth", "1")
		req.Header.Set("Content-Type", "application/xml")
	}
	for name, value := range headers {
		req.Header.Set(name, value)
	}
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func resetDAVPasswordForTest(t *testing.T, router http.Handler, token string) string {
	t.Helper()
	response := adminAssetRequest(router, token, http.MethodPost, "/api/webdav/app-password/reset", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("reset password status=%d body=%s", response.Code, response.Body.String())
	}
	var body struct {
		Data struct {
			Password string `json:"app_password"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil || body.Data.Password == "" {
		t.Fatalf("reset password response=%s error=%v", response.Body.String(), err)
	}
	return body.Data.Password
}

func createDAVRateLimitMember(t *testing.T, account string) string {
	t.Helper()
	member := &models.Member{
		Account:     account,
		Password:    "unused-login-password",
		Email:       account + "@example.test",
		Role:        0,
		Status:      1,
		CreateTime:  time.Now(),
		CreateAt:    time.Now().Unix(),
		DefaultHome: models.DefaultHomeNotes,
	}
	if err := member.Insert(); err != nil {
		t.Fatalf("insert rate-limit member %q: %v", account, err)
	}
	if _, err := models.ResetDAVAppPassword(member.MemberID); err != nil {
		t.Fatalf("ResetDAVAppPassword(%q) error = %v", account, err)
	}
	return account
}

func publicDAVRequest(router http.Handler, method, requestPath string, headers map[string]string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, requestPath, nil)
	for name, value := range headers {
		request.Header.Set(name, value)
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}
