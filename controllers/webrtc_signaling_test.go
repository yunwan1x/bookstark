package controllers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"bookstark/conf"
	"bookstark/models"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var webRTCSignalingSettingsTestMu sync.Mutex

func TestWebRTCSignalingRoutesMessagesBetweenPeers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	host := dialSignalingWS(t, server.URL, "room-alpha", "host")
	defer host.Close()
	viewer := dialSignalingWS(t, server.URL, "room-alpha", "viewer")
	defer viewer.Close()

	hostJoined := readSignalingMessage(t, host)
	if hostJoined["type"] != "joined" || hostJoined["peer"] != "host" {
		t.Fatalf("unexpected host joined message: %#v", hostJoined)
	}

	viewerJoined := readSignalingMessage(t, viewer)
	if viewerJoined["type"] != "joined" || viewerJoined["peer"] != "viewer" {
		t.Fatalf("unexpected viewer joined message: %#v", viewerJoined)
	}

	existingPeerNotice := readSignalingMessage(t, viewer)
	if existingPeerNotice["type"] != "peer-joined" || existingPeerNotice["peer"] != "host" {
		t.Fatalf("viewer should learn existing host peer, got %#v", existingPeerNotice)
	}

	newPeerNotice := readSignalingMessage(t, host)
	if newPeerNotice["type"] != "peer-joined" || newPeerNotice["peer"] != "viewer" {
		t.Fatalf("host should learn viewer peer, got %#v", newPeerNotice)
	}

	if err := viewer.WriteJSON(map[string]any{
		"type": "signal",
		"to":   "host",
		"payload": map[string]any{
			"kind": "offer",
			"sdp":  "fake-offer",
		},
	}); err != nil {
		t.Fatalf("write viewer signal: %v", err)
	}

	forwarded := readSignalingMessage(t, host)
	if forwarded["type"] != "signal" || forwarded["from"] != "viewer" || forwarded["to"] != "host" {
		t.Fatalf("unexpected forwarded signal envelope: %#v", forwarded)
	}
	payload, ok := forwarded["payload"].(map[string]any)
	if !ok || payload["kind"] != "offer" || payload["sdp"] != "fake-offer" {
		t.Fatalf("unexpected forwarded payload: %#v", forwarded["payload"])
	}
}

func TestWebRTCSignalingRejectsInvalidRoom(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=x&peer=host"
	_, resp, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err == nil {
		t.Fatal("expected invalid room websocket dial to fail")
	}
	if resp == nil || resp.StatusCode != 400 {
		t.Fatalf("expected HTTP 400 for invalid room, got resp=%v err=%v", resp, err)
	}
}

func TestWebRTCSignalingAllowsNullOriginForLocalHtml(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-local&peer=host"
	headers := http.Header{}
	headers.Set("Origin", "null")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, headers)
	if err != nil {
		t.Fatalf("expected null origin websocket dial to work for local HTML: %v", err)
	}
	defer conn.Close()

	joined := readSignalingMessage(t, conn)
	if joined["type"] != "joined" || joined["peer"] != "host" {
		t.Fatalf("unexpected joined message: %#v", joined)
	}
}

func TestWebRTCSignalingAllowsFileOriginForLocalHtml(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-file&peer=host"
	headers := http.Header{}
	headers.Set("Origin", "file://")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, headers)
	if err != nil {
		t.Fatalf("expected file origin websocket dial to work for local HTML: %v", err)
	}
	defer conn.Close()

	joined := readSignalingMessage(t, conn)
	if joined["type"] != "joined" || joined["peer"] != "host" {
		t.Fatalf("unexpected joined message: %#v", joined)
	}
}

func TestWebRTCSignalingDisabledBySetting(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_enabled": "0",
	})
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-disabled&peer=host"
	_, resp, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err == nil {
		t.Fatal("expected disabled signaling websocket dial to fail")
	}
	if resp == nil || resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("expected HTTP 503 when signaling disabled, got resp=%v err=%v", resp, err)
	}
}

func TestWebRTCSignalingRejectsLocalOriginWhenDisabled(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_allow_local_file": "0",
	})
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-origin&peer=host"
	headers := http.Header{}
	headers.Set("Origin", "null")
	_, resp, err := websocket.DefaultDialer.Dial(wsURL, headers)
	if err == nil {
		t.Fatal("expected null origin websocket dial to fail when local file is disabled")
	}
	if resp == nil || resp.StatusCode != http.StatusForbidden {
		t.Fatalf("expected HTTP 403 for disabled local origin, got resp=%v err=%v", resp, err)
	}
}

