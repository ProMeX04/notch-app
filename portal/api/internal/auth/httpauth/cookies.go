package httpauth

import (
	"net/http"
	"strings"
	"time"
)

const (
	AccessCookieName  = "notch_access_token"
	RefreshCookieName = "notch_refresh_token"
)

type CookieConfig struct {
	Secure bool
	Domain string
}

type AuthCookiePayload struct {
	AccessToken      string
	AccessExpiresAt  time.Time
	RefreshToken     string
	RefreshExpiresAt time.Time
}

func ApplyAuthCookies(w http.ResponseWriter, req *http.Request, cfg CookieConfig, payload AuthCookiePayload) {
	setAuthCookie(w, req, cfg, AccessCookieName, payload.AccessToken, payload.AccessExpiresAt)
	setAuthCookie(w, req, cfg, RefreshCookieName, payload.RefreshToken, payload.RefreshExpiresAt)
}

func ClearAuthCookies(w http.ResponseWriter, req *http.Request, cfg CookieConfig) {
	setAuthCookie(w, req, cfg, AccessCookieName, "", time.Unix(0, 0).UTC())
	setAuthCookie(w, req, cfg, RefreshCookieName, "", time.Unix(0, 0).UTC())
}

func ReadRefreshTokenCookie(req *http.Request) string {
	cookie, err := req.Cookie(RefreshCookieName)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(cookie.Value)
}

func setAuthCookie(w http.ResponseWriter, req *http.Request, cfg CookieConfig, name string, value string, expires time.Time) {
	cookie := &http.Cookie{Name: name, Value: value, Path: "/", Expires: expires, HttpOnly: true, Secure: secureCookie(req, cfg), SameSite: http.SameSiteLaxMode}
	if cfg.Domain != "" {
		cookie.Domain = cfg.Domain
	}
	http.SetCookie(w, cookie)
}

func secureCookie(req *http.Request, cfg CookieConfig) bool {
	if !cfg.Secure {
		return false
	}
	if req == nil || req.URL == nil {
		return cfg.Secure
	}
	hostname := strings.ToLower(req.URL.Hostname())
	return hostname != "localhost" && hostname != "127.0.0.1"
}
