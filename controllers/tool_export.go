package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"fmt"
	"io"
	"mime"
	"os"

	"github.com/gin-gonic/gin"
)

type boundedToolArchive struct {
	io.Writer
	n int64
}

func (w *boundedToolArchive) Write(b []byte) (int, error) {
	if int64(len(b)) > toolpackage.MaxArchive-w.n {
		return 0, models.ErrDAVFileTooLarge
	}
	n, err := w.Writer.Write(b)
	w.n += int64(n)
	return n, err
}

// Build before sending headers so failed/conflicting exports never download a
// partial ZIP. Temp files bound memory use and are removed on every exit path.
func ExportToolInstall(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	c.Header("Cache-Control", "private, no-store")
	file, err := os.CreateTemp("", "bookstark-tool-export-*.zip")
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer os.Remove(file.Name())
	defer file.Close()
	err = models.ExportInstalledTool(c.Request.Context(), member, id, c.Query("revision"), c.Query("instance"), &boundedToolArchive{Writer: file})
	if err != nil {
		toolAPIError(c, err)
		return
	}
	info, err := file.Stat()
	if err != nil {
		toolAPIError(c, err)
		return
	}
	if _, err = file.Seek(0, io.SeekStart); err != nil {
		toolAPIError(c, err)
		return
	}
	c.Header("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": fmt.Sprintf("bookstark-tool-%d.zip", id)}))
	c.DataFromReader(200, info.Size(), "application/zip", file, nil)
}
