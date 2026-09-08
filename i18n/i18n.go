package i18n

import "github.com/gin-gonic/gin"

// SupportedLangs is the list of supported language codes.
var SupportedLangs = []string{"zh", "en"}

// DefaultLang is the fallback language.
const DefaultLang = "zh"

var messages = map[string]map[string]string{
	"zh": zhMessages,
	"en": enMessages,
}

// MakeT returns a translator function for the given language.
// Missing keys fall back to the key string itself.
func MakeT(lang string) func(string) string {
	m, ok := messages[lang]
	if !ok {
		m = messages[DefaultLang]
	}
	return func(key string) string {
		if v, ok := m[key]; ok {
			return v
		}
		if lang != DefaultLang {
			if v, ok := messages[DefaultLang][key]; ok {
				return v
			}
		}
		return key
	}
}

// T translates a key directly for the given language.
func T(lang, key string) string {
	return MakeT(lang)(key)
}

// JSBundle returns the full translation map for client-side injection.
func JSBundle(lang string) map[string]string {
	if m, ok := messages[lang]; ok {
		return m
	}
	return messages[DefaultLang]
}

// GetLang reads the lang cookie from the request and validates it.
func GetLang(c *gin.Context) string {
	lang, err := c.Cookie("lang")
	if err != nil || !isSupported(lang) {
		return DefaultLang
	}
	return lang
}

func isSupported(lang string) bool {
	for _, l := range SupportedLangs {
		if l == lang {
			return true
		}
	}
	return false
}
