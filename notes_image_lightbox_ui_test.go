package main

import (
	"os"
	"strings"
	"testing"
)

func TestNotesImageLightboxHooks(t *testing.T) {
	templateBytes, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(templates/notes.html) error = %v", err)
	}
	jsBytes, err := os.ReadFile("static/js/notes.js")
	if err != nil {
		t.Fatalf("ReadFile(static/js/notes.js) error = %v", err)
	}
	cssBytes, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(static/css/notes.css) error = %v", err)
	}

	template := string(templateBytes)
	for _, required := range []string{
		`id="noteImageLightboxOverlay"`,
		`id="noteImageLightboxImg"`,
		`id="noteImageLightboxPrevBtn"`,
		`id="noteImageLightboxNextBtn"`,
		`notesApp.closeImageLightbox()`,
		`notesApp.showAdjacentImageLightbox(-1)`,
		`notesApp.showAdjacentImageLightbox(1)`,
	} {
		if !strings.Contains(template, required) {
			t.Fatalf("notes image lightbox template hook missing %q", required)
		}
	}

	js := string(jsBytes)
	for _, required := range []string{
		`NotesApp.prototype.prepareNoteCardImages = function(card)`,
		`NotesApp.prototype._getNoteImageLightboxItems = function()`,
		`NotesApp.prototype.openImageLightbox = function(targetImg)`,
		`NotesApp.prototype.showAdjacentImageLightbox = function(delta)`,
		`NotesApp.prototype.closeImageLightbox = function()`,
		`NotesApp.prototype._trapImageLightbox = function(on)`,
		`#notesTimeline .note-card .note-content img`,
		`BookStarkScrollLock.lock('notes-image-lightbox')`,
		`BookStarkScrollLock.unlock('notes-image-lightbox')`,
	} {
		if !strings.Contains(js, required) {
			t.Fatalf("notes image lightbox js hook missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`#noteViewerContent img`,
		`.article-card .note-content img`,
	} {
		if strings.Contains(js, forbidden) {
			t.Fatalf("image lightbox should not collect forbidden image scope %q", forbidden)
		}
	}
	noteViewerTrap := strings.Index(js, `NotesApp.prototype._trapNoteViewer = function(on)`)
	imageTrap := strings.Index(js, `NotesApp.prototype._trapImageLightbox = function(on)`)
	if noteViewerTrap < 0 || imageTrap < 0 {
		t.Fatalf("both note viewer and image lightbox keyboard traps must exist")
	}
	if strings.Count(js, `if (e.key === 'ArrowLeft')`) < 2 {
		t.Fatalf("both note viewer and image lightbox should handle ArrowLeft")
	}
	if strings.Count(js, `if (e.key === 'ArrowRight')`) < 2 {
		t.Fatalf("both note viewer and image lightbox should handle ArrowRight")
	}

	css := string(cssBytes)
	for _, required := range []string{
		`.note-content img.note-image-lightbox-trigger`,
		`#noteImageLightboxOverlay.note-image-lightbox-overlay`,
		`.note-image-lightbox-img`,
		`.note-image-lightbox-nav`,
		`.note-image-lightbox-counter`,
		`@media (max-width: 640px)`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("notes image lightbox css hook missing %q", required)
		}
	}
}
