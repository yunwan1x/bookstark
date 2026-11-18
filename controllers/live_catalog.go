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

func AdminLiveIDs(c *gin.Context) {
	key := c.Param("key")
	var found bool
	for _, ch := range cctvlive.OfficialChannels() {
		if ch.Key == key {
			found = true
			break
		}
	}
	if !found {
		apiError(c, http.StatusBadRequest, "此频道没有央视频取流线路")
		return
	}
	var change *cctvlive.OfficialIDs
	if c.Request.Method != http.MethodDelete {
		var ids cctvlive.OfficialIDs
		if c.ShouldBindJSON(&ids) != nil || !ids.Valid() {
			apiError(c, http.StatusBadRequest, "PID 和流编号须为 1 至 19 位正整数")
			return
		}
		if ids != cctvlive.DefaultIDs(key) {
			change = &ids
		}
	}
	if err := models.SaveLiveIDs(key, change); err != nil {
		apiError(c, http.StatusInternalServerError, "频道编号保存失败")
		return
	}
	effective := cctvlive.DefaultIDs(key)
	if change != nil {
		effective = *change
	}
	apiSuccess(c, effective)
}
