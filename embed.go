//go:build !dev

package main

import (
	"embed"
	"io/fs"
)

//go:embed static templates conf
var embedFS embed.FS

var EmbedFS = struct {
	StaticFS   fs.FS
	TemplateFS fs.FS
	ConfFS     fs.FS
}{
	StaticFS:   mustSub(embedFS, "static"),
	TemplateFS: mustSub(embedFS, "templates"),
	ConfFS:     mustSub(embedFS, "conf"),
}

func mustSub(fsys embed.FS, path string) fs.FS {
	sub, err := fs.Sub(fsys, path)
	if err != nil {
		panic(err)
	}
	return sub
}