func TestWebRTCSignalingAllowsConfiguredOrigin(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_allowed_origins": "https://tool.example.com",
	})
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-allow&peer=host"
	headers := http.Header{}
	headers.Set("Origin", "https://tool.example.com")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, headers)
	if err != nil {
		t.Fatalf("expected configured origin websocket dial to work: %v", err)
	}
	defer conn.Close()
	joined := readSignalingMessage(t, conn)
	if joined["type"] != "joined" {
		t.Fatalf("unexpected joined message: %#v", joined)
	}
}

func TestWebRTCSignalingRejectsDuplicatePeerBeforeUpgrade(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	host := dialSignalingWS(t, server.URL, "room-duplicate", "host")
	defer host.Close()
	joined := readSignalingMessage(t, host)
	if joined["type"] != "joined" || joined["peer"] != "host" {
		t.Fatalf("unexpected joined message: %#v", joined)
	}

	duplicateURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-duplicate&peer=host"
	_, resp, err := websocket.DefaultDialer.Dial(duplicateURL, nil)
	if err == nil {
		t.Fatal("expected duplicate peer websocket dial to fail before upgrade")
	}
	if resp == nil || resp.StatusCode != http.StatusConflict {
		t.Fatalf("expected HTTP 409 for duplicate peer, got resp=%v err=%v", resp, err)
	}

	if err := host.WriteJSON(map[string]any{"type": "ping"}); err != nil {
		t.Fatalf("write ping after duplicate rejection: %v", err)
	}
	pong := readSignalingMessage(t, host)
	if pong["type"] != "pong" || pong["peer"] != "host" {
		t.Fatalf("existing host should remain connected after duplicate rejection, got %#v", pong)
	}
}

func TestWebRTCSignalingHeartbeatReleasesStalePeer(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()
	restoreHeartbeat := setWebRTCSignalingHeartbeatForTest(150*time.Millisecond, 50*time.Millisecond)
	defer restoreHeartbeat()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	host := dialSignalingWS(t, server.URL, "room-stale", "host")
	defer host.Close()
	joined := readSignalingMessage(t, host)
	if joined["type"] != "joined" || joined["peer"] != "host" {
		t.Fatalf("unexpected joined message: %#v", joined)
	}

	pingSeen := make(chan struct{}, 1)
	host.SetPingHandler(func(string) error {
		select {
		case pingSeen <- struct{}{}:
		default:
		}
		// Deliberately do not send a pong, so the server must close and unregister this stale peer.
		return nil
	})
	readDone := make(chan error, 1)
	go func() {
		for {
			if _, _, err := host.ReadMessage(); err != nil {
				readDone <- err
				return
			}
		}
	}()

	select {
	case <-pingSeen:
	case <-time.After(time.Second):
		t.Fatal("expected server protocol ping")
	}
	select {
	case <-readDone:
	case <-time.After(2 * time.Second):
		t.Fatal("expected server to close stale websocket after missing pong")
	}

	waitForSignalingAvailability(t, server.URL, "room-stale", "host", true, "")
	reused := dialSignalingWS(t, server.URL, "room-stale", "host")
	defer reused.Close()
	reusedJoined := readSignalingMessage(t, reused)
	if reusedJoined["type"] != "joined" || reusedJoined["peer"] != "host" {
		t.Fatalf("unexpected reused host joined message: %#v", reusedJoined)
	}
}

func TestWebRTCSignalingAvailabilityReportsPeerState(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	assertAvailability := func(path string, available bool, reason string) {
		t.Helper()
		resp, err := http.Get(server.URL + path)
		if err != nil {
			t.Fatalf("GET %s: %v", path, err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("GET %s status = %d, want 200", path, resp.StatusCode)
		}
		var body map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
			t.Fatalf("decode availability: %v", err)
		}
		if body["available"] != available {
			t.Fatalf("availability %s = %#v, want %v; body=%#v", path, body["available"], available, body)
		}
		if reason != "" && body["reason"] != reason {
			t.Fatalf("availability %s reason = %#v, want %s; body=%#v", path, body["reason"], reason, body)
		}
	}

	assertAvailability("/api/webrtc-signaling/availability?room=room-check&peer=host", true, "")
	host := dialSignalingWS(t, server.URL, "room-check", "host")
	defer host.Close()
	_ = readSignalingMessage(t, host)
	assertAvailability("/api/webrtc-signaling/availability?room=room-check&peer=host", false, "peer_exists")
	assertAvailability("/api/webrtc-signaling/availability?room=x&peer=host", false, "invalid_id")
}

