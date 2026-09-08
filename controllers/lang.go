package controllers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"bookstark/i18n"
)

func isKnownLang(lang string) bool {
	for _, l := range i18n.SupportedLangs {
		if l == lang {
			return true
		}
	}
	return false
}

func SetLang(c *gin.Context) {
	lang := c.Query("lang")
	if !isKnownLang(lang) {
		lang = i18n.DefaultLang
	}

	c.SetCookie("lang", lang, 365*24*3600, "/", "", false, false)

	redirect := c.Query("redirect")
	if redirect == "" || !strings.HasPrefix(redirect, "/") {
		redirect = "/"
	}
	c.Redirect(http.StatusFound, redirect)
}

func SetLangAPI(c *gin.Context) {
	lang := c.Query("lang")
	if !isKnownLang(lang) {
		lang = i18n.DefaultLang
	}

	c.SetSameSite(http.SameSiteLaxMode)
	c.SetCookie("lang", lang, 365*24*3600, "/", "", false, false)

	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func GetLangBundle(c *gin.Context) {
	lang := c.Query("lang")
	if !isKnownLang(lang) {
		lang = i18n.DefaultLang
	}
	c.JSON(http.StatusOK, i18n.JSBundle(lang))
}
