package models

import (
	_ "embed"
	"encoding/json"
	"regexp"
	"strings"
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

// ResolveToolAppearance mirrors the browser's ToolAppearance.values fallback so
// the initial server-rendered tool identity matches its hydrated appearance.
func ResolveToolAppearance(m ToolMetadata) (icon, style, color string) {
	defaults := map[string][2]string{
		"document": {"file-pdf", "#dc2626"}, "image": {"image", "#7c3aed"},
		"media": {"photo-film", "#db2777"}, "development": {"code", "#0891b2"},
		"productivity": {"diagram-project", "#d97706"}, "other": {"cube", "#2563eb"},
	}
	fallback, ok := defaults[m.Category]
	if !ok {
		fallback = defaults["other"]
	}
	icon, style, color = fallback[0], "solid", fallback[1]
	if m.Icon != "" && validToolIcon(m.Icon, m.IconStyle) {
		icon = m.Icon
		if m.IconStyle != "" {
			style = m.IconStyle
		}
	}
	if toolIconColor.MatchString(m.IconColor) {
		color = strings.ToLower(m.IconColor)
	}
	return
}
