package edgetts

import (
	"bytes"
	"context"
	"os"
	"testing"
	"time"
)

func TestEdgeLive(t *testing.T) {
	if os.Getenv("BOOKSTARK_TTS_LIVE") != "1" {
		t.Skip("explicit opt-in network smoke")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	var audio bytes.Buffer
	start := time.Now()
	if err := WriteTo(ctx, "你好，这是 BookStark 语音朗读测试。", "zh-CN-YunxiNeural", os.Getenv("BOOKSTARK_TTS_PROXY"), &audio); err != nil {
		t.Fatal(err)
	}
	if audio.Len() < 1000 {
		t.Fatal("missing MP3")
	}
	t.Logf("Yunxi: %d bytes in %s", audio.Len(), time.Since(start))
	if path := os.Getenv("BOOKSTARK_TTS_FIXTURE"); path != "" {
		if err := os.WriteFile(path, audio.Bytes(), 0600); err != nil {
			t.Fatal(err)
		}
	}
}
