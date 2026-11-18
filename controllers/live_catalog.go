package controllers

import (
	"net/http"

	"bookstark/models"
	"bookstark/services/cctvlive"
	"github.com/gin-gonic/gin"
)

func LiveChannelCatalog(c *gin.Context) {
	config := ""
	if c.Query("defaults") != "1" {
		config = models.GetSetting(cctvlive.LinesSetting)
	}
	catalog, err := cctvlive.Catalog(config)
	c.Header("Cache-Control", "no-store")
	if err != nil {
		apiError(c, http.StatusInternalServerError, "直播线路配置无效")
		return
	}
	c.Data(http.StatusOK, "application/json; charset=utf-8", catalog)
}
