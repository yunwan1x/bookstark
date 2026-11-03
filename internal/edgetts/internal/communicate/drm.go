package communicate

import (
	"bookstark/internal/edgetts/gecv2"
	"bookstark/internal/edgetts/internal/businessConsts"
	"time"
)

func generateWssEndpoint() string {
	return businessConsts.EdgeWssEndpoint + "&Sec-MS-GEC=" + gecv2.GenerateSecMSGecV2(float64(time.Now().Unix())) + "&Sec-MS-GEC-Version=2-" + businessConsts.ChromiumFllVersion + "&ConnectionId=" + generateConnectID()
}
