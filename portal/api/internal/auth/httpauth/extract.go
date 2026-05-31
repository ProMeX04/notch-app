package httpauth

import (
	"net/url"
	"strings"
)

func ExtractBearerToken(authorization string) string {
	header := strings.TrimSpace(authorization)
	if header == "" {
		return ""
	}
	parts := strings.Fields(header)
	if len(parts) < 2 || strings.ToLower(parts[0]) != "bearer" {
		return ""
	}
	return parts[1]
}

func ExtractCookieToken(cookieHeader string, name string) string {
	if strings.TrimSpace(cookieHeader) == "" || strings.TrimSpace(name) == "" {
		return ""
	}
	for _, part := range strings.Split(cookieHeader, ";") {
		rawName, rawValue, ok := strings.Cut(part, "=")
		if !ok || strings.TrimSpace(rawName) != name {
			continue
		}
		value := strings.TrimSpace(rawValue)
		if value == "" {
			return ""
		}
		decoded, err := url.QueryUnescape(value)
		if err != nil {
			return value
		}
		return decoded
	}
	return ""
}
