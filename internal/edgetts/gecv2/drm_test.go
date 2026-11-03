// SPDX-License-Identifier: LGPL-3.0-only
package gecv2

import (
	"regexp"
	"testing"
)

// 期望值来自 rany2/edge-tts 7.3.1 的 generate_sec_ms_gec_v2(unix)，不是本文件再算一遍。
func TestSecMSGECv2MatchesEdgeTTS731(t *testing.T) {
	cases := []struct {
		unix float64
		want string
	}{
		{1700000000, "2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2"},
		{1700000100, "0919602B5750900A-EC9DD394F23CB5635CF62A0E8E24136DCD32B26D10C543B10082E482D7516397"},
		{0, "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6"},
	}
	for _, tc := range cases {
		got := GenerateSecMSGecV2(tc.unix)
		if got != tc.want {
			t.Errorf("unix %v:\n got %s\nwant %s", tc.unix, got, tc.want)
		}
	}
}

func TestMUIDCookieShape(t *testing.T) {
	got := Cookie()
	if !regexp.MustCompile(`^muid=[0-9A-F]{32};$`).MatchString(got) {
		t.Fatalf("cookie = %q", got)
	}
}
