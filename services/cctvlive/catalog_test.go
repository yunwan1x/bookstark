package cctvlive

import (
	"encoding/json"
	"testing"
)

func TestChannelOverrides(t *testing.T) {
	for _, invalid := range []string{`{"no-channel":["https://example.org/live.m3u8"]}`, `{"10001":["10013-1"]}`, `{"10001":["http://example.org/live"]}`, `{"10001":[]}`, `null`} {
		if _, err := Catalog(invalid); err == nil {
			t.Fatalf("accepted %s", invalid)
		}
	}
	defaults, err := Catalog("{}")
	if err != nil || string(defaults) != string(defaultCatalog) {
		t.Fatal("empty configuration changed defaults")
	}
	updated, err := Catalog(`{"10001":["https://example.org/live.m3u8","10001-3"]}`)
	if err != nil {
		t.Fatal(err)
	}
	var catalog struct {
		Channels []struct {
			ID, PreferredSourceID string
			Sources               []struct{ ID, URL, Protocol string }
		}
	}
	if err := json.Unmarshal(updated, &catalog); err != nil {
		t.Fatal(err)
	}
	c := catalog.Channels[0]
	if len(catalog.Channels) != 56 || c.ID != "10001" || len(c.Sources) != 2 || c.Sources[0].ID != c.PreferredSourceID || c.Sources[0].URL != "https://example.org/live.m3u8" || c.Sources[1].Protocol != "cctv" {
		t.Fatal(c)
	}
}
