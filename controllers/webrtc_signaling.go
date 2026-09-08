package controllers

import (
	"encoding/json"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"

	"bookstark/models"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const (
	webRTCSignalingMaxPeers       = 16
	webRTCSignalingMaxMessageSize = 64 << 10
	webRTCSignalingWriteWait      = 5 * time.Second
)

var (
	webRTCSignalingPongWait   = 60 * time.Second
	webRTCSignalingPingPeriod = 54 * time.Second
	webRTCSignalingIDPattern  = regexp.MustCompile(`^[A-Za-z0-9_-]{3,96}$`)
	webRTCSignalingUpgrader   = websocket.Upgrader{CheckOrigin: checkWebRTCSignalingOrigin}
	webRTCSignalHub           = newWebRTCSignalingHub(webRTCSignalingMaxPeers)
)

type webRTCSignalingHub struct {
	mu       sync.Mutex
	rooms    map[string]*webRTCSignalingRoom
	maxPeers int
}

type webRTCSignalingRoom struct {
	id    string
	peers map[string]*webRTCSignalingPeer
}

type webRTCSignalingPeer struct {
	room            string
	id              string
	conn            *websocket.Conn
	send            chan []byte
	hub             *webRTCSignalingHub
	maxMessageBytes int64
}

type webRTCSignalInput struct {
	Type    string          `json:"type"`
	To      string          `json:"to,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type webRTCSignalOutput struct {
	Type    string          `json:"type"`
	Room    string          `json:"room,omitempty"`
	Peer    string          `json:"peer,omitempty"`
	From    string          `json:"from,omitempty"`
	To      string          `json:"to,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

func RegisterWebRTCSignalingRoutes(r gin.IRoutes) {
	r.GET("/api/webrtc-signaling/ws", WebRTCSignalingWS)
	r.GET("/api/webrtc-signaling/config", GetWebRTCSignalingConfig)
	r.GET("/api/webrtc-signaling/availability", GetWebRTCSignalingAvailability)
}

func GetWebRTCSignalingConfig(c *gin.Context) {
	cfg := models.GetWebRTCSignalingSettings()
	response := gin.H{
		"enabled":       cfg.Enabled,
		"signaling_url": resolveWebRTCSignalingURL(c.Request, cfg.DefaultURL),
		"max_peers":     cfg.MaxPeers,
		"ice_servers":   buildWebRTCICEServers(cfg),
	}
	c.JSON(http.StatusOK, response)
}

func GetWebRTCSignalingAvailability(c *gin.Context) {
	cfg := models.GetWebRTCSignalingSettings()
	roomID := c.Query("room")
	peerID := c.Query("peer")
	if !cfg.Enabled {
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"reason":    "disabled",
			"message":   "webrtc signaling disabled",
		})
		return
	}
	if !validWebRTCSignalingID(roomID) || !validWebRTCSignalingID(peerID) {
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"reason":    "invalid_id",
			"message":   "invalid room or peer",
		})
		return
	}
	if err := webRTCSignalHub.validateRegister(roomID, peerID, cfg.MaxPeers); err != nil {
		c.JSON(http.StatusOK, gin.H{
			"available": false,
			"reason":    webRTCSignalingErrorReason(err),
			"message":   err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"available": true,
		"room":      roomID,
		"peer":      peerID,
	})
}

func resolveWebRTCSignalingURL(r *http.Request, configured string) string {
	if strings.TrimSpace(configured) != "" {
		return strings.TrimSpace(configured)
	}
	scheme := "ws"
	if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
		scheme = "wss"
	}
	return scheme + "://" + r.Host + "/api/webrtc-signaling/ws"
}

func buildWebRTCICEServers(cfg models.WebRTCSignalingSettings) []gin.H {
	servers := make([]gin.H, 0, 2)
	if len(cfg.STUNURLs) > 0 {
		servers = append(servers, gin.H{"urls": cfg.STUNURLs})
	}
	if cfg.TURNURL != "" {
		turn := gin.H{"urls": cfg.TURNURL}
		if cfg.TURNUsername != "" {
			turn["username"] = cfg.TURNUsername
		}
		if cfg.TURNCredential != "" {
			turn["credential"] = cfg.TURNCredential
		}
		servers = append(servers, turn)
	}
	return servers
}

