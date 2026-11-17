package cctvlive

import (
	"context"
	"net/url"
	"os"
	"testing"
	"time"
)

// Opt in only from the intended deployment network; never log signed URLs.
func TestLiveProbe(t *testing.T) {
	if os.Getenv("CCTV_LIVE_PROBE") != "1" {
		t.Skip("set CCTV_LIVE_PROBE=1 to check official metadata from this network")
	}
	resolve := NewResolver()
	for _, channel := range []string{"cctv8k", "cctv164k"} {
		t.Run(channel, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			result, e := resolve(ctx, channel)
			if e != nil {
				t.Fatalf("metadata failed: %v", e)
			}
			u, e := url.Parse(result.URL)
			if e != nil || u.Scheme != "https" || result.Transform != "ysp-tea" {
				t.Fatal("invalid metadata")
			}
			t.Logf("official metadata OK; CDN=%s, transform=%s", u.Hostname(), result.Transform)
		})
	}
}
