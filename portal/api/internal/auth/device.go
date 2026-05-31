package auth

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strings"
)

type DeviceInput struct {
	DeviceID    string
	DeviceName  string
	Platform    string
	TrustDevice bool
}

type NormalizedDevice struct {
	DeviceID    string
	DeviceName  string
	Platform    string
	TrustDevice bool
}

func NormalizeDevice(req *http.Request, input DeviceInput, userKey string, existing *Session) NormalizedDevice {
	deviceID := cleanLimit(input.DeviceID, 128)
	if deviceID == "" && existing != nil && existing.DeviceID != nil {
		deviceID = *existing.DeviceID
	}
	if deviceID == "" {
		deviceID = generatedDeviceID(userKey, userAgent(req))
	}

	deviceName := cleanLimit(input.DeviceName, 120)
	if deviceName == "" && existing != nil && existing.DeviceName != nil {
		deviceName = *existing.DeviceName
	}
	if deviceName == "" {
		deviceName = "Browser"
	}

	platform := cleanLimit(input.Platform, 64)
	if platform == "" && existing != nil && existing.Platform != nil {
		platform = *existing.Platform
	}
	if platform == "" {
		platform = inferPlatform(userAgent(req))
	}

	return NormalizedDevice{DeviceID: deviceID, DeviceName: deviceName, Platform: platform, TrustDevice: input.TrustDevice}
}

func DeviceInputFromRefreshRequest(req *http.Request) DeviceInput {
	deviceID := ""
	if req != nil {
		deviceID = strings.TrimSpace(req.Header.Get("x-notch-device-id"))
	}
	return DeviceInput{DeviceID: deviceID}
}

func cleanLimit(value string, limit int) string {
	trimmed := strings.TrimSpace(value)
	if len(trimmed) <= limit {
		return trimmed
	}
	return trimmed[:limit]
}

func generatedDeviceID(userKey string, userAgent string) string {
	sum := sha256.Sum256([]byte(userKey + ":" + userAgent))
	return "generated_" + hex.EncodeToString(sum[:])[:24]
}

func inferPlatform(userAgent string) string {
	ua := strings.ToLower(userAgent)
	switch {
	case strings.Contains(ua, "mac os x") || strings.Contains(ua, "macintosh"):
		return "macOS"
	case strings.Contains(ua, "windows"):
		return "Windows"
	case strings.Contains(ua, "android"):
		return "Android"
	case strings.Contains(ua, "iphone") || strings.Contains(ua, "ipad") || strings.Contains(ua, "ipod"):
		return "iOS"
	case strings.Contains(ua, "linux"):
		return "Linux"
	default:
		return "Browser"
	}
}

func userAgent(req *http.Request) string {
	if req == nil {
		return ""
	}
	return req.UserAgent()
}
