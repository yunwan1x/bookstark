package models

import (
	"strings"
	"testing"
)

func TestValidateRichDocumentAcceptsSystemImageURL(t *testing.T) {
	content := `{"schema":"bookstark-richdoc","schema_version":1,"editor_version":"0.9.137","data":{"main":[{"type":"image","value":"/upload-files/editor/example.webp","width":320,"height":200}]},"options":{},"comments":[]}`
	if err := ValidateRichDocument(content); err != nil {
		t.Fatalf("ValidateRichDocument() error = %v", err)
	}
}

func TestValidateRichDocumentDoesNotMistakePlainTextForImage(t *testing.T) {
	content := `{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"data:image/png is discussed here; blob: is also text"}]},"options":{},"comments":[]}`
	if err := ValidateRichDocument(content); err != nil {
		t.Fatalf("ValidateRichDocument() rejected ordinary text: %v", err)
	}
}

func TestValidateRichDocumentRejectsEmbeddedImages(t *testing.T) {
	for _, value := range []string{
		"data:image/png;base64,iVBORw0KGgo=",
		"blob:https://bookstark.example/image-id",
	} {
		content := `{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"type":"table","trList":[{"tdList":[{"value":[{"type":"image","value":"` + value + `"}]}]}]}]},"options":{},"comments":[]}`
		err := ValidateRichDocument(content)
		if err == nil || !strings.Contains(err.Error(), "不能嵌入文档") {
			t.Fatalf("ValidateRichDocument(%q) error = %v, want embedded-image rejection", value, err)
		}
	}
	background := `{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":""}]},"options":{"background":{"image":"data:image/png;base64,iVBORw0KGgo="}},"comments":[]}`
	if err := ValidateRichDocument(background); err == nil {
		t.Fatalf("ValidateRichDocument() accepted an embedded page background")
	}
}

func TestRichDocumentCodecAndPreview(t *testing.T) {
	content := `{"schema":"bookstark-richdoc","schema_version":1,"editor_version":"0.9.137","data":{"header":[],"main":[{"value":"富文档标题"},{"type":"table","trList":[{"tdList":[{"value":[{"value":"表格内容"}]}]}]}],"footer":[]},"options":{},"comments":[]}`
	encoded, err := EncodeContentForType(RichDocumentType, content)
	if err != nil {
		t.Fatalf("EncodeContentForType() error = %v", err)
	}
	if !IsCompressedContent(encoded) {
		t.Fatalf("encoded rich document does not use compressed content format")
	}
	decoded, err := DecodeContentForType(RichDocumentType, encoded)
	if err != nil {
		t.Fatalf("DecodeContentForType() error = %v", err)
	}
	if decoded != content {
		t.Fatalf("decoded content differs from source")
	}
	preview := extractRichDocumentText(encoded)
	if !strings.Contains(preview, "富文档标题") || !strings.Contains(preview, "表格内容") {
		t.Fatalf("preview %q does not contain rich document text", preview)
	}
}

func TestValidateRichDocumentRejectsInvalidEnvelope(t *testing.T) {
	for _, content := range []string{
		`not-json`,
		`{"schema":"other","schema_version":1,"data":{"main":[]}}`,
		`{"schema":"bookstark-richdoc","schema_version":2,"data":{"main":[]}}`,
		`{"schema":"bookstark-richdoc","schema_version":1,"data":{}}`,
	} {
		if err := ValidateRichDocument(content); err == nil {
			t.Fatalf("ValidateRichDocument(%q) unexpectedly succeeded", content)
		}
	}
}
