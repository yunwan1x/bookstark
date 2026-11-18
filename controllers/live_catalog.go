package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

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

func AdminTVChannels(c *gin.Context) {
	defaults, _ := cctvlive.Catalog("")
	current, err := cctvlive.Catalog(models.GetSetting(cctvlive.LinesSetting))
	if err != nil {
		apiError(c, 500, "频道配置读取失败")
		return
	}
	mappings, err := models.LiveMappings()
	if err != nil {
		apiError(c, 500, "频道编号读取失败")
		return
	}
	c.Header("Cache-Control", "no-store")
	apiSuccess(c, gin.H{"defaults": json.RawMessage(defaults), "current": json.RawMessage(current), "official": cctvlive.OfficialChannels(), "mappings": mappings})
}

func officialKey(id string) string {
	for _, ch := range cctvlive.OfficialChannels() {
		if ch.ID == id {
			return ch.Key
		}
	}
	return ""
}

func SaveTVChannel(c *gin.Context) {
	var in struct {
		Lines []string              `json:"lines"`
		IDs   *cctvlive.OfficialIDs `json:"ids"`
		Reset bool                  `json:"reset"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 96<<10)
	if c.ShouldBindJSON(&in) != nil {
		apiError(c, 400, "无效的频道配置")
		return
	}
	id := c.Param("id")
	key := officialKey(id)
	if in.IDs != nil && (key == "" || !in.IDs.Valid()) {
		apiError(c, 400, "无效的央视频编号")
		return
	}
	defaults, _ := cctvlive.Catalog("")
	var catalog struct{ Channels []struct{ ID string } }
	json.Unmarshal(defaults, &catalog)
	found := false
	for _, ch := range catalog.Channels {
		if ch.ID == id {
			found = true
			break
		}
	}
	if !found {
		apiError(c, 400, "未知频道")
		return
	}
	if in.Reset {
		in.Lines = nil
		if key != "" {
			ids := cctvlive.DefaultIDs(key)
			in.IDs = &ids
		}
	} else {
		data, _ := json.Marshal(map[string][]string{id: in.Lines})
		if _, err := cctvlive.Catalog(string(data)); err != nil {
			apiError(c, 400, err.Error())
			return
		}
	}
	if err := models.SaveTVChannel(id, in.Lines, key, in.IDs); err != nil {
		apiError(c, 500, "保存失败，请检查配置大小并重试")
		return
	}
	apiSuccess(c, true)
}

var previewSlots = make(chan struct{}, 2)

func PreviewTVChannel(c *gin.Context) {
	var ids cctvlive.OfficialIDs
	if officialKey(c.Param("id")) == "" || c.ShouldBindJSON(&ids) != nil || !ids.Valid() {
		apiError(c, 400, "请填写有效的频道编号和流编号")
		return
	}
	select {
	case previewSlots <- struct{}{}:
		defer func() { <-previewSlots }()
	default:
		apiError(c, 429, "有其他线路正在取址，请稍后重试")
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()
	result, err := cctvlive.PreviewIDs(ctx, ids)
	c.Header("Cache-Control", "no-store")
	if err != nil {
		apiError(c, 502, "央视频取址失败，请核对编号、地区和节目权限")
		return
	}
	apiSuccess(c, result)
}
