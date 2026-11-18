package controllers

import (
	"context"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// TVOfficialDirectory serves only the public channel metadata used by the admin picker.
func TVOfficialDirectory(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://capi.yangshipin.cn/api/oms/pc/page/PG00000004", nil)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "无法读取官方目录")
		return
	}
	response, err := http.DefaultClient.Do(req)
	if err != nil {
		apiError(c, http.StatusBadGateway, "官方目录暂不可用")
		return
	}
	defer response.Body.Close()
	const limit = 2 << 20
	data, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if response.StatusCode != http.StatusOK || err != nil || len(data) == 0 || len(data) > limit {
		apiError(c, http.StatusBadGateway, "官方目录暂不可用")
		return
	}
	c.Header("Cache-Control", "no-store")
	c.Data(http.StatusOK, "application/octet-stream", data)
}
