package main

import (
	"os"
	"strings"
	"testing"
)

func TestShareViewCommentsJumpUsesContentScrollerAndKeepsMobilePadding(t *testing.T) {
	tpl, err := os.ReadFile("templates/share_view.html")
	if err != nil {
		t.Fatalf("ReadFile(share_view.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`function scrollToShareComments()`,
		`openShareCommentsPanel();`,
		`#preview-wrap { padding: 16px 16px !important; }`,
		`#preview-area .cherry-previewer { padding-left: 0 !important; padding-right: 0 !important; }`,
		`body.share-reader-fullscreen #share-comments`,
		`function writeShareClipboard(text, btn)`,
		`navigator.clipboard.writeText(value).then(done).catch(fallback);`,
		`class="share-comments share-comments-panel"`,
		`data-comments-lazy="1" hidden`,
		`class="share-comments-backdrop"`,
		`.share-comments-panel[hidden] { display: none !important; }`,
		`@keyframes shareCommentsSlideDown`,
		`animation: shareCommentsSlideDown 0.22s ease-out;`,
		`border-radius: 0 0 12px 12px;`,
		`max-height: calc(var(--bs-vvh, 100dvh) - 8px);`,
		`overscroll-behavior: contain;`,
		`.share-comment-delete,
        .share-comment-reply`,
		`width: 28px;
            height: 28px;`,
		`justify-content: center;`,
		`function openShareCommentsPanel()`,
		`function closeShareCommentsPanel()`,
		`BookStarkShareComments.init(comments);`,
		`#content-scroll.html-mode { overflow: hidden !important; }`,
		`#content-scroll.html-mode #preview-wrap`,
		`#content-scroll.html-mode #preview-area`,
		`#content-scroll.html-mode .html-preview-iframe`,
		`onFullpage: type === 'html' ? null : function()`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share view comment UI behavior missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`comments.scrollIntoView({ behavior: 'smooth', block: 'start' });`,
		`scroller.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });`,
		`navigator.clipboard.writeText(window.location.href).then(function()`,
		`navigator.clipboard.writeText(shareContent).then(function()`,
		`#content-scroll.html-mode.has-share-comments { overflow-y: auto !important; }`,
		`#content-scroll.html-mode.has-share-comments #share-comments`,
		`share-html-window-scroll`,
		`function setShareWindowScrollMode(enabled)`,
		`#content-scroll.html-mode { overflow-y: auto !important; }`,
		`onFullpage: onFullpage`,
		`top: auto;
                left: 8px;`,
		`bottom: 8px;
                width: auto;`,
		"#preview-wrap { padding: 0 !important; }\n        }\n        /* Non-markdown types",
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("share view comment UI still contains obsolete behavior %q", forbidden)
		}
	}
}
