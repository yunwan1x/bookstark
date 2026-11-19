// Package worldtv synchronizes public M3U metadata, never media streams.
package worldtv

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"time"
)

const DefaultSource = "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8"
const MaxBytes = 8 << 20

type Channel struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Country  string `json:"country"`
	Group    string `json:"group"`
	Logo     string `json:"logo"`
	URL      string `json:"url"`
	External bool   `json:"external"`
	Geo      bool   `json:"geo"`
	Language string `json:"language"`
}
type Catalog struct {
	Schema    int       `json:"schema"`
	Source    string    `json:"source"`
	CheckedAt time.Time `json:"checkedAt"`
	UpdatedAt time.Time `json:"updatedAt"`
	Revision  string    `json:"revision"`
	ETag      string    `json:"etag"`
	Channels  []Channel `json:"channels"`
}

var attribute = regexp.MustCompile(`([\w-]+)="([^"]*)"`)

func webURL(raw string) bool {
	u, e := url.Parse(raw)
	return e == nil && (u.Scheme == "https" || u.Scheme == "http") && u.Hostname() != "" && u.User == nil && !strings.ContainsAny(raw, "\r\n\t\\")
}
func Parse(data []byte) ([]Channel, error) {
	if len(data) > MaxBytes {
		return nil, errors.New("订阅列表超过 8 MiB")
	}
	text := strings.TrimLeft(string(data), "\ufeff \r\n\t")
	if !strings.HasPrefix(text, "#EXTM3U") {
		return nil, errors.New("订阅内容不是 M3U 频道列表")
	}
	scanner := bufio.NewScanner(strings.NewReader(text))
	scanner.Buffer(make([]byte, 4096), 64<<10)
	var attrs map[string]string
	var title string
	rows := make([]Channel, 0)
	seen := map[string]bool{}
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "#EXTINF:") {
			attrs = map[string]string{}
			for _, m := range attribute.FindAllStringSubmatch(line, -1) {
				attrs[m[1]] = m[2]
			}
			quoted := false
			title = ""
			for i, r := range line {
				if r == '"' {
					quoted = !quoted
				}
				if r == ',' && !quoted {
					title = line[i+1:]
					break
				}
			}
		} else if line != "" && !strings.HasPrefix(line, "#") && attrs != nil {
			name := attrs["tvg-name"]
			if name == "" {
				name = strings.TrimSpace(strings.NewReplacer("Ⓢ", "", "Ⓖ", "", "Ⓨ", "", "Ⓣ", "").Replace(title))
			}
			if name != "" && webURL(line) {
				country, group := attrs["tvg-country"], attrs["group-title"]
				if group == "" {
					group = "其他"
				}
				key := attrs["tvg-id"]
				if key == "" {
					key = country + "|" + group + "|" + strings.ToLower(name)
				}
				sum := sha256.Sum256([]byte(key))
				id := hex.EncodeToString(sum[:12])
				u, _ := url.Parse(line)
				host := strings.ToLower(u.Hostname())
				external := false
				for _, d := range []string{"youtube.com", "youtu.be", "twitch.tv", "dailymotion.com"} {
					if host == d || strings.HasSuffix(host, "."+d) {
						external = true
					}
				}
				logo := attrs["tvg-logo"]
				if !strings.HasPrefix(logo, "https://") || !webURL(logo) {
					logo = ""
				}
				if !seen[id] {
					rows = append(rows, Channel{id, name, country, group, logo, line, external, strings.Contains(title, "Ⓖ"), attrs["tvg-language"]})
					seen[id] = true
				}
			}
			attrs = nil
		}
	}
	if e := scanner.Err(); e != nil {
		return nil, fmt.Errorf("频道列表行过长或格式不完整")
	}
	if len(rows) == 0 {
		return nil, errors.New("未找到有效频道，保留上次成功列表")
	}
	if len(rows) > 20000 {
		return nil, errors.New("频道列表超过 20000 个频道")
	}
	return rows, nil
}
