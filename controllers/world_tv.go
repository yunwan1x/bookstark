package controllers

import (
	"context"
	"errors"
	"net/http"
	"time"

	"bookstark/services"
	"bookstark/services/worldtv"

	"github.com/gin-gonic/gin"
)

func AdminWorldTV(c *gin.Context) {
	state, e := services.WorldTV().Snapshot()
	if e != nil {
		apiError(c, 500, "读取世界电视配置失败")
		return
	}
	catalog, e := services.WorldTV().Catalog()
	catalogError := ""
	if e != nil {
		catalog = worldtv.Catalog{Channels: []worldtv.Channel{}}
		catalogError = "读取频道列表失败，请重新拉取"
	}
	c.Header("Cache-Control", "no-store")
	apiSuccess(c, gin.H{"state": state, "catalog": catalog, "catalogError": catalogError})
}
func SaveWorldTV(c *gin.Context) {
	var cfg worldtv.Config
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 8192)
	if c.ShouldBindJSON(&cfg) != nil {
		apiError(c, 400, "无效的世界电视配置")
		return
	}
	if e := worldtv.ValidateConfig(cfg); e != nil {
		apiError(c, 400, e.Error())
		return
	}
	state, e := services.WorldTV().Configure(cfg)
	if e != nil {
		if errors.Is(e, worldtv.ErrBusy) {
			apiError(c, 409, e.Error())
		} else {
			apiError(c, 500, "保存世界电视配置失败")
		}
		return
	}
	apiSuccess(c, state)
}
func PullWorldTV(c *gin.Context) {
	// A browser navigation does not cancel an administrator's accepted pull.
	ctx, cancel := context.WithTimeout(context.Background(), 65*time.Second)
	defer cancel()
	e := services.WorldTV().Run(ctx, false)
	if e != nil {
		status := 502
		if errors.Is(e, worldtv.ErrBusy) {
			status = 409
		}
		apiError(c, status, e.Error())
		return
	}
	AdminWorldTV(c)
}
