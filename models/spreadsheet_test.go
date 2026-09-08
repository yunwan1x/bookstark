package models

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestDefaultSpreadsheetIsValidUniverWorkbook(t *testing.T) {
	var snapshot struct {
		AppVersion string                     `json:"appVersion"`
		SheetOrder []string                   `json:"sheetOrder"`
		Sheets     map[string]json.RawMessage `json:"sheets"`
	}
	if err := json.Unmarshal([]byte(DefaultSpreadsheet), &snapshot); err != nil {
		t.Fatalf("DefaultSpreadsheet is not valid JSON: %v", err)
	}
	if snapshot.AppVersion != "0.25.1" {
		t.Fatalf("AppVersion = %q, want 0.25.1", snapshot.AppVersion)
	}
	if len(snapshot.SheetOrder) != 1 || snapshot.Sheets[snapshot.SheetOrder[0]] == nil {
		t.Fatalf("default workbook has invalid sheet order: %#v", snapshot.SheetOrder)
	}
}

func TestExtractSpreadsheetTextSupportsUniverSnapshots(t *testing.T) {
	univer := `{"sheetOrder":["sheet-01"],"sheets":{"sheet-01":{"cellData":{"0":{"0":{"v":"标题"},"1":{"v":"结论"}},"1":{"0":{"v":42}}}}}}`
	preview := extractSpreadsheetText(univer)
	for _, want := range []string{"标题", "结论", "42"} {
		if !strings.Contains(preview, want) {
			t.Fatalf("Univer preview %q does not contain %q", preview, want)
		}
	}
}
