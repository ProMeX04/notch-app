package httpauth

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestApplyAuthCookiesMatchesPortalCookiePolicy(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "https://portal.example.com/account", nil)
	w := httptest.NewRecorder()
	expires := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)

	ApplyAuthCookies(w, req, CookieConfig{Secure: true}, AuthCookiePayload{
		AccessToken:      "access",
		AccessExpiresAt:  expires,
		RefreshToken:     "refresh",
		RefreshExpiresAt: expires.Add(time.Hour),
	})

	cookies := w.Result().Cookies()
	if len(cookies) != 2 {
		t.Fatalf("got %d cookies, want 2", len(cookies))
	}
	for _, cookie := range cookies {
		if !cookie.HttpOnly {
			t.Fatalf("%s is not HttpOnly", cookie.Name)
		}
		if !cookie.Secure {
			t.Fatalf("%s is not Secure", cookie.Name)
		}
		if cookie.SameSite != http.SameSiteLaxMode {
			t.Fatalf("%s SameSite = %v", cookie.Name, cookie.SameSite)
		}
		if cookie.Path != "/" {
			t.Fatalf("%s Path = %s", cookie.Name, cookie.Path)
		}
	}
}

func TestSecureCookieDisabledForLocalhost(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "http://localhost:5173/account", nil)
	w := httptest.NewRecorder()

	ApplyAuthCookies(w, req, CookieConfig{Secure: true}, AuthCookiePayload{
		AccessToken:      "access",
		AccessExpiresAt:  time.Now().Add(time.Hour),
		RefreshToken:     "refresh",
		RefreshExpiresAt: time.Now().Add(time.Hour),
	})

	for _, header := range w.Result().Header.Values("Set-Cookie") {
		if strings.Contains(strings.ToLower(header), "secure") {
			t.Fatalf("localhost cookie unexpectedly secure: %s", header)
		}
	}
}

func TestClearAuthCookiesExpiresBothCookies(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "https://portal.example.com/account", nil)
	w := httptest.NewRecorder()

	ClearAuthCookies(w, req, CookieConfig{Secure: true})

	cookies := w.Result().Cookies()
	if len(cookies) != 2 {
		t.Fatalf("got %d cookies, want 2", len(cookies))
	}
	for _, cookie := range cookies {
		if cookie.Value != "" {
			t.Fatalf("%s value = %q, want empty", cookie.Name, cookie.Value)
		}
		if !cookie.Expires.Equal(time.Unix(0, 0).UTC()) {
			t.Fatalf("%s expires = %s", cookie.Name, cookie.Expires)
		}
	}
}
