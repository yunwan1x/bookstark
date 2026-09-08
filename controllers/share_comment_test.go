package controllers_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"bookstark/models"
)

func shareCommentRequest(router http.Handler, method, path string, body any) *httptest.ResponseRecorder {
	return shareCommentRequestFromIP(router, method, path, body, "192.0.2.1")
}

func shareCommentRequestFromIP(router http.Handler, method, path string, body any, ip string) *httptest.ResponseRecorder {
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	req.RemoteAddr = ip + ":1234"
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-CSRF-Token", "test-csrf")
	req.AddCookie(&http.Cookie{Name: "csrf_token", Value: "test-csrf"})
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func createPublicBlogShareForCommentTest(t *testing.T, router http.Handler, token string) string {
	t.Helper()
	w := adminAssetRequest(router, token, http.MethodPost, "/api/blogs", map[string]any{
		"blog_title":   "Commented article",
		"blog_type":    "article",
		"editor_type":  "markdown",
		"blog_content": "public body",
		"visibility":   1,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/blogs status = %d, body=%s", w.Code, w.Body.String())
	}
	var blogResp struct {
		Data struct {
			BlogID int64 `json:"blog_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &blogResp); err != nil {
		t.Fatalf("decode blog response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/shares", map[string]any{
		"share_type": "blog",
		"target_id":  blogResp.Data.BlogID,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/shares status = %d, body=%s", w.Code, w.Body.String())
	}
	var shareResp struct {
		Data struct {
			ShareIdentify string `json:"share_identify"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &shareResp); err != nil {
		t.Fatalf("decode share response: %v", err)
	}
	if shareResp.Data.ShareIdentify == "" {
		t.Fatalf("share identify is empty: %s", w.Body.String())
	}
	return shareResp.Data.ShareIdentify
}

func TestShareCommentsRespectSystemSwitch(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.SetShareCommentDBPath(filepath.Join(t.TempDir(), "share-comments.db")); err != nil {
		t.Fatalf("SetShareCommentDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = models.CloseShareCommentDB()
		_ = models.SetShareCommentDBPath("")
	})
	identify := createPublicBlogShareForCommentTest(t, router, token)

	if err := models.BatchUpdateSettings(map[string]string{"share_comments_enabled": "0"}); err != nil {
		t.Fatalf("disable comments setting: %v", err)
	}
	w := shareCommentRequest(router, http.MethodPost, "/api/shares/"+identify+"/comments", map[string]any{
		"author_name": "Guest",
		"content":     "disabled comment",
	})
	if w.Code != http.StatusForbidden {
		t.Fatalf("POST disabled comments status = %d, want 403; body=%s", w.Code, w.Body.String())
	}

	if err := models.BatchUpdateSettings(map[string]string{"share_comments_enabled": "1"}); err != nil {
		t.Fatalf("enable comments setting: %v", err)
	}
	w = shareCommentRequest(router, http.MethodPost, "/api/shares/"+identify+"/comments", map[string]any{
		"author_name": "Guest",
		"content":     "visible comment",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST enabled comments status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var createResp struct {
		Data struct {
			CommentID int64 `json:"comment_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createResp); err != nil {
		t.Fatalf("decode create comment response: %v", err)
	}
	if createResp.Data.CommentID == 0 {
		t.Fatalf("created comment id = 0; body=%s", w.Body.String())
	}

	w = shareCommentRequest(router, http.MethodGet, "/api/shares/"+identify+"/comments", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET comments status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "visible comment") {
		t.Fatalf("GET comments missing created content: %s", w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodDelete, "/api/share-comments/"+itoa(createResp.Data.CommentID)+"?identify="+identify, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("DELETE comment as share owner status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	w = shareCommentRequest(router, http.MethodGet, "/api/shares/"+identify+"/comments", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET comments after delete status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "visible comment") {
		t.Fatalf("deleted comment still listed: %s", w.Body.String())
	}

	time.Sleep(10 * time.Millisecond)
}

func TestShareCommentsReturnFlatReplies(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.SetShareCommentDBPath(filepath.Join(t.TempDir(), "share-comments.db")); err != nil {
		t.Fatalf("SetShareCommentDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = models.CloseShareCommentDB()
		_ = models.SetShareCommentDBPath("")
	})
	if err := models.BatchUpdateSettings(map[string]string{"share_comments_enabled": "1"}); err != nil {
		t.Fatalf("enable comments setting: %v", err)
	}
	identify := createPublicBlogShareForCommentTest(t, router, token)

	w := shareCommentRequest(router, http.MethodPost, "/api/shares/"+identify+"/comments", map[string]any{
		"author_name": "Root",
		"content":     "root comment",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST root comment status = %d, body=%s", w.Code, w.Body.String())
	}
	var rootResp struct {
		Data struct {
			CommentID int64 `json:"comment_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &rootResp); err != nil {
		t.Fatalf("decode root response: %v", err)
	}

	w = shareCommentRequest(router, http.MethodPost, "/api/shares/"+identify+"/comments", map[string]any{
		"author_name":         "ReplyOne",
		"content":             "reply to root",
		"parent_comment_id":   rootResp.Data.CommentID,
		"reply_to_comment_id": rootResp.Data.CommentID,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST reply status = %d, body=%s", w.Code, w.Body.String())
	}
	var replyResp struct {
		Data struct {
			CommentID         int64  `json:"comment_id"`
			ParentCommentID   int64  `json:"parent_comment_id"`
			RootCommentID     int64  `json:"root_comment_id"`
			ReplyToCommentID  int64  `json:"reply_to_comment_id"`
			ReplyToAuthorName string `json:"reply_to_author_name"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &replyResp); err != nil {
		t.Fatalf("decode reply response: %v", err)
	}
	if replyResp.Data.ParentCommentID != rootResp.Data.CommentID || replyResp.Data.RootCommentID != rootResp.Data.CommentID {
		t.Fatalf("reply response hierarchy mismatch: %#v", replyResp.Data)
	}
	if replyResp.Data.ReplyToAuthorName != "Root" {
		t.Fatalf("ReplyToAuthorName = %q, want Root", replyResp.Data.ReplyToAuthorName)
	}

	w = shareCommentRequest(router, http.MethodGet, "/api/shares/"+identify+"/comments", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET comments status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var listResp struct {
		Data []struct {
			CommentID int64 `json:"comment_id"`
			Replies   []struct {
				CommentID         int64  `json:"comment_id"`
				ParentCommentID   int64  `json:"parent_comment_id"`
				ReplyToAuthorName string `json:"reply_to_author_name"`
				Content           string `json:"content"`
			} `json:"replies"`
		} `json:"data"`
		Total int64 `json:"total"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &listResp); err != nil {
		t.Fatalf("decode list response: %v", err)
	}
	if listResp.Total != 1 || len(listResp.Data) != 1 || len(listResp.Data[0].Replies) != 1 {
		t.Fatalf("unexpected thread response: total=%d data=%#v", listResp.Total, listResp.Data)
	}
	if listResp.Data[0].Replies[0].Content != "reply to root" {
		t.Fatalf("reply content = %q, want reply to root", listResp.Data[0].Replies[0].Content)
	}
}

func TestShareCommentDefaultsGuestAuthorNameToClientIP(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.SetShareCommentDBPath(filepath.Join(t.TempDir(), "share-comments.db")); err != nil {
		t.Fatalf("SetShareCommentDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = models.CloseShareCommentDB()
		_ = models.SetShareCommentDBPath("")
	})
	if err := models.BatchUpdateSettings(map[string]string{"share_comments_enabled": "1"}); err != nil {
		t.Fatalf("enable comments setting: %v", err)
	}
	identify := createPublicBlogShareForCommentTest(t, router, token)

	w := shareCommentRequest(router, http.MethodPost, "/api/shares/"+identify+"/comments", map[string]any{
		"content": "guest ip name",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST guest comment without name status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var resp struct {
		Data struct {
			AuthorName string `json:"author_name"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.Data.AuthorName != "192.0.2.1" {
		t.Fatalf("AuthorName = %q, want client IP 192.0.2.1", resp.Data.AuthorName)
	}
}

func TestShareCommentMaxLengthSettingRejectsLongContent(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.SetShareCommentDBPath(filepath.Join(t.TempDir(), "share-comments.db")); err != nil {
		t.Fatalf("SetShareCommentDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = models.CloseShareCommentDB()
		_ = models.SetShareCommentDBPath("")
	})
	if err := models.BatchUpdateSettings(map[string]string{
		"share_comments_enabled":   "1",
		"share_comment_max_length": "100",
	}); err != nil {
		t.Fatalf("update comment settings: %v", err)
	}
	identify := createPublicBlogShareForCommentTest(t, router, token)

	w := shareCommentRequestFromIP(router, http.MethodPost, "/api/shares/"+identify+"/comments", map[string]any{
		"author_name": "Guest",
		"content":     strings.Repeat("字", 101),
	}, "198.51.100.10")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("POST over max length status = %d, want 400; body=%s", w.Code, w.Body.String())
	}

	w = shareCommentRequestFromIP(router, http.MethodPost, "/api/shares/"+identify+"/comments", map[string]any{
		"author_name": "Guest",
		"content":     strings.Repeat("字", 100),
	}, "198.51.100.11")
	if w.Code != http.StatusOK {
		t.Fatalf("POST at max length status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
}

func TestAdminShareCommentsListAndHardDelete(t *testing.T) {
	router, token := initAssetControllerTest(t)
	if err := models.SetShareCommentDBPath(filepath.Join(t.TempDir(), "share-comments.db")); err != nil {
		t.Fatalf("SetShareCommentDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = models.CloseShareCommentDB()
		_ = models.SetShareCommentDBPath("")
	})
	if err := models.BatchUpdateSettings(map[string]string{"share_comments_enabled": "1"}); err != nil {
		t.Fatalf("enable comments setting: %v", err)
	}
	identify := createPublicBlogShareForCommentTest(t, router, token)
	detail, err := models.GetShareDetailByIdentify(identify)
	if err != nil {
		t.Fatalf("GetShareDetailByIdentify() error = %v", err)
	}
	root, err := models.CreateShareComment(models.ShareCommentCreate{
		TargetType:    detail.ShareType,
		TargetID:      detail.TargetID,
		ShareIdentify: identify,
		AuthorName:    "Root",
		Content:       "admin managed root",
	})
	if err != nil {
		t.Fatalf("CreateShareComment(root) error = %v", err)
	}
	if _, err := models.CreateShareComment(models.ShareCommentCreate{
		TargetType:       detail.ShareType,
		TargetID:         detail.TargetID,
		ShareIdentify:    identify,
		AuthorName:       "Reply",
		Content:          "admin managed reply",
		ParentCommentID:  root.CommentID,
		ReplyToCommentID: root.CommentID,
	}); err != nil {
		t.Fatalf("CreateShareComment(reply) error = %v", err)
	}

	w := adminAssetRequest(router, token, http.MethodGet, "/api/admin/share-comments?keyword=managed&page=1&page_size=20", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET admin comments status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var listResp struct {
		Data []struct {
			CommentID     int64  `json:"comment_id"`
			Content       string `json:"content"`
			ShareIdentify string `json:"share_identify"`
			Status        string `json:"status"`
		} `json:"data"`
		Total int64 `json:"total"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &listResp); err != nil {
		t.Fatalf("decode admin comments response: %v", err)
	}
	if listResp.Total != 2 || len(listResp.Data) != 2 {
		t.Fatalf("admin comments total/items = %d/%d, want 2/2; body=%s", listResp.Total, len(listResp.Data), w.Body.String())
	}
	if listResp.Data[0].ShareIdentify == "" || listResp.Data[0].Status != "visible" {
		t.Fatalf("admin comment payload missing share/status details: %#v", listResp.Data[0])
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/admin/share-comments/delete", map[string]any{
		"comment_ids": []int64{root.CommentID},
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST admin hard delete status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/admin/share-comments?keyword=managed&page=1&page_size=20", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET admin comments after delete status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "admin managed") {
		t.Fatalf("hard-deleted comments still listed: %s", w.Body.String())
	}
}

func TestUpdateSettingsValidatesShareCommentMaxLength(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", map[string]any{
		"share_comment_max_length": "99",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("PUT comment max length below range status = %d, want 400; body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", map[string]any{
		"share_comment_max_length": "5001",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("PUT comment max length above range status = %d, want 400; body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", map[string]any{
		"share_comment_max_length": "2000",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("PUT valid comment max length status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
}

func TestUpdateSettingsValidatesWebRTCSignalingSettings(t *testing.T) {
	router, token := initAssetControllerTest(t)

	cases := []map[string]any{
		{"webrtc_signaling_default_url": "https://example.com/ws"},
		{"webrtc_signaling_allowed_origins": "file://"},
		{"webrtc_signaling_stun_urls": "https://stun.example.com"},
		{"webrtc_signaling_turn_url": "https://turn.example.com"},
		{"webrtc_signaling_max_peers": "1"},
		{"webrtc_signaling_max_message_kb": "7"},
	}
	for _, body := range cases {
		w := adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", body)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("PUT invalid WebRTC setting %#v status = %d, want 400; body=%s", body, w.Code, w.Body.String())
		}
	}

	w := adminAssetRequest(router, token, http.MethodPut, "/api/admin/settings", map[string]any{
		"webrtc_signaling_enabled":          "1",
		"webrtc_signaling_default_url":      "wss://books.example.com/api/webrtc-signaling/ws",
		"webrtc_signaling_max_peers":        "16",
		"webrtc_signaling_max_message_kb":   "64",
		"webrtc_signaling_allow_local_file": "1",
		"webrtc_signaling_allowed_origins":  "https://tools.example.com",
		"webrtc_signaling_stun_urls":        "stun:stun.l.google.com:19302",
		"webrtc_signaling_turn_url":         "turn:turn.example.com:3478",
		"webrtc_signaling_turn_username":    "user",
		"webrtc_signaling_turn_credential":  "secret",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("PUT valid WebRTC settings status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
}
