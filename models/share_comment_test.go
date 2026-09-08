package models

import (
	"path/filepath"
	"testing"
)

func initShareCommentTestDB(t *testing.T) string {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "share-comments.db")
	if err := SetShareCommentDBPath(dbPath); err != nil {
		t.Fatalf("SetShareCommentDBPath() error = %v", err)
	}
	t.Cleanup(func() {
		_ = CloseShareCommentDB()
		_ = SetShareCommentDBPath(defaultShareCommentDBPath)
	})
	return dbPath
}

func TestShareCommentsUseSeparateEntityScopedDB(t *testing.T) {
	initShareCommentTestDB(t)

	comment, err := CreateShareComment(ShareCommentCreate{
		TargetType:     "blog",
		TargetID:       42,
		ShareIdentify:  "share-alpha",
		AuthorMemberID: 0,
		AuthorName:     "Guest",
		AuthorEmail:    "guest@example.com",
		Content:        "这篇文章写得很好。",
		IPHash:         "ip-a",
		UserAgentHash:  "ua-a",
	})
	if err != nil {
		t.Fatalf("CreateShareComment() error = %v", err)
	}
	if comment.CommentID == 0 {
		t.Fatalf("created comment id = 0")
	}

	items, total, err := ListShareComments("blog", 42, 1, 20)
	if err != nil {
		t.Fatalf("ListShareComments() error = %v", err)
	}
	if total != 1 || len(items) != 1 {
		t.Fatalf("total/items = %d/%d, want 1/1", total, len(items))
	}
	if items[0].Content != "这篇文章写得很好。" || items[0].ShareIdentify != "share-alpha" {
		t.Fatalf("unexpected comment: %#v", items[0])
	}

	if err := SoftDeleteShareComment(comment.CommentID); err != nil {
		t.Fatalf("SoftDeleteShareComment() error = %v", err)
	}
	items, total, err = ListShareComments("blog", 42, 1, 20)
	if err != nil {
		t.Fatalf("ListShareComments(after delete) error = %v", err)
	}
	if total != 0 || len(items) != 0 {
		t.Fatalf("after delete total/items = %d/%d, want 0/0", total, len(items))
	}
}

func TestCreateShareCommentRejectsScriptableInput(t *testing.T) {
	initShareCommentTestDB(t)

	for _, tc := range []struct {
		name  string
		input ShareCommentCreate
	}{
		{
			name: "script content",
			input: ShareCommentCreate{
				TargetType:    "blog",
				TargetID:      42,
				ShareIdentify: "share-alpha",
				AuthorName:    "Guest",
				Content:       `<img src=x onerror=alert(1)>`,
			},
		},
		{
			name: "javascript author",
			input: ShareCommentCreate{
				TargetType:    "blog",
				TargetID:      42,
				ShareIdentify: "share-alpha",
				AuthorName:    `javascript:alert(1)`,
				Content:       "hello",
			},
		},
		{
			name: "html email payload",
			input: ShareCommentCreate{
				TargetType:    "blog",
				TargetID:      42,
				ShareIdentify: "share-alpha",
				AuthorName:    "Guest",
				AuthorEmail:   `guest@example.com"><script>alert(1)</script>`,
				Content:       "hello",
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := CreateShareComment(tc.input); err == nil {
				t.Fatalf("CreateShareComment() error = nil, want scriptable input rejected")
			}
		})
	}
}

func TestCreateShareCommentNormalizesControlCharacters(t *testing.T) {
	initShareCommentTestDB(t)

	comment, err := CreateShareComment(ShareCommentCreate{
		TargetType:    "blog",
		TargetID:      42,
		ShareIdentify: "share-alpha",
		AuthorName:    "Guest\x00Name",
		Content:       "hello\x00\nworld",
	})
	if err != nil {
		t.Fatalf("CreateShareComment() error = %v", err)
	}
	if comment.AuthorName != "GuestName" {
		t.Fatalf("AuthorName = %q, want control character removed", comment.AuthorName)
	}
	if comment.Content != "hello\nworld" {
		t.Fatalf("Content = %q, want NUL removed but newline preserved", comment.Content)
	}
}

