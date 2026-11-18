package cctvlive

import (
	"crypto/sha256"
	_ "embed"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
)

//go:embed default_channels.json
var defaultCatalog []byte

const LinesSetting = "live_channel_lines"

type catalogChannel struct {
	ExternalOnly bool              `json:"externalOnly"`
	ID           string            `json:"id"`
	Sources      []json.RawMessage `json:"sources"`
}

// Catalog applies only administrator-selected lines. All other channel fields
// (including programme IDs and official-site links) come from the release catalog.
func Catalog(config string) ([]byte, error) {
	if strings.TrimSpace(config) == "" {
		return defaultCatalog, nil
	}
	var overrides map[string][]string
	if len(config) > 128*1024 || json.Unmarshal([]byte(config), &overrides) != nil || overrides == nil {
		return nil, fmt.Errorf("频道配置应为 JSON 对象，最大 128 KiB")
	}
	if len(overrides) == 0 {
		return defaultCatalog, nil
	}
	var catalog map[string]json.RawMessage
	if err := json.Unmarshal(defaultCatalog, &catalog); err != nil {
		return nil, err
	}
	var channels []json.RawMessage
	if err := json.Unmarshal(catalog["channels"], &channels); err != nil {
		return nil, err
	}
	for i, raw := range channels {
		var channel catalogChannel
		if err := json.Unmarshal(raw, &channel); err != nil {
			return nil, err
		}
		lines, ok := overrides[channel.ID]
		if !ok {
			continue
		}
		delete(overrides, channel.ID)
		if len(lines) == 0 || len(lines) > 16 {
			return nil, fmt.Errorf("频道 %s 需配置 1 至 16 条线路", channel.ID)
		}
		if len(lines) == 1 && strings.HasPrefix(lines[0], "official:") {
			address := strings.TrimPrefix(lines[0], "official:")
			u, err := url.ParseRequestURI(address)
			if !channel.ExternalOnly || err != nil || u.Scheme != "https" || u.Host != "www.yangshipin.cn" || u.User != nil || u.Path != "/tv/home" || !decimalID.MatchString(u.Query().Get("pid")) {
				return nil, fmt.Errorf("请输入含 pid 的央视频官方电视频道页地址")
			}
			var fields map[string]json.RawMessage
			if err := json.Unmarshal(raw, &fields); err != nil {
				return nil, err
			}
			fields["officialUrl"], _ = json.Marshal(address)
			channels[i], _ = json.Marshal(fields)
			continue
		}
		known := map[string]json.RawMessage{}
		for _, s := range channel.Sources {
			var item struct {
				ID string `json:"id"`
			}
			if err := json.Unmarshal(s, &item); err != nil {
				return nil, err
			}
			known[item.ID] = s
		}
		sources := make([]json.RawMessage, 0, len(lines))
		first := ""
		seen := map[string]bool{}
		for j, line := range lines {
			if seen[line] {
				return nil, fmt.Errorf("频道 %s 存在重复线路", channel.ID)
			}
			seen[line] = true
			id := line
			source, ok := known[id]
			if !ok {
				u, err := url.ParseRequestURI(line)
				if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || !strings.HasPrefix(line, "https://") || strings.ContainsAny(line, "\\ <>\"'\t\r\n#") || len(line) > 4096 {
					return nil, fmt.Errorf("频道 %s 第 %d 项必须是本频道的线路 ID 或 HTTPS 直播地址", channel.ID, j+1)
				}
				digest := sha256.Sum256([]byte(line))
				id = fmt.Sprintf("%s-custom-%x", channel.ID, digest[:8])
				source, _ = json.Marshal(map[string]string{"id": id, "label": fmt.Sprintf("自定义线路 %d", j+1), "protocol": "https", "capability": "direct", "url": line, "original": line})
			}
			if j == 0 {
				first = id
			}
			sources = append(sources, source)
		}
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(raw, &fields); err != nil {
			return nil, err
		}
		fields["sources"], _ = json.Marshal(sources)
		fields["preferredSourceId"], _ = json.Marshal(first)
		delete(fields, "externalOnly")
		delete(fields, "note")
		channels[i], _ = json.Marshal(fields)
	}
	for id := range overrides {
		return nil, fmt.Errorf("未知频道 ID %q", id)
	}
	catalog["channels"], _ = json.Marshal(channels)
	return json.Marshal(catalog)
}
