package models

import (
	"encoding/json"
	"testing"
)

func TestDefaultPresentationIsValidPPTistData(t *testing.T) {
	content := DefaultPresentation("季度复盘")
	if err := ValidatePresentation(content); err != nil {
		t.Fatalf("ValidatePresentation(default) error = %v", err)
	}
	var doc struct {
		Title  string  `json:"title"`
		Width  int     `json:"width"`
		Height float64 `json:"height"`
		Slides []struct {
			ID       string `json:"id"`
			Elements []any  `json:"elements"`
		} `json:"slides"`
	}
	if err := json.Unmarshal([]byte(content), &doc); err != nil {
		t.Fatalf("default presentation is not JSON: %v", err)
	}
	if doc.Title != "季度复盘" || doc.Width != 1000 || doc.Height != 562.5 {
		t.Fatalf("unexpected presentation metadata: %#v", doc)
	}
	if len(doc.Slides) != 1 || doc.Slides[0].ID == "" {
		t.Fatalf("default presentation must contain one identified slide")
	}
}

func TestValidatePresentationRejectsInvalidSnapshots(t *testing.T) {
	for _, content := range []string{
		"",
		`{}`,
		`{"width":1000,"height":562.5,"slides":[]}`,
		`{"width":1000,"height":562.5,"slides":[{"elements":[]}]}`,
		`{"width":1000,"height":562.5,"slides":[{"id":"a","elements":{}}]}`,
	} {
		if err := ValidatePresentation(content); err == nil {
			t.Fatalf("ValidatePresentation(%q) unexpectedly succeeded", content)
		}
	}
}