func checkWebRTCSignalingOrigin(r *http.Request) bool {
	cfg := models.GetWebRTCSignalingSettings()
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	if origin == "null" || strings.EqualFold(origin, "file://") {
		return cfg.AllowLocalFile
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	if strings.EqualFold(u.Host, r.Host) {
		return true
	}
	for _, allowed := range cfg.AllowedOrigins {
		if strings.EqualFold(strings.TrimRight(allowed, "/"), strings.TrimRight(origin, "/")) {
			return true
		}
	}
	return false
}

func WebRTCSignalingWS(c *gin.Context) {
	cfg := models.GetWebRTCSignalingSettings()
	if !cfg.Enabled {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "webrtc signaling disabled"})
		return
	}
	roomID := c.Query("room")
	peerID := c.Query("peer")
	if !validWebRTCSignalingID(roomID) || !validWebRTCSignalingID(peerID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid room or peer"})
		return
	}
	if err := webRTCSignalHub.validateRegister(roomID, peerID, cfg.MaxPeers); err != nil {
		status := http.StatusConflict
		if err.Error() == "room is full" {
			status = http.StatusTooManyRequests
		} else if err.Error() == "room not found" {
			status = http.StatusNotFound
		}
		c.JSON(status, gin.H{"error": err.Error()})
		return
	}

	conn, err := webRTCSignalingUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	peer := &webRTCSignalingPeer{
		room:            roomID,
		id:              peerID,
		conn:            conn,
		send:            make(chan []byte, 16),
		hub:             webRTCSignalHub,
		maxMessageBytes: cfg.MaxMessageBytes,
	}
	if err := webRTCSignalHub.register(peer, cfg.MaxPeers); err != nil {
		writeWebRTCSignalClose(conn, websocket.ClosePolicyViolation, err.Error())
		conn.Close()
		return
	}

	go peer.writeLoop()
	peer.readLoop()
}

func newWebRTCSignalingHub(maxPeers int) *webRTCSignalingHub {
	return &webRTCSignalingHub{
		rooms:    make(map[string]*webRTCSignalingRoom),
		maxPeers: maxPeers,
	}
}

func validWebRTCSignalingID(value string) bool {
	return webRTCSignalingIDPattern.MatchString(value)
}

func webRTCSignalingErrorReason(err error) string {
	if err == nil {
		return ""
	}
	switch err.Error() {
	case "peer already exists":
		return "peer_exists"
	case "room is full":
		return "room_full"
	case "room not found":
		return "room_not_found"
	default:
		return "unavailable"
	}
}

func (h *webRTCSignalingHub) validateRegister(roomID, peerID string, maxPeers int) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.validateRegisterLocked(roomID, peerID, maxPeers)
}

func (h *webRTCSignalingHub) validateRegisterLocked(roomID, peerID string, maxPeers int) error {
	if maxPeers <= 0 {
		maxPeers = h.maxPeers
	}
	room := h.rooms[roomID]
	if room == nil {
		if peerID != "host" {
			return errWebRTCSignaling("room not found")
		}
		return nil
	}
	if peerID != "host" && !room.hasHost() {
		return errWebRTCSignaling("room not found")
	}
	if _, exists := room.peers[peerID]; exists {
		return errWebRTCSignaling("peer already exists")
	}
	if len(room.peers) >= maxPeers {
		return errWebRTCSignaling("room is full")
	}
	return nil
}

func (h *webRTCSignalingHub) register(peer *webRTCSignalingPeer, maxPeers int) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if maxPeers <= 0 {
		maxPeers = h.maxPeers
	}

	if err := h.validateRegisterLocked(peer.room, peer.id, maxPeers); err != nil {
		return err
	}
	room := h.rooms[peer.room]
	if room == nil {
		room = &webRTCSignalingRoom{id: peer.room, peers: make(map[string]*webRTCSignalingPeer)}
		h.rooms[peer.room] = room
	}

	room.peers[peer.id] = peer
	peer.queue(webRTCSignalOutput{Type: "joined", Room: peer.room, Peer: peer.id})
	for existingPeerID, existingPeer := range room.peers {
		if existingPeerID == peer.id {
			continue
		}
		peer.queue(webRTCSignalOutput{Type: "peer-joined", Room: peer.room, Peer: existingPeerID})
		existingPeer.queue(webRTCSignalOutput{Type: "peer-joined", Room: peer.room, Peer: peer.id})
	}
	return nil
}

