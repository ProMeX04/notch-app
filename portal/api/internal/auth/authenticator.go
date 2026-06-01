package auth

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"
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
	if payload.DeviceID != nil && !sameStringPtr(payload.DeviceID, requestDeviceID) {
		fmt.Printf("[DEBUG Auth] reject=payload_device_mismatch sessionID=%s payloadDevice=%s requestDevice=%s\n", payload.SessionID, debugStringPtr(payload.DeviceID), debugStringPtr(requestDeviceID))
		return nil, ErrUnauthenticated
	}
	session, err := a.Repo.FindSessionByID(ctx, payload.SessionID)
	if err != nil {
		fmt.Printf("[DEBUG Auth] reject=session_lookup_error sessionID=%s err=%v\n", payload.SessionID, err)
		return nil, ErrUnauthenticated
	}
	if session == nil {
		fmt.Printf("[DEBUG Auth] reject=session_not_found sessionID=%s\n", payload.SessionID)
		return nil, ErrUnauthenticated
	}
	if session.UserID != payload.UserID {
		fmt.Printf("[DEBUG Auth] reject=user_mismatch sessionID=%s payloadUser=%s sessionUser=%s\n", payload.SessionID, payload.UserID, session.UserID)
		return nil, ErrUnauthenticated
	}
	accessHash := token.HashToken(rawToken)
	if err := validateSession(session, accessHash, requestDeviceID, now, true); err != nil {
		fmt.Printf("[DEBUG Auth] reject=%s sessionID=%s requestDevice=%s sessionDevice=%s accessHashMatch=%t accessHashPresent=%t accessExpiresAt=%s now=%s revoked=%t\n", sessionRejectReason(session, accessHash, requestDeviceID, now, true), payload.SessionID, debugStringPtr(requestDeviceID), debugStringPtr(session.DeviceID), session.AccessTokenHash != nil && *session.AccessTokenHash == accessHash, session.AccessTokenHash != nil, accessExpiry(session).UTC().Format(time.RFC3339), now.UTC().Format(time.RFC3339), session.RevokedAt != nil)
		return nil, err
	}
	_ = a.Repo.UpdateLastSeen(ctx, session.ID, now)
	return &AuthContext{SessionID: session.ID, DeviceID: session.DeviceID, User: session.User}, nil
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
	if session.AccessExpiresAt != nil {
		return *session.AccessExpiresAt
	}
	return session.ExpiresAt
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
