package cctvlive

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const appID = "519748109"
const platform = "5910204"
const authURL = "https://player-api.yangshipin.cn/v1/player/auth"
const tokenURL = "https://h5access.yangshipin.cn/web/open/token"
const liveURL = "https://player-api.yangshipin.cn/v1/player/get_live_info"
const ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/159.0.8154.6 Safari/537.36"

var channels = map[string][2]string{"cctv8k": {"2026774101", "600156816"}, "cctv164k": {"2027249301", "600099502"}}

// Result contains metadata only. This package never downloads playlists or video.
type Result struct {
	URL       string `json:"url"`
	Transform string `json:"transform"`
}
type apiError struct {
	status int
	code   string
}

func (e *apiError) Error() string          { return e.code }
func errAPI(status int, code string) error { return &apiError{status, code} }
func md(s string) string                   { return fmt.Sprintf("%x", md5.Sum([]byte(s))) }
func random(n int, alphabet string) (string, error) {
	b := make([]byte, n)
	if _, e := rand.Read(b); e != nil {
		return "", e
	}
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return string(b), nil
}

const alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

func find(m any, key string) any {
	switch v := m.(type) {
	case map[string]any:
		if x, ok := v[key]; ok {
			return x
		}
		for _, x := range v {
			if r := find(x, key); r != nil {
				return r
			}
		}
	case []any:
		for _, x := range v {
			if r := find(x, key); r != nil {
				return r
			}
		}
	}
	return nil
}
func str(v any) string {
	if v == nil {
		return ""
	}
	return fmt.Sprint(v)
}
func num(v any) int64 { n, _ := strconv.ParseInt(str(v), 10, 64); return n }
func ckey(cnlid, guid string, ts int64) string {
	raw := "|" + cnlid + "|" + strconv.FormatInt(ts, 10) + "|mg3c3b04ba|V1.0.0|" + guid + "|" + platform + "|https://www.yangshipin.c|mozilla/5.0 (windows nt ||Mozilla|Netscape|Win32|"
	var hash int32
	for _, r := range raw {
		hash = hash*31 + int32(r)
	}
	plain := []byte("|" + strconv.FormatInt(int64(hash), 10) + raw)
	pad := aes.BlockSize - len(plain)%aes.BlockSize
	for i := 0; i < pad; i++ {
		plain = append(plain, byte(pad))
	}
	key, _ := hex.DecodeString("48e5918a74ae21c972b90cce8af6c8be")
	iv, _ := hex.DecodeString("9a7e7d23610266b1d9fbf98581384d92")
	block, _ := aes.NewCipher(key)
	out := make([]byte, len(plain))
	cipher.NewCBCEncrypter(block, iv).CryptBlocks(out, plain)
	return "--01" + strings.ToUpper(hex.EncodeToString(out))
}
func ticket(pid, guid, rnd string, ts int64) string {
	key, _ := hex.DecodeString("6a70e9ac007ccc384c28a88dfd2211decb66494bca83bd6178f85732b2eacc9594e4e5ab720ec3a43e87b3c72b86192ff0dfea8fa8f47794d8792668438c")
	b := []byte(pid + "&" + strconv.FormatInt(ts, 10) + "&" + guid + "&" + appID + "&" + rnd)
	for i := range b {
		if i < len(key) {
			b[i] ^= key[i]
		}
	}
	return hex.EncodeToString(b)
}