func (h *webRTCSignalingHub) unregister(peer *webRTCSignalingPeer) {
	h.mu.Lock()
	defer h.mu.Unlock()

	room := h.rooms[peer.room]
	if room == nil || room.peers[peer.id] != peer {
		return
	}
	delete(room.peers, peer.id)
	close(peer.send)
	for _, existingPeer := range room.peers {
		existingPeer.queue(webRTCSignalOutput{Type: "peer-left", Room: peer.room, Peer: peer.id})
	}
	if len(room.peers) == 0 {
		delete(h.rooms, peer.room)
	}
}

func (r *webRTCSignalingRoom) hasHost() bool {
	if r == nil {
		return false
	}
	return r.peers["host"] != nil
}

func (h *webRTCSignalingHub) closeRoom(roomID, peerID string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	room := h.rooms[roomID]
	if room == nil {
		return
	}
	delete(h.rooms, roomID)
	for _, existingPeer := range room.peers {
		existingPeer.queue(webRTCSignalOutput{Type: "room-closed", Room: roomID, Peer: peerID})
		close(existingPeer.send)
	}
}

func (h *webRTCSignalingHub) relay(from *webRTCSignalingPeer, input webRTCSignalInput) {
	h.mu.Lock()
	defer h.mu.Unlock()

	room := h.rooms[from.room]
	if room == nil {
		return
	}
	output := webRTCSignalOutput{
		Type:    "signal",
		Room:    from.room,
		From:    from.id,
		To:      input.To,
		Payload: input.Payload,
	}
	if input.To != "" {
		if target := room.peers[input.To]; target != nil {
			target.queue(output)
		}
		return
	}
	for peerID, target := range room.peers {
		if peerID == from.id {
			continue
		}
		target.queue(output)
	}
}

func (p *webRTCSignalingPeer) readLoop() {
	defer func() {
		p.hub.unregister(p)
		p.conn.Close()
	}()
	maxMessageBytes := p.maxMessageBytes
	if maxMessageBytes <= 0 {
		maxMessageBytes = webRTCSignalingMaxMessageSize
	}
	p.conn.SetReadLimit(maxMessageBytes)
	_ = p.conn.SetReadDeadline(time.Now().Add(webRTCSignalingPongWait))
	p.conn.SetPongHandler(func(string) error {
		return p.conn.SetReadDeadline(time.Now().Add(webRTCSignalingPongWait))
	})
	for {
		var input webRTCSignalInput
		if err := p.conn.ReadJSON(&input); err != nil {
			return
		}
		switch input.Type {
		case "ping":
			p.queue(webRTCSignalOutput{Type: "pong", Room: p.room, Peer: p.id})
		case "close-room":
			if p.id == "host" {
				p.hub.closeRoom(p.room, p.id)
				return
			}
		case "signal":
			p.hub.relay(p, input)
		}
	}
}

func (p *webRTCSignalingPeer) writeLoop() {
	defer p.conn.Close()
	ticker := time.NewTicker(webRTCSignalingPingPeriod)
	defer ticker.Stop()
	for {
		select {
		case message, ok := <-p.send:
			_ = p.conn.SetWriteDeadline(time.Now().Add(webRTCSignalingWriteWait))
			if !ok {
				_ = p.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := p.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			_ = p.conn.SetWriteDeadline(time.Now().Add(webRTCSignalingWriteWait))
			if err := p.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (p *webRTCSignalingPeer) queue(output webRTCSignalOutput) {
	message, err := json.Marshal(output)
	if err != nil {
		return
	}
	select {
	case p.send <- message:
	default:
	}
}

type errWebRTCSignaling string

func (e errWebRTCSignaling) Error() string {
	return string(e)
}

func writeWebRTCSignalClose(conn *websocket.Conn, code int, text string) {
	message := websocket.FormatCloseMessage(code, text)
	_ = conn.WriteControl(websocket.CloseMessage, message, time.Now().Add(webRTCSignalingWriteWait))
}
