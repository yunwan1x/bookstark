package models

import (
	_ "embed"
	"encoding/json"
	"regexp"
)

type ToolIconOption struct {
	ID     string `json:"id"`
	Style  string `json:"style"`
	ZH     string `json:"zh"`
	EN     string `json:"en"`
	Search string `json:"search"`
}

// Source: Font Awesome Free 6.5.1 metadata/icons.json. Only free styles are
// included. Glyphs ship locally in static/webfonts; licensing is recorded in
// static/webfonts/font-awesome-license.txt.
//
//go:embed catalogs/tool-icons.json
var toolIconCatalog []byte

var ToolIconOptions = func() []ToolIconOption {
	var options []ToolIconOption
	if err := json.Unmarshal(toolIconCatalog, &options); err != nil {
		panic(err)
	}
	return options
}()

var toolIconKeys = func() map[string]bool {
	keys := make(map[string]bool, len(ToolIconOptions))
	for _, option := range ToolIconOptions {
		keys[option.Style+":"+option.ID] = true
	}
	return keys
}()

func validToolIcon(icon, style string) bool {
	if style == "" {
		style = "solid"
	}
	return (icon == "" && style == "solid") || toolIconKeys[style+":"+icon]
}

var toolIconColor = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)

func ValidToolAppearance(icon, style, color string) bool {
	if color != "" && !toolIconColor.MatchString(color) {
		return false
	}
	return validToolIcon(icon, style)
}
