package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"bookstark/models"
	"bookstark/services/worldtv"
)

func TestWorldTVBrowser(t *testing.T) {
	runIsolatedBrowser(t, "world_tv_browser_test.cjs", func(t *testing.T) {
		path := filepath.Join(models.UploadBaseDir, "worldtv", "channels.json")
		if e := os.MkdirAll(filepath.Dir(path), 0755); e != nil {
			t.Fatal(e)
		}
		c := worldtv.Catalog{Schema: 1, Source: worldtv.DefaultSource, CheckedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(), Channels: []worldtv.Channel{
			{ID: "nhk", Name: "NHK WORLD-JAPAN", Country: "JP", Group: "Japan", URL: "https://media.example/nhk.m3u8", Language: "en"},
			{ID: "france", Name: "France 24", Country: "FR", Group: "France", URL: "https://media.example/france.m3u8", Language: "fr"},
			{ID: "video", Name: "<img src=x onerror=alert(1)>", Country: "JP", Group: "Japan", URL: "https://www.youtube.com/@test/live", External: true},
		}}
		b, _ := json.Marshal(c)
		if e := os.WriteFile(path, b, 0644); e != nil {
			t.Fatal(e)
		}
	})
}