func TestShareCommentRepliesAreFlatUnderRootComment(t *testing.T) {
	initShareCommentTestDB(t)

	root, err := CreateShareComment(ShareCommentCreate{
		TargetType:    "blog",
		TargetID:      42,
		ShareIdentify: "share-alpha",
		AuthorName:    "Root",
		Content:       "root comment",
	})
	if err != nil {
		t.Fatalf("CreateShareComment(root) error = %v", err)
	}
	if root.ParentCommentID != 0 || root.RootCommentID != root.CommentID {
		t.Fatalf("root hierarchy = parent:%d root:%d id:%d, want parent 0 and root self", root.ParentCommentID, root.RootCommentID, root.CommentID)
	}

	reply, err := CreateShareComment(ShareCommentCreate{
		TargetType:        "blog",
		TargetID:          42,
		ShareIdentify:     "share-alpha",
		AuthorName:        "ReplyOne",
		Content:           "reply to root",
		ParentCommentID:   root.CommentID,
		ReplyToCommentID:  root.CommentID,
		ReplyToAuthorName: root.AuthorName,
	})
	if err != nil {
		t.Fatalf("CreateShareComment(reply) error = %v", err)
	}
	if reply.ParentCommentID != root.CommentID || reply.RootCommentID != root.CommentID || reply.ReplyToCommentID != root.CommentID {
		t.Fatalf("reply hierarchy mismatch: %#v", reply)
	}

	nestedReply, err := CreateShareComment(ShareCommentCreate{
		TargetType:        "blog",
		TargetID:          42,
		ShareIdentify:     "share-alpha",
		AuthorName:        "ReplyTwo",
		Content:           "reply to reply",
		ParentCommentID:   root.CommentID,
		ReplyToCommentID:  reply.CommentID,
		ReplyToAuthorName: reply.AuthorName,
	})
	if err != nil {
		t.Fatalf("CreateShareComment(nested reply) error = %v", err)
	}
	if nestedReply.ParentCommentID != root.CommentID || nestedReply.RootCommentID != root.CommentID || nestedReply.ReplyToCommentID != reply.CommentID {
		t.Fatalf("nested reply should stay flat under root: %#v", nestedReply)
	}

	threads, total, err := ListShareCommentThreads("blog", 42, 1, 20)
	if err != nil {
		t.Fatalf("ListShareCommentThreads() error = %v", err)
	}
	if total != 1 || len(threads) != 1 {
		t.Fatalf("total/threads = %d/%d, want 1/1", total, len(threads))
	}
	if len(threads[0].Replies) != 2 {
		t.Fatalf("reply count = %d, want 2", len(threads[0].Replies))
	}
	if threads[0].Replies[1].ReplyToAuthorName != "ReplyOne" {
		t.Fatalf("nested reply ReplyToAuthorName = %q, want ReplyOne", threads[0].Replies[1].ReplyToAuthorName)
	}
}

func TestShareCommentReplyRejectsDifferentTargetParent(t *testing.T) {
	initShareCommentTestDB(t)

	other, err := CreateShareComment(ShareCommentCreate{
		TargetType:    "blog",
		TargetID:      99,
		ShareIdentify: "share-beta",
		AuthorName:    "Other",
		Content:       "other target",
	})
	if err != nil {
		t.Fatalf("CreateShareComment(other) error = %v", err)
	}

	_, err = CreateShareComment(ShareCommentCreate{
		TargetType:       "blog",
		TargetID:         42,
		ShareIdentify:    "share-alpha",
		AuthorName:       "Guest",
		Content:          "bad reply",
		ParentCommentID:  other.CommentID,
		ReplyToCommentID: other.CommentID,
	})
	if err == nil {
		t.Fatalf("CreateShareComment() error = nil, want different target parent rejected")
	}
}

