package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	HTTP        HTTPConfig
	Database    DatabaseConfig
	Auth        AuthConfig
	OAuth       OAuthConfig
	Payments    PaymentConfig
	Gemini      GeminiConfig
	Observatory ObservabilityConfig
}

type HTTPConfig struct {
	Addr              string
	PublicAppURL      string
	AllowedDevOrigins []string
	FrontendURL       string
}

type DatabaseConfig struct {
	URL string
}

type AuthConfig struct {
	JWTSecret        string
	CookieDomain     string
	SecureCookies    bool
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	MaxActiveDevices int
}

type OAuthConfig struct {
	GoogleClientID         string
	GoogleClientSecret     string
	NativeClientID         string
	NativeRedirectURIAllow []string
	DriveHandoffEncryptKey string
}

type PaymentConfig struct {
	VNPayTMNCode    string
	VNPayHashSecret string
	VNPayPaymentURL string
	VNPayProAmount  int
}

type GeminiConfig struct {
	APIKey string
}

type ObservabilityConfig struct {
	EventLogIPSalt string
}

func Load() (Config, error) {
	cfg := Config{
		HTTP: HTTPConfig{
			Addr:              env("PORTAL_API_ADDR", fmt.Sprintf(":%s", env("PORT", "8080"))),
			PublicAppURL:      env("PUBLIC_APP_URL", env("NEXT_PUBLIC_APP_URL", "http://localhost:5173")),
			AllowedDevOrigins: csvEnv("PORTAL_DEV_ORIGINS", []string{"http://localhost:5173", "http://127.0.0.1:5173", "http://localhost:3000"}),
			FrontendURL:       env("FRONTEND_URL", env("PUBLIC_APP_URL", env("NEXT_PUBLIC_APP_URL", "http://localhost:5173"))),
		},
		Database: DatabaseConfig{URL: env("DATABASE_URL", "")},
		Auth: AuthConfig{
			JWTSecret:        env("JWT_SECRET", ""),
			CookieDomain:     env("AUTH_COOKIE_DOMAIN", ""),
			SecureCookies:    boolEnv("AUTH_SECURE_COOKIES", env("NODE_ENV", "development") == "production"),
			AccessTokenTTL:   durationEnv("AUTH_ACCESS_TOKEN_TTL", time.Hour),
			RefreshTokenTTL:  durationEnv("AUTH_REFRESH_TOKEN_TTL", 30*24*time.Hour),
			MaxActiveDevices: intEnv("NOTCH_MAX_ACTIVE_DEVICES", 3),
		},
		OAuth: OAuthConfig{
			GoogleClientID:         env("GOOGLE_CLIENT_ID", ""),
			GoogleClientSecret:     env("GOOGLE_CLIENT_SECRET", ""),
			NativeClientID:         env("NOTCH_OAUTH_NATIVE_CLIENT_ID", "notch-desktop"),
			NativeRedirectURIAllow: csvEnv("NOTCH_OAUTH_NATIVE_REDIRECT_URIS", []string{"notch://oauth/callback"}),
			DriveHandoffEncryptKey: env("GOOGLE_DRIVE_HANDOFF_ENCRYPTION_KEY", ""),
		},
		Payments: PaymentConfig{
			VNPayTMNCode:    env("VNPAY_TMN_CODE", ""),
			VNPayHashSecret: env("VNPAY_HASH_SECRET", ""),
			VNPayPaymentURL: env("VNPAY_PAYMENT_URL", ""),
			VNPayProAmount:  intEnv("VNPAY_PRO_AMOUNT", 99000),
		},
		Gemini:      GeminiConfig{APIKey: env("GEMINI_API_KEY", "")},
		Observatory: ObservabilityConfig{EventLogIPSalt: env("EVENT_LOG_IP_SALT", env("AUTH_TOKEN_SECRET", "notch-event-log"))},
	}

	if env("NODE_ENV", "development") == "production" {
		if cfg.Database.URL == "" {
			return cfg, fmt.Errorf("DATABASE_URL is required in production")
		}
		if cfg.Auth.JWTSecret == "" {
			return cfg, fmt.Errorf("JWT_SECRET is required in production")
		}
		if cfg.OAuth.DriveHandoffEncryptKey == "" {
			return cfg, fmt.Errorf("GOOGLE_DRIVE_HANDOFF_ENCRYPTION_KEY is required in production")
		}
	}
	if cfg.Auth.JWTSecret == "" {
		cfg.Auth.JWTSecret = "development-secret-key-notch-default-change-in-production"
	}
	if cfg.OAuth.DriveHandoffEncryptKey == "" {
		cfg.OAuth.DriveHandoffEncryptKey = "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY="
	}
	return cfg, nil
}

func env(name, fallback string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	return value
}

func csvEnv(name string, fallback []string) []string {
	value := env(name, "")
	if value == "" {
		return fallback
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			out = append(out, trimmed)
		}
	}
	if len(out) == 0 {
		return fallback
	}
	return out
}

func boolEnv(name string, fallback bool) bool {
	value := env(name, "")
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func intEnv(name string, fallback int) int {
	value := env(name, "")
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

func durationEnv(name string, fallback time.Duration) time.Duration {
	value := env(name, "")
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