// NewResolver uses only fixed official metadata endpoints, with no proxy or redirect.
func NewResolver() func(context.Context, string) (Result, error) {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	client := &http.Client{Transport: transport, Timeout: 15 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("redirect rejected") }}
	return resolver(client)
}
func resolver(client *http.Client) func(context.Context, string) (Result, error) {
	return func(ctx context.Context, channel string) (Result, error) {
		ids, ok := channels[channel]
		if !ok {
			return Result{}, errAPI(400, "UNSUPPORTED_CHANNEL")
		}
		cnlid, pid := ids[0], ids[1]
		a, e := random(8, "abcdefghijklmnopqrstuvwxyz0123456789")
		if e != nil {
			return Result{}, e
		}
		b, e := random(11, "abcdefghijklmnopqrstuvwxyz0123456789")
		if e != nil {
			return Result{}, e
		}
		guid := a + "_" + b
		request := func(endpoint, body string, headers map[string]string) (map[string]any, error) {
			method := http.MethodGet
			if body != "" {
				method = http.MethodPost
			}
			req, e := http.NewRequestWithContext(ctx, method, endpoint, strings.NewReader(body))
			if e != nil {
				return nil, e
			}
			req.Header.Set("Origin", "https://www.yangshipin.cn")
			req.Header.Set("Referer", "https://www.yangshipin.cn/")
			req.Header.Set("User-Agent", ua)
			req.Header.Set("yspappid", appID)
			req.Header.Set("Cookie", "guid="+guid+"; versionName=99.99.99; versionCode=999999; vplatform=109; platformVersion=Chrome; deviceModel=159; newLogin=1; pc_version=1.1.16; ysp_uinfo_pc=")
			for k, v := range headers {
				req.Header.Set(k, v)
			}
			resp, e := client.Do(req)
			if e != nil {
				return nil, e
			}
			defer resp.Body.Close()
			if resp.StatusCode != 200 {
				return nil, errAPI(502, "UPSTREAM_HTTP_ERROR")
			}
			raw, e := io.ReadAll(io.LimitReader(resp.Body, (1<<20)+1))
			if e != nil || len(raw) > 1<<20 {
				return nil, errAPI(502, "INVALID_UPSTREAM_RESPONSE")
			}
			var data map[string]any
			dec := json.NewDecoder(strings.NewReader(string(raw)))
			dec.UseNumber()
			if dec.Decode(&data) != nil || data == nil {
				return nil, errAPI(502, "INVALID_UPSTREAM_RESPONSE")
			}
			return data, nil
		}
		rnd, e := random(10, alpha)
		if e != nil {
			return Result{}, e
		}
		authFields := url.Values{"pid": {pid}, "guid": {guid}, "appid": {"ysp_pc"}, "rand_str": {rnd}, "signature": {md("appid=ysp_pc&guid=" + guid + "&pid=" + pid + "&rand_str=" + rnd + "n@7QKk%YeSjfw%22")}}
		auth, e := request(authURL, authFields.Encode(), map[string]string{"Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"})
		if e != nil {
			return Result{}, e
		}
		if str(auth["code"]) != "0" {
			return Result{}, errAPI(502, "AUTH_FAILED")
		}
		authToken, ts := str(find(auth, "token")), num(find(auth, "ts"))
		if authToken == "" || ts <= 0 {
			return Result{}, errAPI(502, "INVALID_AUTH_RESPONSE")
		}
		tsms := strconv.FormatInt(ts*1000, 10)
		query := url.Values{"yspappid": {appID}, "guid": {guid}, "vappid": {"59306155"}, "vsecret": {"b42702bf7309a179d102f3d51b1add2fda0bc7ada64cb801"}, "raw": {"1"}, "version": {"v1"}, "ts": {tsms}, "rnd": {md("token_rnd;" + appID + ";v1;" + guid + ";" + tsms + ";")}}
		token, e := request(tokenURL+"?"+query.Encode(), "", nil)
		if e != nil {
			return Result{}, e
		}
		sdkToken := str(find(token, "token"))
		if str(token["ret"]) != "0" || sdkToken == "" {
			return Result{}, errAPI(502, "TOKEN_FAILED")
		}
		rnd, e = random(10, alpha)
		if e != nil {
			return Result{}, e
		}
		fields := map[string]any{"adjust": 1, "appVer": "V1.0.0", "app_version": "V1.0.0", "cKey": ckey(cnlid, guid, ts), "channel": "ysp_tx", "cmd": "2", "cnlid": cnlid, "defn": "fhd", "devid": "devid", "dtype": "1", "encryptVer": "8.1", "guid": guid, "livepid": pid, "otype": "ojson", "platform": platform, "rand_str": rnd, "sphttps": "1", "stream": "2"}
		keys := make([]string, 0, len(fields))
		for k := range fields {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		parts := make([]string, 0, len(keys))
		for _, k := range keys {
			parts = append(parts, k+"="+str(fields[k]))
		}
		signature := md(strings.Join(parts, "&") + "0f$IVHi9Qno?G")
		sdkKeys := []string{"adjust", "app_version", "appVer", "channel", "cKey", "cmd", "cnlid", "defn", "devid", "dtype", "encryptVer", "guid", "livepid", "otype", "platform", "sphttps", "stream"}
		parts = nil
		for _, k := range sdkKeys {
			parts = append(parts, k+"="+str(fields[k]))
		}
		sdkInput := md(strings.Join(parts, "&"))
		rnd, e = random(10, alpha)
		if e != nil {
			return Result{}, e
		}
		requestID := "999999" + rnd + strconv.FormatInt(ts*1000+time.Now().UnixMilli()%1000, 10)
		input := sdkInput + "-" + guid + "-1-" + requestID
		sdkSign := md(guid + ";www.yangshipin.cn;" + sdkToken + ";https:;" + appID + ";" + input + ";")
		rnd, e = random(10, alpha)
		if e != nil {
			return Result{}, e
		}
		fields["signature"] = signature
		body, _ := json.Marshal(fields)
		data, e := request(liveURL, string(body), map[string]string{"Content-Type": "application/json;charset=UTF-8", "yspplayertoken": authToken, "yspticket": ticket(pid, guid, rnd, ts), "seqid": "1", "request-id": requestID, "yspsdkinput": sdkInput, "yspsdksign": sdkSign + "-" + input})
		if e != nil {
			return Result{}, e
		}
		if str(data["code"]) != "0" {
			return Result{}, errAPI(502, "LIVE_FAILED")
		}
		if code := num(find(data, "iretcode")); code != 0 {
			if code == 5 {
				return Result{}, errAPI(403, "REGION_OR_COPYRIGHT_RESTRICTED")
			}
			return Result{}, errAPI(502, "UPSTREAM_REJECTED")
		}
		rawURL := str(find(data, "playurl"))
		if rawURL == "" {
			return Result{}, errAPI(502, "NO_PLAYURL")
		}
		if ext, ok := find(data, "extended_param").(string); ok && ext != "" {
			if !strings.HasPrefix(ext, "&") && !strings.HasPrefix(ext, "?") {
				ext = "&" + ext
			}
			rawURL += ext
		}
		u, e := url.Parse(rawURL)
		if e != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil {
			return Result{}, errAPI(502, "INVALID_PLAYURL")
		}
		transform := ""
		if str(find(data, "encrypt")) == "2" {
			transform = "ysp-tea"
		} else if strings.Contains(strings.ToLower(rawURL), "cdrmld") || strings.Contains(strings.ToLower(rawURL), "cctvwbcd") {
			transform = "h5e"
		}
		return Result{u.String(), transform}, nil
	}
}

type call struct {
	ctx    context.Context
	cancel context.CancelFunc
	done   chan struct{}
	users  int
	result Result
	err    error
}
type cached struct {
	result Result
	err    error
	until  time.Time
}
type Handler struct {
	mu      sync.Mutex
	pending map[string]*call
	cache   map[string]cached
	resolve func(context.Context, string) (Result, error)
	timeout time.Duration
}

func NewHandler() *Handler { return newHandler(NewResolver(), 15*time.Second) }
func newHandler(resolve func(context.Context, string) (Result, error), timeout time.Duration) *Handler {
	return &Handler{pending: map[string]*call{}, cache: map[string]cached{}, resolve: resolve, timeout: timeout}
}
func reply(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func respond(w http.ResponseWriter, r Result, e error) {
	if e == nil {
		reply(w, 200, r)
		return
	}
	status, code := 502, "UPSTREAM_FAILED"
	var ae *apiError
	if errors.As(e, &ae) {
		status, code = ae.status, ae.code
	}
	if errors.Is(e, context.DeadlineExceeded) {
		status, code = 504, "UPSTREAM_TIMEOUT"
	}
	message := "央视频线路暂时不可用，请稍后重试"
	if status == 403 {
		message = "当前服务器出口受频道地区或版权限制"
	}
	reply(w, status, map[string]string{"error": code, "message": message})
}
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/api/cctv-live/resolve" {
		reply(w, 404, map[string]string{"error": "NOT_FOUND"})
		return
	}
	if r.Method != "GET" {
		w.Header().Set("Allow", "GET")
		reply(w, 405, map[string]string{"error": "METHOD_NOT_ALLOWED"})
		return
	}
	q, e := url.ParseQuery(r.URL.RawQuery)
	channel := q.Get("channel")
	_, ok := channels[channel]
	if e != nil || !ok || len(q) != 1 || len(q["channel"]) != 1 {
		reply(w, 400, map[string]string{"error": "UNSUPPORTED_CHANNEL"})
		return
	}
	h.mu.Lock()
	if c, ok := h.cache[channel]; ok && time.Now().Before(c.until) {
		h.mu.Unlock()
		respond(w, c.result, c.err)
		return
	}
	c := h.pending[channel]
	if c != nil && c.ctx.Err() != nil {
		h.mu.Unlock()
		reply(w, 429, map[string]string{"error": "BUSY"})
		return
	}
	if c == nil {
		if len(h.pending) >= 2 {
			h.mu.Unlock()
			reply(w, 429, map[string]string{"error": "BUSY"})
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), h.timeout)
		c = &call{ctx: ctx, cancel: cancel, done: make(chan struct{})}
		h.pending[channel] = c
		go func() {
			result, err := h.resolve(ctx, channel)
			if ctx.Err() != nil {
				err = ctx.Err()
			}
			h.mu.Lock()
			c.result, c.err = result, err
			ttl := 30 * time.Second
			if err != nil {
				ttl = 5 * time.Second
			}
			if !errors.Is(err, context.Canceled) {
				h.cache[channel] = cached{result, err, time.Now().Add(ttl)}
			}
			delete(h.pending, channel)
			close(c.done)
			h.mu.Unlock()
			cancel()
		}()
	}
	c.users++
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		c.users--
		if c.users == 0 && h.pending[channel] == c {
			c.cancel()
		}
		h.mu.Unlock()
	}()
	select {
	case <-r.Context().Done():
		return
	case <-c.done:
		respond(w, c.result, c.err)
	}
}