func TestWebRTCSignalingRejectsViewerWhenHostMissing(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	resp, err := http.Get(server.URL + "/api/webrtc-signaling/availability?room=room-missing-host&peer=viewer-one")
	if err != nil {
		t.Fatalf("GET missing host availability: %v", err)
	}
	defer resp.Body.Close()
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode availability: %v", err)
	}
	if body["available"] != false || body["reason"] != "room_not_found" {
		t.Fatalf("viewer availability without host = %#v, want room_not_found", body)
	}

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-missing-host&peer=viewer-one"
	_, upgradeResp, dialErr := websocket.DefaultDialer.Dial(wsURL, nil)
	if dialErr == nil {
		t.Fatal("expected viewer websocket dial without active host to fail")
	}
	if upgradeResp == nil || upgradeResp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected HTTP 404 for viewer joining missing host room, got resp=%v err=%v", upgradeResp, dialErr)
	}
}

func TestWebRTCSignalingHostCloseBroadcastsRoomClosed(t *testing.T) {
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	host := dialSignalingWS(t, server.URL, "room-close", "host")
	defer host.Close()
	viewer := dialSignalingWS(t, server.URL, "room-close", "viewer")
	defer viewer.Close()

	_ = readSignalingMessage(t, host)   // host joined
	_ = readSignalingMessage(t, viewer) // viewer joined
	_ = readSignalingMessage(t, viewer) // existing host
	_ = readSignalingMessage(t, host)   // viewer joined notice

	if err := host.WriteJSON(map[string]any{"type": "close-room"}); err != nil {
		t.Fatalf("write close-room: %v", err)
	}
	closed := readSignalingMessage(t, viewer)
	if closed["type"] != "room-closed" || closed["room"] != "room-close" || closed["peer"] != "host" {
		t.Fatalf("viewer should receive room-closed from host, got %#v", closed)
	}

	waitForSignalingAvailability(t, server.URL, "room-close", "viewer-two", false, "room_not_found")
}

func TestWebRTCSignalingAvailabilityReportsDisabledAndRoomFull(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_enabled":   "0",
		"webrtc_signaling_max_peers": "2",
	})
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	resp, err := http.Get(server.URL + "/api/webrtc-signaling/availability?room=room-disabled&peer=host")
	if err != nil {
		t.Fatalf("GET disabled availability: %v", err)
	}
	defer resp.Body.Close()
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode disabled availability: %v", err)
	}
	if body["available"] != false || body["reason"] != "disabled" {
		t.Fatalf("unexpected disabled availability: %#v", body)
	}
}

func TestWebRTCSignalingAvailabilityReportsRoomFull(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_max_peers": "2",
	})
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	one := dialSignalingWS(t, server.URL, "room-availability-full", "host")
	defer one.Close()
	two := dialSignalingWS(t, server.URL, "room-availability-full", "peer-two")
	defer two.Close()

	resp, err := http.Get(server.URL + "/api/webrtc-signaling/availability?room=room-availability-full&peer=peer-three")
	if err != nil {
		t.Fatalf("GET room full availability: %v", err)
	}
	defer resp.Body.Close()
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode room full availability: %v", err)
	}
	if body["available"] != false || body["reason"] != "room_full" {
		t.Fatalf("unexpected room full availability: %#v", body)
	}
}

func TestWebRTCSignalingMaxPeersFromSetting(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_max_peers": "2",
	})
	gin.SetMode(gin.TestMode)
	resetWebRTCSignalingHubForTest()

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	server := httptest.NewServer(router)
	defer server.Close()

	one := dialSignalingWS(t, server.URL, "room-limit", "host")
	defer one.Close()
	two := dialSignalingWS(t, server.URL, "room-limit", "peer-two")
	defer two.Close()

	thirdURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/webrtc-signaling/ws?room=room-limit&peer=peer-three"
	_, resp, err := websocket.DefaultDialer.Dial(thirdURL, nil)
	if err == nil {
		t.Fatal("expected third peer websocket dial to fail before upgrade")
	}
	if resp == nil || resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("expected HTTP 429 when room is full, got resp=%v err=%v", resp, err)
	}
}

func TestWebRTCSignalingConfigUsesSettings(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_default_url":     "wss://books.example.com/api/webrtc-signaling/ws",
		"webrtc_signaling_max_peers":       "12",
		"webrtc_signaling_stun_urls":       "stun:one.example.com\nstun:two.example.com",
		"webrtc_signaling_turn_url":        "turn:turn.example.com:3478",
		"webrtc_signaling_turn_username":   "turn-user",
		"webrtc_signaling_turn_credential": "turn-secret",
	})
	gin.SetMode(gin.TestMode)

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	req := httptest.NewRequest(http.MethodGet, "/api/webrtc-signaling/config", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GET config status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode config: %v", err)
	}
	if body["signaling_url"] != "wss://books.example.com/api/webrtc-signaling/ws" {
		t.Fatalf("unexpected signaling URL: %#v", body["signaling_url"])
	}
	if body["max_peers"].(float64) != 12 {
		t.Fatalf("unexpected max peers: %#v", body["max_peers"])
	}
	iceServers, ok := body["ice_servers"].([]any)
	if !ok || len(iceServers) != 2 {
		t.Fatalf("unexpected ice servers: %#v", body["ice_servers"])
	}
	turn, ok := iceServers[1].(map[string]any)
	if !ok || turn["username"] != "turn-user" || turn["credential"] != "turn-secret" {
		t.Fatalf("unexpected TURN config: %#v", iceServers[1])
	}
}

