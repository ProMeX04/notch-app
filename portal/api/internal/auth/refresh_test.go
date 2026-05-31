package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"notch/portal/api/internal/auth/token"
)

type refreshRepo struct {
	session        *Session
	rotated        RotatedSession
	rotatedDevice  NormalizedDevice
	refreshHashArg string
	expiredID      string
}

func (r *refreshRepo) FindSessionByID(context.Context, string) (*Session, error) { return nil, nil }
func (r *refreshRepo) FindSessionByAccessTokenHash(context.Context, string) (*Session, error) {
	return nil, nil
}
func (r *refreshRepo) FindLegacySessionByTokenHash(context.Context, string) (*Session, error) {
	return nil, nil
}
func (r *refreshRepo) FindSessionByRefreshTokenHash(_ context.Context, tokenHash string) (*Session, error) {
	r.refreshHashArg = tokenHash
	if r.session != nil && r.session.TokenHash == tokenHash {
		return r.session, nil
	}
	return nil, nil
}
func (r *refreshRepo) RotateSession(_ context.Context, sessionID string, _ string, _ string, _ time.Time, _ time.Time, device NormalizedDevice, trustedAt *time.Time, _ time.Time) (RotatedSession, error) {
	r.rotatedDevice = device
	r.rotated = RotatedSession{ID: sessionID, DeviceID: device.DeviceID, DeviceName: device.DeviceName, Platform: device.Platform, TrustedAt: trustedAt}
	return r.rotated, nil
}
func (r *refreshRepo) UpdateLastSeen(context.Context, string, time.Time) error { return nil }
func (r *refreshRepo) MarkSessionExpired(_ context.Context, sessionID string, _ time.Time) error {
	r.expiredID = sessionID
	return nil
}
func (r *refreshRepo) CreateUser(_ context.Context, id string, email string, name string, hashedPassword string, now time.Time) (*User, error) {
	return &User{ID: id, Email: &email, Name: &name, CreatedAt: now}, nil
}
func (r *refreshRepo) FindUserByEmail(_ context.Context, email string) (*User, error) {
	return nil, nil
}
func (r *refreshRepo) CreateSession(_ context.Context, sessionID string, userID string, tokenHash string, accessTokenHash *string, device NormalizedDevice, expiresAt time.Time, accessExpiresAt *time.Time, trustedAt *time.Time, now time.Time) error {
	return nil
}
func (r *refreshRepo) UpdateUserPasswordAndName(_ context.Context, id string, name string, hashedPassword string, now time.Time) (*User, error) {
	return &User{ID: id, Name: &name, CreatedAt: now}, nil
}
func (r *refreshRepo) FindUserByID(_ context.Context, id string) (*User, error) {
	return nil, nil
}
func (r *refreshRepo) RevokeSession(_ context.Context, sessionID string, revokedAt time.Time, reason string) error {
	return nil
}
func (r *refreshRepo) FindActiveSessionsByUserID(_ context.Context, userID string) ([]*Session, error) {
	return nil, nil
}
func (r *refreshRepo) FindAllSessionsByUserID(_ context.Context, userID string) ([]*Session, error) {
	return nil, nil
}
func (r *refreshRepo) RevokeSessionByID(_ context.Context, sessionID string, userID string) error {
	return nil
}
func (r *refreshRepo) CreateGoogleDriveAuthHandoff(_ context.Context, id string, tokenHash string, codeChallenge string, accessToken string, refreshToken *string, expiresIn *int, expiresAt time.Time, createdAt time.Time) error {
	return nil
}
func (r *refreshRepo) UpdateUserAvatar(_ context.Context, id string, avatarURL *string) error {
	return nil
}

func TestRefreshServiceRotatesValidRefreshToken(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	refreshToken := "refresh-token"
	deviceID := "browser-device"
	email := "user@example.com"
	repo := &refreshRepo{session: &Session{
		ID:        "session_1",
		TokenHash: token.HashToken(refreshToken),
		DeviceID:  ptr("old-device"),
		ExpiresAt: now.Add(24 * time.Hour),
		UserID:    "user_1",
		User: User{
			ID:        "user_1",
			Email:     &email,
			CreatedAt: now.Add(-24 * time.Hour),
			IsPro:     true,
		},
	}}
	service := RefreshService{Repo: repo, JWTSecret: "secret", AccessTokenTTL: time.Hour, RefreshTokenTTL: 30 * 24 * time.Hour, MaxActiveDevices: 3, Now: func() time.Time { return now }}
	req := httptest.NewRequest(http.MethodPost, "/api/auth/refresh", nil)

	payload, err := service.RefreshWithToken(context.Background(), req, refreshToken, DeviceInput{DeviceID: deviceID})
	if err != nil {
		t.Fatalf("RefreshWithToken() error = %v", err)
	}
	if payload.TokenType != token.BearerScheme || payload.RefreshToken == "" || payload.AccessToken == "" {
		t.Fatalf("unexpected payload tokens: %#v", payload)
	}
	if payload.User.ID != "user_1" || payload.User.Email != email || !payload.User.IsPro {
		t.Fatalf("unexpected payload user: %#v", payload.User)
	}
	if payload.Session.ID != "session_1" || payload.Session.DeviceID != deviceID {
		t.Fatalf("unexpected payload session: %#v", payload.Session)
	}
	if repo.refreshHashArg != token.HashToken(refreshToken) {
		t.Fatalf("refresh lookup hash = %q", repo.refreshHashArg)
	}
	if repo.rotatedDevice.DeviceID != deviceID {
		t.Fatalf("rotated device = %#v", repo.rotatedDevice)
	}
}

func TestRefreshServiceRejectsExpiredAndMarksSession(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	refreshToken := "refresh-token"
	repo := &refreshRepo{session: &Session{
		ID:        "session_1",
		TokenHash: token.HashToken(refreshToken),
		ExpiresAt: now.Add(-time.Second),
		UserID:    "user_1",
		User:      User{ID: "user_1", CreatedAt: now},
	}}
	service := RefreshService{Repo: repo, JWTSecret: "secret", Now: func() time.Time { return now }}

	if _, err := service.RefreshWithToken(context.Background(), httptest.NewRequest(http.MethodPost, "/", nil), refreshToken, DeviceInput{}); err == nil {
		t.Fatal("expected expired refresh token to fail")
	}
	if repo.expiredID != "session_1" {
		t.Fatalf("expiredID = %q", repo.expiredID)
	}
}

func ptr(value string) *string { return &value }
