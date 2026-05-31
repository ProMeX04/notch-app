package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"
)

type fakeSessionRepo struct {
	byID       map[string]*Session
	lastSeenID string
	expiredID  string
}

func (r *fakeSessionRepo) FindSessionByID(_ context.Context, sessionID string) (*Session, error) {
	return r.byID[sessionID], nil
}
func (r *fakeSessionRepo) FindSessionByRefreshTokenHash(_ context.Context, tokenHash string) (*Session, error) {
	return nil, nil
}
func (r *fakeSessionRepo) RotateSession(_ context.Context, sessionID string, _ string, _ string, _ time.Time, _ time.Time, device NormalizedDevice, trustedAt *time.Time, _ time.Time) (RotatedSession, error) {
	return RotatedSession{ID: sessionID, DeviceID: device.DeviceID, DeviceName: device.DeviceName, Platform: device.Platform, TrustedAt: trustedAt}, nil
}
func (r *fakeSessionRepo) UpdateLastSeen(_ context.Context, sessionID string, _ time.Time) error {
	r.lastSeenID = sessionID
	return nil
}
func (r *fakeSessionRepo) MarkSessionExpired(_ context.Context, sessionID string, _ time.Time) error {
	r.expiredID = sessionID
	return nil
}
func (r *fakeSessionRepo) CreateUser(_ context.Context, id string, email string, name string, hashedPassword string, now time.Time) (*User, error) {
	return &User{ID: id, Email: &email, Name: &name, CreatedAt: now}, nil
}
func (r *fakeSessionRepo) FindUserByEmail(_ context.Context, email string) (*User, error) {
	return nil, nil
}
func (r *fakeSessionRepo) CreateSession(_ context.Context, sessionID string, userID string, tokenHash string, accessTokenHash *string, device NormalizedDevice, expiresAt time.Time, accessExpiresAt *time.Time, trustedAt *time.Time, now time.Time) error {
	return nil
}

func TestAuthenticatorAcceptsSessionBoundJWT(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	deviceID := "device_1"
	user := User{ID: "user_1", CreatedAt: now}
	payload := token.JWTPayload{UserID: user.ID, SessionID: "session_1", DeviceID: &deviceID, UserCreatedAt: now.Format(time.RFC3339)}
	jwtToken, err := token.SignJWT(payload, "secret", time.Hour, now)
	if err != nil {
		t.Fatalf("token.SignJWT() error = %v", err)
	}
	accessHash := token.HashToken(jwtToken)
	repo := &fakeSessionRepo{byID: map[string]*Session{
		"session_1": sessionFixture(user, "session_1", &accessHash, &deviceID, now.Add(time.Hour)),
	}}
	authenticator := Authenticator{Repo: repo, JWTSecret: "secret", Now: func() time.Time { return now }}

	ctx, err := authenticator.AuthenticateAccessToken(context.Background(), jwtToken, &deviceID)
	if err != nil {
		t.Fatalf("AuthenticateAccessToken() error = %v", err)
	}
	if ctx.User.ID != user.ID || ctx.SessionID != "session_1" || repo.lastSeenID != "session_1" {
		t.Fatalf("unexpected auth context/repo: %#v repo=%#v", ctx, repo)
	}
}

func TestAuthenticatorRejectsNonJWTAccessToken(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	authenticator := Authenticator{Repo: &fakeSessionRepo{byID: map[string]*Session{}}, JWTSecret: "secret", Now: func() time.Time { return now }}
	if _, err := authenticator.AuthenticateAccessToken(context.Background(), "opaque-token", nil); err == nil {
		t.Fatal("expected non-JWT access token to reject")
	}
}

