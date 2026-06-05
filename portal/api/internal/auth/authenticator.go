package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"

	"github.com/jackc/pgx/v5"
)

var ErrUnauthenticated = errors.New("unauthenticated")

type Authenticator struct {
	Repo      SessionRepository
	JWTSecret string
	Now       func() time.Time
}

func (a Authenticator) AuthenticateRequest(ctx context.Context, req *http.Request) (*AuthContext, error) {
	token := accessTokenFromRequest(req)
	if token == "" {
		return nil, ErrUnauthenticated
	}
	requestDeviceID := requestDeviceID(req)
	return a.AuthenticateAccessToken(ctx, token, requestDeviceID)
}

func (a Authenticator) AuthenticateAccessToken(ctx context.Context, rawToken string, requestDeviceID *string) (*AuthContext, error) {
	if strings.TrimSpace(rawToken) == "" || a.Repo == nil {
		return nil, ErrUnauthenticated
	}
	now := a.now()
	payload, err := token.VerifyJWT(rawToken, a.JWTSecret, now)
	if err != nil {
		return nil, ErrUnauthenticated
	}
	return a.authenticateJWT(ctx, rawToken, payload, requestDeviceID, now)
}

func (a Authenticator) authenticateJWT(ctx context.Context, rawToken string, payload *token.JWTPayload, requestDeviceID *string, now time.Time) (*AuthContext, error) {
	var revokedAt *time.Time
	var lastSeenAt time.Time
	var platform *string
	var deviceID *string
	var isFallback = true

	if pgxRepo, ok := a.Repo.(*PgxSessionRepository); ok && pgxRepo != nil && pgxRepo.db != nil {
		err := pgxRepo.db.QueryRow(ctx, `
			SELECT "revokedAt", "lastSeenAt", "platform", "deviceId"
			FROM "AuthSession"
			WHERE "id" = $1
			LIMIT 1
		`, payload.SessionID).Scan(&revokedAt, &lastSeenAt, &platform, &deviceID)
		if err == pgx.ErrNoRows {
			return nil, ErrUnauthenticated
		}
		if err != nil {
			return nil, ErrUnauthenticated
		}
		isFallback = false
	}

	if isFallback {
		session, err := a.Repo.FindSessionByID(ctx, payload.SessionID)
		if err != nil || session == nil {
			return nil, ErrUnauthenticated
		}
		revokedAt = session.RevokedAt
		lastSeenAt = session.LastSeenAt
		platform = session.Platform
		deviceID = session.DeviceID
	}

	if revokedAt != nil {
		return nil, ErrUnauthenticated
	}

	// Device check: Enforce DeviceID matching strictly for macOS App sessions
	if platform != nil && *platform == "macOS" {
		if deviceID != nil && !sameStringPtr(deviceID, requestDeviceID) {
			return nil, ErrUnauthenticated
		}
	}

	// Throttle lastSeenAt updates to at most once per 15 minutes
	if now.Sub(lastSeenAt) > 15*time.Minute {
		go func(id string) {
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			_ = a.Repo.UpdateLastSeen(ctx, id, now)
		}(payload.SessionID)
	}

	userCreatedAt, _ := time.Parse(time.RFC3339Nano, payload.UserCreatedAt)
	user := User{
		ID:               payload.UserID,
		Email:            payload.Email,
		Name:             payload.Name,
		DisplayName:      payload.DisplayName,
		AvatarURL:        payload.AvatarURL,
		IsPro:            payload.IsPro,
		IsAdmin:          payload.IsAdmin,
		LeaderboardOptIn: payload.LeaderboardOptIn,
		CreatedAt:        userCreatedAt,
	}

	return &AuthContext{
		SessionID: payload.SessionID,
		DeviceID:  deviceID,
		User:      user,
	}, nil
}

func validateSession(session *Session, tokenHash string, requestDeviceID *string, now time.Time, requireAccessHash bool) error {
	if session == nil || session.RevokedAt != nil {
		return ErrUnauthenticated
	}
	expiresAt := accessExpiry(session)
	if !expiresAt.After(now) {
		return ErrUnauthenticated
	}
	if requireAccessHash {
		if session.AccessTokenHash == nil || *session.AccessTokenHash != tokenHash {
			return ErrUnauthenticated
		}
	} else if session.AccessTokenHash != nil && *session.AccessTokenHash != tokenHash {
		return ErrUnauthenticated
	}
	if session.DeviceID != nil && !sameStringPtr(session.DeviceID, requestDeviceID) {
		return ErrUnauthenticated
	}
	return nil
}

func accessExpiry(session *Session) time.Time {
	if session.AccessTokenExpiresAt != nil {
		return *session.AccessTokenExpiresAt
	}
	return session.RefreshTokenExpiresAt
}

func (a Authenticator) now() time.Time {
	if a.Now != nil {
		return a.Now()
	}
	return time.Now()
}

func accessTokenFromRequest(req *http.Request) string {
	if req == nil {
		return ""
	}
	if accessToken := httpauth.ExtractBearerToken(req.Header.Get("authorization")); accessToken != "" {
		return accessToken
	}
	return httpauth.ExtractCookieToken(req.Header.Get("cookie"), httpauth.AccessCookieName)
}

func requestDeviceID(req *http.Request) *string {
	if req == nil {
		return nil
	}
	value := strings.TrimSpace(req.Header.Get("x-notch-device-id"))
	if value == "" {
		return nil
	}
	return &value
}

func sameStringPtr(a *string, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func sessionRejectReason(session *Session, tokenHash string, requestDeviceID *string, now time.Time, requireAccessHash bool) string {
	if session == nil {
		return "session_nil"
	}
	if session.RevokedAt != nil {
		return "session_revoked"
	}
	if !accessExpiry(session).After(now) {
		return "access_expired"
	}
	if requireAccessHash && session.AccessTokenHash == nil {
		return "missing_access_hash"
	}
	if requireAccessHash && *session.AccessTokenHash != tokenHash {
		return "access_hash_mismatch"
	}
	if !requireAccessHash && session.AccessTokenHash != nil && *session.AccessTokenHash != tokenHash {
		return "access_hash_mismatch"
	}
	if session.DeviceID != nil && !sameStringPtr(session.DeviceID, requestDeviceID) {
		return "session_device_mismatch"
	}
	return "unknown"
}

func debugStringPtr(value *string) string {
	if value == nil {
		return "<nil>"
	}
	return *value
}
