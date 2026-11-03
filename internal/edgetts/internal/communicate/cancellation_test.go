package communicate

import (
	"bookstark/internal/edgetts/internal/communicateOption"
	"context"
	"encoding/binary"
	"errors"
	"github.com/gorilla/websocket"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type failWriter struct{}

func (failWriter) Write(p []byte) (int, error) { return 0, errors.New("writer closed") }
func TestEdgeCancellationAndPartialDisconnect(t *testing.T) {
	for _, mode := range []string{"cancel", "writer", "partial", "complete"} {
		t.Run(mode, func(t *testing.T) {
			connected := make(chan struct{})
			closed := make(chan struct{})
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				conn, e := (&websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}).Upgrade(w, r, nil)
				if e != nil {
					return
				}
				defer conn.Close()
				defer close(closed)
				for i := 0; i < 2; i++ {
					if _, _, e = conn.ReadMessage(); e != nil {
						return
					}
				}
				close(connected)
				if mode != "cancel" {
					_ = conn.WriteMessage(1, []byte("Path:turn.start\r\n\r\n"))
					header := []byte("Path:audio\r\n")
					data := make([]byte, 2+len(header))
					binary.BigEndian.PutUint16(data, uint16(len(header)))
					copy(data[2:], header)
					data = append(data, []byte("audio")...)
					_ = conn.WriteMessage(2, data)
					if mode == "partial" {
						return
					}
					if mode == "complete" {
						_ = conn.WriteMessage(1, []byte("Path:turn.end\r\n\r\n"))
						return
					}
				}
				for {
					if _, _, e = conn.ReadMessage(); e != nil {
						return
					}
				}
			}))
			defer server.Close()
			c, e := NewCommunicate(InputText, "hello", &communicateOption.CommunicateOption{Voice: "zh-CN-YunxiNeural", Rate: "+0%", Pitch: "+0Hz", Volume: "+0%"})
			if e != nil {
				t.Fatal(e)
			}
			c.endpoint = "ws" + strings.TrimPrefix(server.URL, "http")
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			done := make(chan error, 1)
			var writer io.Writer = io.Discard
			if mode == "writer" {
				writer = failWriter{}
			}
			go func() { _, e := c.WriteStreamToContext(ctx, writer); done <- e }()
			select {
			case <-connected:
			case <-ctx.Done():
				t.Fatal("no connection")
			}
			if mode == "cancel" {
				cancel()
			}
			select {
			case e := <-done:
				if mode == "complete" && e != nil {
					t.Fatal(e)
				}
				if mode != "complete" && e == nil {
					t.Fatal("incomplete stream accepted")
				}
			case <-time.After(time.Second):
				t.Fatal("stream did not cancel")
			}
			select {
			case <-closed:
			case <-time.After(time.Second):
				t.Fatal("connection leaked")
			}
		})
	}
}