func TestAuthenticatorRejectsRevokedJWTSession(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	jwtToken, _ := token.SignJWT(token.JWTPayload{UserID: "user_1", SessionID: "session_1"}, "secret", time.Hour, now)
	accessHash := token.HashToken(jwtToken)
	revokedAt := now.Add(-time.Minute)
	session := sessionFixture(User{ID: "user_1"}, "session_1", &accessHash, nil, now.Add(time.Hour))
	session.RevokedAt = &revokedAt
	authenticator := Authenticator{Repo: &fakeSessionRepo{byID: map[string]*Session{"session_1": session}}, JWTSecret: "secret", Now: func() time.Time { return now }}

	if _, err := authenticator.AuthenticateAccessToken(context.Background(), jwtToken, nil); err == nil {
		t.Fatal("expected revoked session to reject")
	}
}

func TestAuthenticatorRejectsJWTAccessHashMismatch(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	jwtToken, _ := token.SignJWT(token.JWTPayload{UserID: "user_1", SessionID: "session_1"}, "secret", time.Hour, now)
	wrongHash := token.HashToken("other-token")
	authenticator := Authenticator{Repo: &fakeSessionRepo{byID: map[string]*Session{
		"session_1": sessionFixture(User{ID: "user_1"}, "session_1", &wrongHash, nil, now.Add(time.Hour)),
	}}, JWTSecret: "secret", Now: func() time.Time { return now }}

	if _, err := authenticator.AuthenticateAccessToken(context.Background(), jwtToken, nil); err == nil {
		t.Fatal("expected hash mismatch to reject")
	}
}

func TestAuthenticatorRejectsDeviceMismatch(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	deviceID := "device_1"
	requestDeviceID := "device_2"
	jwtToken, _ := token.SignJWT(token.JWTPayload{UserID: "user_1", SessionID: "session_1", DeviceID: &deviceID}, "secret", time.Hour, now)
	accessHash := token.HashToken(jwtToken)
	authenticator := Authenticator{Repo: &fakeSessionRepo{byID: map[string]*Session{
		"session_1": sessionFixture(User{ID: "user_1"}, "session_1", &accessHash, &deviceID, now.Add(time.Hour)),
	}}, JWTSecret: "secret", Now: func() time.Time { return now }}

	if _, err := authenticator.AuthenticateAccessToken(context.Background(), jwtToken, &requestDeviceID); err == nil {
		t.Fatal("expected device mismatch to reject")
	}
}

func TestAuthenticatorReadsBearerBeforeCookie(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	bearerToken, _ := token.SignJWT(token.JWTPayload{UserID: "user_1", SessionID: "bearer_session"}, "secret", time.Hour, now)
	cookieToken, _ := token.SignJWT(token.JWTPayload{UserID: "user_2", SessionID: "cookie_session"}, "secret", time.Hour, now)
	bearerHash := token.HashToken(bearerToken)
	cookieHash := token.HashToken(cookieToken)
	repo := &fakeSessionRepo{byID: map[string]*Session{
		"bearer_session": sessionFixture(User{ID: "user_1"}, "bearer_session", &bearerHash, nil, now.Add(time.Hour)),
		"cookie_session": sessionFixture(User{ID: "user_2"}, "cookie_session", &cookieHash, nil, now.Add(time.Hour)),
	}}
	authenticator := Authenticator{Repo: repo, JWTSecret: "secret", Now: func() time.Time { return now }}
	req := httptest.NewRequest(http.MethodGet, "/api/auth/me", nil)
	req.Header.Set("authorization", "Bearer "+bearerToken)
	req.Header.Set("cookie", httpauth.AccessCookieName+"="+cookieToken)

	ctx, err := authenticator.AuthenticateRequest(context.Background(), req)
	if err != nil {
		t.Fatalf("AuthenticateRequest() error = %v", err)
	}
	if ctx.SessionID != "bearer_session" {
		t.Fatalf("used %q, want bearer_session", ctx.SessionID)
	}
}

func sessionFixture(user User, id string, accessHash *string, deviceID *string, accessExpiresAt time.Time) *Session {
	return &Session{
		ID:              id,
		TokenHash:       "refresh_hash",
		AccessTokenHash: accessHash,
		DeviceID:        deviceID,
		ExpiresAt:       accessExpiresAt.Add(24 * time.Hour),
		AccessExpiresAt: &accessExpiresAt,
		UserID:          user.ID,
		User:            user,
	}
}