func TestListShareCommentsAdminIncludesVisibleAndDeletedComments(t *testing.T) {
	initShareCommentTestDB(t)

	first, err := CreateShareComment(ShareCommentCreate{
		TargetType:    "blog",
		TargetID:      42,
		ShareIdentify: "share-alpha",
		AuthorName:    "Root",
		Content:       "visible root",
	})
	if err != nil {
		t.Fatalf("CreateShareComment(first) error = %v", err)
	}
	second, err := CreateShareComment(ShareCommentCreate{
		TargetType:    "document",
		TargetID:      7,
		ShareIdentify: "share-beta",
		AuthorName:    "Guest",
		Content:       "deleted document comment",
	})
	if err != nil {
		t.Fatalf("CreateShareComment(second) error = %v", err)
	}
	if err := SoftDeleteShareComment(second.CommentID); err != nil {
		t.Fatalf("SoftDeleteShareComment() error = %v", err)
	}

	items, total, err := ListShareCommentsAdmin(1, 20, "document", "deleted", "")
	if err != nil {
		t.Fatalf("ListShareCommentsAdmin() error = %v", err)
	}
	if total != 1 || len(items) != 1 || items[0].CommentID != second.CommentID || items[0].Status != "deleted" {
		t.Fatalf("deleted document filter returned total=%d items=%#v, want second deleted comment", total, items)
	}

	items, total, err = ListShareCommentsAdmin(1, 20, "root", "visible", "blog")
	if err != nil {
		t.Fatalf("ListShareCommentsAdmin(blog visible) error = %v", err)
	}
	if total != 1 || len(items) != 1 || items[0].CommentID != first.CommentID {
		t.Fatalf("visible blog search returned total=%d items=%#v, want first comment", total, items)
	}
}

func TestHardDeleteShareCommentRootRemovesReplies(t *testing.T) {
	initShareCommentTestDB(t)

	root, err := CreateShareComment(ShareCommentCreate{
		TargetType:    "blog",
		TargetID:      42,
		ShareIdentify: "share-alpha",
		AuthorName:    "Root",
		Content:       "root comment",
	})
	if err != nil {
		t.Fatalf("CreateShareComment(root) error = %v", err)
	}
	reply, err := CreateShareComment(ShareCommentCreate{
		TargetType:       "blog",
		TargetID:         42,
		ShareIdentify:    "share-alpha",
		AuthorName:       "Reply",
		Content:          "reply comment",
		ParentCommentID:  root.CommentID,
		ReplyToCommentID: root.CommentID,
	})
	if err != nil {
		t.Fatalf("CreateShareComment(reply) error = %v", err)
	}

	affected, err := HardDeleteShareComments([]int64{root.CommentID})
	if err != nil {
		t.Fatalf("HardDeleteShareComments(root) error = %v", err)
	}
	if affected != 2 {
		t.Fatalf("affected rows = %d, want 2", affected)
	}
	if _, err := GetShareCommentByID(root.CommentID); err == nil {
		t.Fatalf("root comment still exists after hard delete")
	}
	if _, err := GetShareCommentByID(reply.CommentID); err == nil {
		t.Fatalf("reply comment still exists after root hard delete")
	}
}

func TestHardDeleteShareCommentReplyKeepsRoot(t *testing.T) {
	initShareCommentTestDB(t)

	root, err := CreateShareComment(ShareCommentCreate{
		TargetType:    "blog",
		TargetID:      42,
		ShareIdentify: "share-alpha",
		AuthorName:    "Root",
		Content:       "root comment",
	})
	if err != nil {
		t.Fatalf("CreateShareComment(root) error = %v", err)
	}
	reply, err := CreateShareComment(ShareCommentCreate{
		TargetType:       "blog",
		TargetID:         42,
		ShareIdentify:    "share-alpha",
		AuthorName:       "Reply",
		Content:          "reply comment",
		ParentCommentID:  root.CommentID,
		ReplyToCommentID: root.CommentID,
	})
	if err != nil {
		t.Fatalf("CreateShareComment(reply) error = %v", err)
	}

	affected, err := HardDeleteShareComments([]int64{reply.CommentID})
	if err != nil {
		t.Fatalf("HardDeleteShareComments(reply) error = %v", err)
	}
	if affected != 1 {
		t.Fatalf("affected rows = %d, want 1", affected)
	}
	if _, err := GetShareCommentByID(reply.CommentID); err == nil {
		t.Fatalf("reply comment still exists after hard delete")
	}
	if _, err := GetShareCommentByID(root.CommentID); err != nil {
		t.Fatalf("root comment should remain after reply hard delete: %v", err)
	}
}
