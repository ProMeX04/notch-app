package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"
)

var ErrRefreshInvalid = errors.New("refresh token is invalid or expired")

type RefreshService struct {
	Repo             SessionRepository
	JWTSecret        string
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	MaxActiveDevices int
	Now              func() time.Time
}

type RefreshRequestBody struct {
	RefreshToken string `json:"refresh_token"`
	DeviceID     string `json:"device_id"`
	DeviceName   string `json:"device_name"`
	Platform     string `json:"platform"`
	TrustDevice  any    `json:"trust_device"`
}

func (s RefreshService) RefreshWithToken(ctx context.Context, req *http.Request, refreshToken string, deviceInput DeviceInput) (AuthPayload, error) {
	var empty AuthPayload
	trimmed := strings.TrimSpace(refreshToken)
	if trimmed == "" || s.Repo == nil {
		return empty, ErrRefreshInvalid
	}
	now := s.now()

	tokenHash := token.HashToken(trimmed)
	session, err := s.Repo.FindSessionByRefreshTokenHash(ctx, tokenHash)
	if err != nil || session == nil {
		return empty, ErrRefreshInvalid
	}
	if session.RevokedAt != nil {
		return empty, ErrRefreshInvalid
	}
	if !session.ExpiresAt.After(now) {
		_ = s.Repo.MarkSessionExpired(ctx, session.ID, now)
		return empty, ErrRefreshInvalid
	}

	device := NormalizeDevice(req, deviceInput, session.User.ID+":"+session.ID, session)
	trustedAt := session.TrustedAt
	if device.TrustDevice {
		trustedAt = &now
	}
	accessExpiresAt := now.Add(s.accessTTL())
	refreshExpiresAt := now.Add(s.refreshTTL())
	accessToken, err := token.SignJWT(token.JWTPayload{
		UserID:           session.User.ID,
		Email:            session.User.Email,
		Name:             session.User.Name,
		DisplayName:      session.User.DisplayName,
		AvatarURL:        session.User.AvatarURL,
		IsPro:            session.User.IsPro,
		IsAdmin:          session.User.IsAdmin,
		LeaderboardOptIn: session.User.LeaderboardOptIn,
		UserCreatedAt:    session.User.CreatedAt.UTC().Format(time.RFC3339Nano),
		SessionID:        session.ID,
		DeviceID:         &device.DeviceID,
	}, s.JWTSecret, s.accessTTL(), now)
	if err != nil {
		return empty, err
	}
	newRefreshToken, err := token.GenerateRefreshToken()
	if err != nil {
		return empty, err
	}
	rotated, err := s.Repo.RotateSession(ctx, session.ID, token.HashToken(accessToken), token.HashToken(newRefreshToken), accessExpiresAt, refreshExpiresAt, device, trustedAt, now)
	if err != nil {
		return empty, err
	}
	policy := s.getPermissionPolicy(ctx, session.User.IsPro)
	payload := BuildAuthPayload(session.User, rotated, accessToken, accessExpiresAt, newRefreshToken, refreshExpiresAt, s.maxDevices(), policy)

	return payload, nil
}

func ParseRefreshRequest(req *http.Request) (RefreshRequestBody, DeviceInput) {
	var body RefreshRequestBody
	if req != nil && req.Body != nil {
		_ = json.NewDecoder(req.Body).Decode(&body)
	}
	device := DeviceInput{
		DeviceID:    body.DeviceID,
		DeviceName:  body.DeviceName,
		Platform:    body.Platform,
		TrustDevice: parseTrustDevice(body.TrustDevice),
	}
	return body, device
}

func RefreshTokenFromRequest(req *http.Request, body RefreshRequestBody) string {
	if token := strings.TrimSpace(body.RefreshToken); token != "" {
		return token
	}
	return httpauth.ReadRefreshTokenCookie(req)
}

func parseTrustDevice(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		switch strings.ToLower(strings.TrimSpace(typed)) {
		case "1", "true", "yes":
			return true
		default:
			return false
		}
	default:
		return false
	}
}

func (s RefreshService) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func (s RefreshService) accessTTL() time.Duration {
	if s.AccessTokenTTL > 0 {
		return s.AccessTokenTTL
	}
	return time.Hour
}

func (s RefreshService) refreshTTL() time.Duration {
	if s.RefreshTokenTTL > 0 {
		return s.RefreshTokenTTL
	}
	return 30 * 24 * time.Hour
}

func (s RefreshService) maxDevices() int {
	if s.MaxActiveDevices > 0 {
		return s.MaxActiveDevices
	}
	return 3
}

func (s RefreshService) getPermissionPolicy(ctx context.Context, isPro bool) PermissionPolicy {
	features := map[string]string{
		"talk_connection":         "pro",
		"focus_pomodoro":          "free",
		"focus_website_blocklist": "free",
		"media_controls":          "free",
		"browser_bridge":          "free",
		"panel_shelf":             "pro",
	}

	pgxRepo, ok := s.Repo.(*PgxSessionRepository)
	if ok && pgxRepo != nil && pgxRepo.db != nil {
		rows, err := pgxRepo.db.Query(ctx, `SELECT "key", "isProOnly", "isEnabled" FROM "FeatureConfig"`)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var key string
				var isProOnly bool
				var isEnabled bool
				if err := rows.Scan(&key, &isProOnly, &isEnabled); err == nil {
					if !isEnabled {
						features[key] = "disabled"
					} else if isProOnly {
						features[key] = "pro"
					} else {
						features[key] = "free"
					}
				}
			}
		}
	}

	return PermissionPolicy{
		Version:   1,
		Features:  features,
		UpdatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
}
