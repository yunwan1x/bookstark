package main

import (
	"os"
	"strings"
	"testing"
)

func TestShareCommentsSubmitReadsOnlyFormControls(t *testing.T) {
	js, err := os.ReadFile("static/js/share-comments.js")
	if err != nil {
		t.Fatalf("ReadFile(share-comments.js) error = %v", err)
	}
	text := string(js)

	for _, forbidden := range []string{
		`form.querySelector('.share-comment-author, #share-comment-author')`,
		`findInRoot(root, '.share-comment-author, #share-comment-author'`,
		`authorEl.value.trim()`,
		`emailEl.value.trim()`,
		`contentEl.value.trim()`,
		`!window.__SHARE_COMMENT_ACCOUNT__ && !authorName`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("share comments submit should not read ambiguous/non-control field with %q", forbidden)
		}
	}

	for _, required := range []string{
		`function fieldValue(el)`,
		`form.querySelector('input.share-comment-author, #share-comment-author')`,
		`findInRoot(root, 'input.share-comment-author, #share-comment-author'`,
		`root.addEventListener('submit'`,
		`fieldValue(authorEl)`,
		`fieldValue(emailEl)`,
		`fieldValue(contentEl)`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share comments submit missing safe field handling %q", required)
		}
	}
	if strings.Contains(text, `form.addEventListener('submit'`) {
		t.Fatalf("dynamic reply forms require delegated submit handling on the comments root")
	}
}

func TestShareCommentsSupportsFlatReplyUI(t *testing.T) {
	js, err := os.ReadFile("static/js/share-comments.js")
	if err != nil {
		t.Fatalf("ReadFile(share-comments.js) error = %v", err)
	}
	text := string(js)

	for _, required := range []string{
		`class="share-comment-reply"`,
		`class="share-comment-replies"`,
		`class="share-comment-reply-context"`,
		`data-parent-comment-id`,
		`data-reply-to-comment-id`,
		`reply_to_comment_id`,
		`parent_comment_id`,
		`reply_to_author_name`,
		`share_comments.reply`,
		`share_comments.reply_to_comment`,
		`share_comments.reply_to_user`,
		`toggleReplyForm`,
		`renderReplyForm`,
		`renderReplies`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share comments reply UI missing %q", required)
		}
	}
}

func TestShareCommentsHydratesLazyPanelsOnDemand(t *testing.T) {
	js, err := os.ReadFile("static/js/share-comments.js")
	if err != nil {
		t.Fatalf("ReadFile(share-comments.js) error = %v", err)
	}
	text := string(js)
	for _, required := range []string{
		`function commentsMarkup()`,
		`function hydrate(root)`,
		`function toggle(root, trigger)`,
		`data-comments-hydrated`,
		`data-share-comments-toggle`,
		`hydrate: hydrate`,
		`toggle: toggle`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share comments lazy hydration missing %q", required)
		}
	}
}
