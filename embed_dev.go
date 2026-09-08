//go:build dev

package main

import (
	"io/fs"
	"os"
)

// Dev mode: read from filesystem directly, no embedding
var EmbedFS = struct {
	StaticFS   fs.FS
	TemplateFS fs.FS
	ConfFS     fs.FS
}{}

func init() {
	os.MkdirAll("conf", 0755)
	os.MkdirAll("static", 0755)
	os.MkdirAll("templates", 0755)
}