func TestWebRTCSignalingConfigResolvesSameOriginURL(t *testing.T) {
	initWebRTCSignalingSettingsDB(t, map[string]string{
		"webrtc_signaling_default_url": "",
	})
	gin.SetMode(gin.TestMode)

	router := gin.New()
	RegisterWebRTCSignalingRoutes(router)
	req := httptest.NewRequest(http.MethodGet, "/api/webrtc-signaling/config", nil)
	req.Host = "books.example.com"
	req.Header.Set("X-Forwarded-Proto", "https")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GET config status = %d, want 200; body=%s", w.Code, w.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode config: %v", err)
	}
	if body["signaling_url"] != "wss://books.example.com/api/webrtc-signaling/ws" {
		t.Fatalf("unexpected resolved signaling URL: %#v", body["signaling_url"])
	}
}

func resetWebRTCSignalingHubForTest() {
	webRTCSignalHub = newWebRTCSignalingHub(webRTCSignalingMaxPeers)
}

func setWebRTCSignalingHeartbeatForTest(pongWait, pingPeriod time.Duration) func() {
	previousPongWait := webRTCSignalingPongWait
	previousPingPeriod := webRTCSignalingPingPeriod
	webRTCSignalingPongWait = pongWait
	webRTCSignalingPingPeriod = pingPeriod
	return func() {
		webRTCSignalingPongWait = previousPongWait
		webRTCSignalingPingPeriod = previousPingPeriod
	}
}

func initWebRTCSignalingSettingsDB(t *testing.T, settings map[string]string) {
	t.Helper()
	webRTCSignalingSettingsTestMu.Lock()
	conf.LoadDefaults()
	dbPath := filepath.Join(t.TempDir(), "webrtc-settings.db")
	if models.DB != nil {
		_ = models.DB.Close()
		models.DB = nil
	}
	if err := models.InitDB(dbPath); err != nil {
		webRTCSignalingSettingsTestMu.Unlock()
		t.Fatalf("InitDB() error = %v", err)
	}
	if err := models.BatchUpdateSettings(settings); err != nil {
		webRTCSignalingSettingsTestMu.Unlock()
		t.Fatalf("BatchUpdateSettings() error = %v", err)
	}
	t.Cleanup(func() {
		if models.DB != nil {
			_ = models.DB.Close()
			models.DB = nil
		}
		_ = os.Remove(dbPath)
		webRTCSignalingSettingsTestMu.Unlock()
	})
}

func dialSignalingWS(t *testing.T, baseURL, room, peer string) *websocket.Conn {
	t.Helper()
	wsURL := "ws" + strings.TrimPrefix(baseURL, "http") + "/api/webrtc-signaling/ws?room=" + room + "&peer=" + peer
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial websocket %s: %v", wsURL, err)
	}
	return conn
}

func readSignalingMessage(t *testing.T, conn *websocket.Conn) map[string]any {
	t.Helper()
	if err := conn.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatalf("set read deadline: %v", err)
	}
	var message map[string]any
	if err := conn.ReadJSON(&message); err != nil {
		t.Fatalf("read websocket json: %v", err)
	}
	encoded, _ := json.Marshal(message)
	if !json.Valid(encoded) {
		t.Fatalf("message should be json serializable: %#v", message)
	}
	return message
}

func waitForSignalingAvailability(t *testing.T, baseURL, room, peer string, available bool, reason string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	path := "/api/webrtc-signaling/availability?room=" + room + "&peer=" + peer
	for {
		resp, err := http.Get(baseURL + path)
		if err == nil {
			var body map[string]any
			decodeErr := json.NewDecoder(resp.Body).Decode(&body)
			_ = resp.Body.Close()
			if decodeErr == nil && resp.StatusCode == http.StatusOK && body["available"] == available {
				if reason == "" || body["reason"] == reason {
					return
				}
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("availability did not become available=%v reason=%q for room=%s peer=%s", available, reason, room, peer)
		}
		time.Sleep(25 * time.Millisecond)
	}
}
