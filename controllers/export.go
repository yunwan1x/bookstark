package controllers

import (
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
)

// exportSem 限制全局同时进行的导出数（导出可能跑数十秒甚至更久，
// 多人同时点会把磁盘 IO 和网络打满）。
var exportSem = make(chan struct{}, 1)

func ExportData(c *gin.Context) {
	var memberID int64
	if mid := c.Query("member_id"); mid != "" {
		if id, err := strconv.ParseInt(mid, 10, 64); err == nil && id > 0 {
			memberID = id
		}
	}
	// include_uploads 默认 1：把 data/uploads/ 一起打进 zip，异机导入图片不会 404
	includeUploads := c.DefaultQuery("include_uploads", "1") != "0"

	select {
	case exportSem <- struct{}{}:
		defer func() { <-exportSem }()
	default:
		apiError(c, http.StatusTooManyRequests, "已有导出任务在运行，请稍后再试")
		return
	}

	data, err := models.ExportAllData(memberID)
	if err != nil {
		log.Printf("ExportData: %v", err)
		apiError(c, http.StatusInternalServerError, "导出数据失败")
		return
	}

	suffix := "all"
	if memberID > 0 {
		suffix = fmt.Sprintf("user-%d", memberID)
	}
	filename := fmt.Sprintf("bookstark-export-%s-%s.zip", suffix, time.Now().Format("20060102-150405"))

	// 流式写响应：边压边送，避免整个 zip 驻留内存。
	c.Header("Content-Type", "application/zip")
	c.Header("Content-Disposition", "attachment; filename="+filename)
	c.Header("X-Content-Type-Options", "nosniff")
	c.Status(http.StatusOK)

	if err := models.WriteExportZip(c.Writer, data, includeUploads, memberID); err != nil {
		// 响应头已发出去了，没法再 c.JSON。只能记日志，客户端会拿到截断的 zip。
		log.Printf("ExportData: WriteExportZip 中断: %v", err)
		return
	}
}

func ImportCheck(c *gin.Context) {
	adminID := middleware.GetMemberID(c)

	data, zipPath, err := models.ParseImportZip(c.Request)
	if err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := models.ValidateImportData(data); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}

	// 获取目标用户 ID（用于书签冲突检测，先用管理员自己的 ID）
	targetMemberID := adminID

	result, err := models.ImportCheckData(data, targetMemberID)
	if err != nil {
		log.Printf("ImportCheck: %v", err)
		apiError(c, http.StatusInternalServerError, "冲突检测失败")
		return
	}

	importID := models.StoreImportSession(adminID, data, zipPath)
	result.ImportID = importID

	apiSuccess(c, result)
}

func ImportExecute(c *gin.Context) {
	adminID := middleware.GetMemberID(c)

	var req models.ImportExecuteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 验证 import_id
	data := models.GetImportSession(req.ImportID, adminID)
	if data == nil {
		apiError(c, http.StatusBadRequest, "导入会话不存在或已过期，请重新上传")
		return
	}

	// 验证 target_member_id
	var status int
	err := models.DB.QueryRow("SELECT status FROM md_members WHERE member_id = ?", req.TargetMemberID).Scan(&status)
	if err != nil || status != 1 {
		apiError(c, http.StatusBadRequest, "目标用户不存在或未通过审批")
		return
	}

	// 对书签冲突检测需要用目标用户的 ID 重新检测
	// 但我们已经在 check 阶段检测了冲突，这里直接执行

	zipPath := models.GetImportSessionZipPath(req.ImportID, adminID)
	result, err := models.ImportExecuteData(data, req.TargetMemberID, req.Resolutions, zipPath)
	if err != nil {
		log.Printf("ImportExecute: %v", err)
		apiError(c, http.StatusInternalServerError, "导入执行失败")
		return
	}

	// 消耗导入会话
	models.ConsumeImportSession(req.ImportID, adminID)

	apiSuccess(c, result)
}