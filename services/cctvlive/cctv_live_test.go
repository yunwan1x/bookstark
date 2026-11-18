package cctvlive

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestProtocolGolden(t *testing.T) {
	// Captured from the previously runtime-tested JS protocol implementation.
	const guid = "abcdefgh_12345678901"
	want := "--01A48AD54C47486F5939CB6AB3FB4FDE2A91EC3EF7A1F3464EB769DA82BE4D397EF13208E4E5E7D02AD819F3DF1479C4030251C0B0B3F929124558A118DF667FBC4FFAD9DF8C645AC6739F21A2CF98C057D3659CC5A86EDFA1EE02D18299A4142438CC6F80A2304E993E2144C4B1BC19F8DC9993F5E1CD85FFF864A45B0137406E2028AA993630131CAA9AA998CFD096F83FE0EB604B5E3123A7CF0E76807FCC39"
	if got := ckey("2027249301", guid, 1794800000); got != want {
		t.Fatal("cKey differs from tested JS")
	}
	if got := ticket("600099502", guid, "0123456789", 1794800000); got != "5c40d99c3945f9087e0e99bac41629eefb56797bece2df021c9d3155dab5fda7a7d0d09d4536fa940fa186f612b12d17c1efd3a998c545a7ec4c105f7bb5" {
		t.Fatal("ticket differs")
	}
}

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestOfficialFlow(t *testing.T) {
	for _, region := range []bool{false, true} {
		t.Run(map[bool]string{false: "success", true: "region403"}[region], func(t *testing.T) {
			stage := 0
			client := &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
				stage++
				var response string
				if r.Header.Get("Origin") != "https://www.yangshipin.cn" || !strings.Contains(r.Header.Get("Cookie"), "guid=") {
					t.Fatal("missing official anonymous headers")
				}
				switch stage {
				case 1:
					if r.URL.String() != authURL || r.Method != "POST" {
						t.Fatal("auth route")
					}
					body, _ := io.ReadAll(r.Body)
					v, _ := url.ParseQuery(string(body))
					if v.Get("pid") != "600099502" || len(v.Get("signature")) != 32 {
						t.Fatal("auth fields")
					}
					response = `{"code":0,"data":{"token":"auth-test","ts":1794800000}}`
				case 2:
					if r.URL.Host != "h5access.yangshipin.cn" || r.URL.Query().Get("ts") != "1794800000000" {
						t.Fatal("token request")
					}
					response = `{"ret":0,"data":{"token":"sdk-test"}}`
				case 3:
					if r.URL.String() != liveURL || r.Header.Get("yspplayertoken") != "auth-test" || r.Header.Get("yspsdksign") == "" {
						t.Fatal("live headers")
					}
					var f map[string]any
					json.NewDecoder(r.Body).Decode(&f)
					if f["cnlid"] != "2027249301" || f["signature"] == nil {
						t.Fatal("live body")
					}
					response = `{"code":0,"data":{"iretcode":0,"playurl":"https://cdn.example.test/live.m3u8?x=1","extended_param":"&y=2","encrypt":2}}`
					if region {
						response = `{"code":0,"data":{"iretcode":5,"errinfo":"private upstream detail"}}`
					}
				default:
					t.Fatal("unexpected network request")
				}
				return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(response)), Header: make(http.Header)}, nil
			})}
			result, e := resolver(client)(context.Background(), DefaultIDs("cctv164k"))
			if region {
				var ae *apiError
				if !errors.As(e, &ae) || ae.status != 403 {
					t.Fatalf("expected region403: %v", e)
				}
			} else if e != nil || result.URL != "https://cdn.example.test/live.m3u8?x=1&y=2" || result.Transform != "ysp-tea" {
				t.Fatalf("result mismatch %v", e)
			}
			if stage != 3 {
				t.Fatal("incomplete flow")
			}
		})
	}
}
func req(h http.Handler, target string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", target, nil))
	return w
}
func TestValidationAndCache(t *testing.T) {
	var calls atomic.Int32
	h := newHandler(func(context.Context, OfficialIDs) (Result, error) {
		calls.Add(1)
		return Result{"https://cdn.test/live.m3u8", "ysp-tea"}, nil
	}, time.Second)
	for _, q := range []string{"", "?channel=other", "?channel=cctv8k&url=http://localhost", "?channel=cctv8k&channel=cctv164k", "?channel=cctv8k&bad=%zz"} {
		if w := req(h, "/api/cctv-live/resolve"+q); w.Code != 400 {
			t.Fatal(w.Code)
		}
	}
	if calls.Load() != 0 {
		t.Fatal("invalid request reached upstream")
	}
	for i := 0; i < 2; i++ {
		w := req(h, "/api/cctv-live/resolve?channel=cctv8k")
		if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal(w.Code)
		}
	}
	if calls.Load() != 1 {
		t.Fatal("cache miss")
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("POST", "/api/cctv-live/resolve", nil))
	if w.Code != 405 {
		t.Fatal(w.Code)
	}
	if req(h, "/api/cctv-live/proxy").Code != 404 {
		t.Fatal("proxy route exists")
	}
}
func TestSharedRequestAndCancellation(t *testing.T) {
	started := make(chan struct{})
	cancelled := make(chan struct{})
	var calls atomic.Int32
	h := newHandler(func(ctx context.Context, _ OfficialIDs) (Result, error) {
		calls.Add(1)
		close(started)
		<-ctx.Done()
		close(cancelled)
		return Result{}, ctx.Err()
	}, time.Second)
	ctx1, cancel1 := context.WithCancel(context.Background())
	ctx2, cancel2 := context.WithCancel(context.Background())
	done := make(chan struct{}, 2)
	go func() {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/api/cctv-live/resolve?channel=cctv8k", nil).WithContext(ctx1))
		done <- struct{}{}
	}()
	<-started
	go func() {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/api/cctv-live/resolve?channel=cctv8k", nil).WithContext(ctx2))
		done <- struct{}{}
	}()
	deadline := time.After(time.Second)
	for {
		h.mu.Lock()
		n := h.pending[lookupKey{"cctv8k", DefaultIDs("cctv8k")}].users
		h.mu.Unlock()
		if n == 2 {
			break
		}
		select {
		case <-deadline:
			t.Fatal("second consumer missing")
		default:
			time.Sleep(time.Millisecond)
		}
	}
	cancel1()
	<-done
	select {
	case <-cancelled:
		t.Fatal("cancelled while a consumer remains")
	default:
	}
	cancel2()
	<-done
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("upstream not cancelled")
	}
	if calls.Load() != 1 {
		t.Fatal("not deduplicated")
	}
}
func TestTimeoutAndRegionSanitization(t *testing.T) {
	h := newHandler(func(ctx context.Context, _ OfficialIDs) (Result, error) { <-ctx.Done(); return Result{}, ctx.Err() }, 10*time.Millisecond)
	if w := req(h, "/api/cctv-live/resolve?channel=cctv8k"); w.Code != 504 {
		t.Fatal(w.Code)
	}
	h = newHandler(func(context.Context, OfficialIDs) (Result, error) {
		return Result{}, errAPI(403, "REGION_OR_COPYRIGHT_RESTRICTED")
	}, time.Second)
	if w := req(h, "/api/cctv-live/resolve?channel=cctv164k"); w.Code != 403 || strings.Contains(w.Body.String(), "token") {
		t.Fatal(w.Code)
	}
}

func TestChangedIDsSkipCachedResult(t *testing.T) {
	ids := DefaultIDs("xjws")
	h := newHandler(func(_ context.Context, upstream OfficialIDs) (Result, error) {
		return Result{URL: "https://example.org/" + upstream.PID + "/" + upstream.StreamID}, nil
	}, time.Second)
	h.lookup = func(string) (OfficialIDs, error) { return ids, nil }
	check := func() {
		w := req(h, "/api/cctv-live/resolve?channel=xjws")
		var result Result
		if e := json.Unmarshal(w.Body.Bytes(), &result); e != nil || result.URL != "https://example.org/"+ids.PID+"/"+ids.StreamID {
			t.Fatal(w.Body.String())
		}
	}
	check()
	ids.StreamID = "1234567890"
	check()
	ids.PID = "654321789"
	check()
}
