package httpauth

import "testing"

func TestExtractBearerToken(t *testing.T) {
	tests := []struct {
		name   string
		header string
		want   string
	}{
		{name: "empty", header: "", want: ""},
		{name: "basic", header: "Bearer abc", want: "abc"},
		{name: "trim and case", header: "  bEaReR   token-1  ", want: "token-1"},
		{name: "invalid scheme", header: "Basic abc", want: ""},
		{name: "missing token", header: "Bearer", want: ""},
		{name: "matches TS first two fields", header: "Bearer abc extra", want: "abc"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ExtractBearerToken(tt.header); got != tt.want {
				t.Fatalf("ExtractBearerToken() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestExtractCookieToken(t *testing.T) {
	if got := ExtractCookieToken("foo=bar; notch_access_token=abc%3D123; other=value", AccessCookieName); got != "abc=123" {
		t.Fatalf("decoded cookie = %q", got)
	}
	if got := ExtractCookieToken("notch_refresh_token=one=two=three", RefreshCookieName); got != "one=two=three" {
		t.Fatalf("cookie with equals = %q", got)
	}
	if got := ExtractCookieToken("notch_refresh_token=", RefreshCookieName); got != "" {
		t.Fatalf("empty cookie = %q", got)
	}
	if got := ExtractCookieToken("notch_refresh_token=%zz", RefreshCookieName); got != "%zz" {
		t.Fatalf("decode fallback = %q", got)
	}
}
