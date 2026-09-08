package main

import (
	"os"
	"strings"
	"testing"
)

func TestSharesNoteAuthorUsesTagWithoutAvatar(t *testing.T) {
	tpl, err := os.ReadFile("templates/shares.html")
	if err != nil {
		t.Fatalf("ReadFile(shares.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		".sh-note-author-tag",
		`'<div class="sh-note-body">'`,
		`<span class="sh-note-author-tag">'+escHtml(s.author)+'</span>`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share note author tag UI missing %q", required)
		}
	}
	for _, forbidden := range []string{
		".sh-note-avatar",
		`'<div class="sh-note-avatar `,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("share note card should not render author avatar, found %q", forbidden)
		}
	}
}

func TestSharesArticleExcerptClampsWithoutFlexStretch(t *testing.T) {
	tpl, err := os.ReadFile("templates/shares.html")
	if err != nil {
		t.Fatalf("ReadFile(shares.html) error = %v", err)
	}
	text := string(tpl)

	required := `.sh-card-footer { display: flex; align-items: center; gap: 5px; margin-top: auto;`
	if !strings.Contains(text, required) {
		t.Fatalf("share article footer should align cards without stretching the clamped excerpt, missing %q", required)
	}
	forbidden := `.sh-card-excerpt { font-size: 12px; color: var(--color-text-secondary); line-height: 1.65; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; flex: 1;`
	if strings.Contains(text, forbidden) {
		t.Fatalf("share article excerpt must not use flex growth because it exposes a clipped partial line")
	}
}

func TestSharesNoteRowsReuseNoteViewerAndImageLightboxControls(t *testing.T) {
	tpl, err := os.ReadFile("templates/shares.html")
	if err != nil {
		t.Fatalf("ReadFile(shares.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		".sh-note-actions",
		`class="sh-note-copy-btn note-copy-btn"`,
		`class="sh-note-fullscreen-btn note-fullscreen-btn"`,
		`#shareNoteViewerOverlay.editor-overlay,`,
		`#shareNoteImageLightboxOverlay.editor-overlay { display: none; position: fixed; inset: 0;`,
		`copyShareNoteContent(\''+noteKeyArg+'\')`,
		`openShareNoteViewer(\''+noteKeyArg+'\')`,
		`prepareShareNoteImages()`,
		`function openShareImageLightbox(targetImg)`,
		`function showAdjacentShareImageLightbox(delta)`,
		`id="shareNoteViewerOverlay"`,
		`id="shareNoteImageLightboxOverlay"`,
		`.note-image-lightbox-trigger`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share note viewer/lightbox support missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`onclick="notesApp.copyNoteContent`,
		`onclick="notesApp.openNoteViewer`,
		`onclick="notesApp.openImageLightbox`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("share page should not depend on notesApp runtime, found %q", forbidden)
		}
	}
}

func TestSharesNoteActionsStayCompactOnMobile(t *testing.T) {
	tpl, err := os.ReadFile("templates/shares.html")
	if err != nil {
		t.Fatalf("ReadFile(shares.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`@media (max-width: 640px)`,
		`.sh-note-header { align-items: center; gap: 4px; flex-wrap: nowrap; }`,
		`.sh-note-time { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }`,
		`.sh-note-actions { margin-left: auto; gap: 0; }`,
		`.note-copy-btn,
            .note-comment-btn,
            .note-fullscreen-btn { width: 28px; height: 28px; min-width: 28px; min-height: 28px; display: inline-flex; align-items: center; justify-content: center; padding: 0; font-size: 13px; }`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("share note mobile action buttons should stay compact, missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`.note-copy-btn,
            .note-comment-btn,
            .note-fullscreen-btn { min-width: 40px; min-height: 40px;`,
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("share note mobile action buttons still use oversized mobile sizing %q", forbidden)
		}
	}
}

func TestSharesNoteTabRendersInlineComments(t *testing.T) {
	tpl, err := os.ReadFile("templates/shares.html")
	if err != nil {
		t.Fatalf("ReadFile(shares.html) error = %v", err)
	}
	text := string(tpl)

	for _, required := range []string{
		`window.__SHARE_COMMENTS_ENABLED__`,
		`window.__SHARE_COMMENT_ACCOUNT__`,
		`/static/js/share-comments.js`,
		`function buildShareCommentsBlock`,
		`buildShareCommentsBlock(s.share_identify`,
		`BookStarkShareComments.init()`,
		`toggleShareNoteComments(this)`,
		`class="sh-note-comment-btn note-comment-btn"`,
		`var commentAction = window.__SHARE_COMMENTS_ENABLED__ ?`,
		`data-comments-lazy="1" hidden`,
		`data-comments-hydrated="0"`,
		`data-share-identify="`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("shares note tab comments support missing %q", required)
		}
	}

	js, err := os.ReadFile("static/js/share-comments.js")
	if err != nil {
		t.Fatalf("ReadFile(share-comments.js) error = %v", err)
	}
	for _, required := range []string{
		`window.BookStarkShareComments`,
		`data-comments-bound`,
		`function hydrate(root)`,
	} {
		if !strings.Contains(string(js), required) {
			t.Fatalf("share comments runtime should support dynamic shares note rendering, missing %q", required)
		}
	}
}
