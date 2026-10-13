package controllers

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"net/http"
	"strconv"

	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
)

var backgroundUploadSem = make(chan struct{}, 1)

func GetBackground(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	p, err := models.GetBackgroundPreference(middleware.GetMemberID(c))
	if err != nil {
		apiError(c, 500, "读取背景设置失败")
		return
	}
	apiSuccess(c, p)
}

func UpdateBackground(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 6<<20)
	if err := c.Request.ParseMultipartForm(6 << 20); err != nil {
		apiError(c, 400, "背景文件过大或格式不正确")
		return
	}
	defer c.Request.MultipartForm.RemoveAll()
	fade, err := strconv.Atoi(c.PostForm("fade"))
	if err != nil {
		apiError(c, 400, "背景淡化值不正确")
		return
	}
	p := models.BackgroundPreference{Mode: c.PostForm("mode"), Animated: c.PostForm("animated") == "true", Fade: fade}
	var data []byte
	var hash string
	f, _, err := c.Request.FormFile("file")
	if err == nil {
		defer f.Close()
		raw, e := io.ReadAll(io.LimitReader(f, (5<<20)+1))
		if e != nil || len(raw) > 5<<20 {
			apiError(c, 400, "背景图片不能超过5MB")
			return
		}
		cfg, format, e := image.DecodeConfig(bytes.NewReader(raw))
		if e != nil || (format != "jpeg" && format != "png" && format != "webp") || cfg.Width < 1 || cfg.Height < 1 || int64(cfg.Width)*int64(cfg.Height) > 20000000 {
			apiError(c, 400, "请选择不超过2000万像素的PNG、JPG或WebP图片")
			return
		}
		select {
		case backgroundUploadSem <- struct{}{}:
			defer func() { <-backgroundUploadSem }()
		default:
			apiError(c, 429, "请稍后重试")
			return
		}
		img, _, e := image.Decode(bytes.NewReader(raw))
		if e != nil {
			apiError(c, 400, "图片无法读取")
			return
		}
		var buf bytes.Buffer
		if e = jpeg.Encode(&buf, resizeImage(img, 2560, 2560), &jpeg.Options{Quality: 85}); e != nil {
			apiError(c, 500, "图片压缩失败")
			return
		}
		data = buf.Bytes()
		hash = fmt.Sprintf("%x", sha256.Sum256(data))
	} else if err != http.ErrMissingFile {
		apiError(c, 400, "图片上传失败")
		return
	}
	if err = models.SaveBackgroundPreference(middleware.GetMemberID(c), p, data, hash, c.PostForm("remove") == "true"); err != nil {
		apiError(c, 400, err.Error())
		return
	}
	GetBackground(c)
}

func BackgroundImage(c *gin.Context) {
	data, hash, err := models.GetBackgroundImage(middleware.GetMemberID(c))
	c.Header("Cache-Control", "private, no-cache")
	c.Header("Vary", "Cookie, Authorization")
	if err != nil || len(data) == 0 {
		c.Status(404)
		return
	}
	etag := `"` + hash + `"`
	c.Header("ETag", etag)
	if c.GetHeader("If-None-Match") == etag {
		c.Status(304)
		return
	}
	c.Data(200, "image/jpeg", data)
}
