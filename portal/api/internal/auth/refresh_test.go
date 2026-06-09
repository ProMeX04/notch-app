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
	session              *Session
	rotated              RotatedSession
	rotatedDevice        NormalizedDevice
	refreshHashArg       string
	expiredID            string
	revokedSessionID     string
	revokedReason        string
	revokeAllUserID      string
	revokeAllReason      string
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
	if r.session != nil {
		if r.session.TokenHash == tokenHash || (r.session.OldTokenHash != nil && *r.session.OldTokenHash == tokenHash) {
			return r.session, nil
		}
	}
	return nil, nil
}
func (r *refreshRepo) RotateSession(_ context.Context, sessionID string, oldTokenHash string, tokenRotatedAt time.Time, accessTokenHash string, refreshTokenHash string, accessExpiresAt time.Time, refreshExpiresAt time.Time, device NormalizedDevice, trustedAt *time.Time, now time.Time) (RotatedSession, error) {
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
	r.revokedSessionID = sessionID
	r.revokedReason = reason
	return nil
}
func (r *refreshRepo) RevokeAllSessionsByUserID(_ context.Context, userID string, reason string) error {
	r.revokeAllUserID = userID
	r.revokeAllReason = reason
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
func (r *refreshRepo) SetTrustedDevice(_ context.Context, userID string, deviceID string, trusted bool) error {
	return nil
}
func (r *refreshRepo) RevokeDeviceSessions(_ context.Context, userID string, deviceID string, exceptSessionID string) error {
	return nil
}
func (r *refreshRepo) CreateOAuthAuthorizationCode(_ context.Context, _ *OAuthAuthorizationCode) error {
	return nil
}
func (r *refreshRepo) FindOAuthAuthorizationCode(_ context.Context, _ string) (*OAuthAuthorizationCode, error) {
	return nil, nil
}
func (r *refreshRepo) ConsumeOAuthAuthorizationCode(_ context.Context, _ string, _ time.Time) (int64, error) {
	return 1, nil
}
func (r *refreshRepo) FindGoogleDriveAuthHandoff(_ context.Context, _ string) (*GoogleDriveAuthHandoff, error) {
	return nil, nil
}
func (r *refreshRepo) ConsumeGoogleDriveAuthHandoff(_ context.Context, _ string, _ time.Time) (int64, error) {
	return 1, nil
}
func (r *refreshRepo) DeleteExpiredGoogleDriveAuthHandoffs(_ context.Context, _ time.Time) error {
	return nil
}

func TestRefreshServiceRotatesValidRefreshToken(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	refreshToken := "refresh-token"
	deviceID := "browser-device"
	email := "user@example.com"
	repo := &refreshRepo{session: &Session{
		ID:                    "session_1",
		TokenHash:             token.HashToken(refreshToken),
		DeviceID:              ptr("old-device"),
		RefreshTokenExpiresAt: now.Add(24 * time.Hour),
		UserID:                "user_1",
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
		ID:                    "session_1",
		TokenHash:             token.HashToken(refreshToken),
		RefreshTokenExpiresAt: now.Add(-time.Second),
		UserID:                "user_1",
		User:                  User{ID: "user_1", CreatedAt: now},
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
func timePtr(value time.Time) *time.Time { return &value }

func TestRefreshServiceGraceWindowSuccess(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	oldRefreshToken := "old-refresh-token"
	newRefreshToken := "new-refresh-token"
	repo := &refreshRepo{session: &Session{
		ID:                    "session_1",
		TokenHash:             token.HashToken(newRefreshToken),
		OldTokenHash:          ptr(token.HashToken(oldRefreshToken)),
		TokenRotatedAt:        timePtr(now.Add(-30 * time.Second)), // Rotated 30 seconds ago (under 60s)
		RefreshTokenExpiresAt: now.Add(24 * time.Hour),
		UserID:                "user_1",
		User:                  User{ID: "user_1", CreatedAt: now},
	}}
	service := RefreshService{Repo: repo, JWTSecret: "secret", Now: func() time.Time { return now }}

	payload, err := service.RefreshWithToken(context.Background(), httptest.NewRequest(http.MethodPost, "/", nil), oldRefreshToken, DeviceInput{})
	if err != nil {
		t.Fatalf("expected successful refresh within grace window, got error: %v", err)
	}
	if payload.RefreshToken == "" {
		t.Fatal("expected non-empty refresh token in payload")
	}
}

func TestRefreshServiceReplayAttackRevokesSingleSession(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	oldRefreshToken := "old-refresh-token"
	newRefreshToken := "new-refresh-token"
	repo := &refreshRepo{session: &Session{
		ID:                    "session_1",
		TokenHash:             token.HashToken(newRefreshToken),
		OldTokenHash:          ptr(token.HashToken(oldRefreshToken)),
		TokenRotatedAt:        timePtr(now.Add(-65 * time.Second)), // Rotated 65 seconds ago (above 60s)
		RefreshTokenExpiresAt: now.Add(24 * time.Hour),
		UserID:                "user_1",
		User:                  User{ID: "user_1", CreatedAt: now},
	}}
	service := RefreshService{Repo: repo, JWTSecret: "secret", Now: func() time.Time { return now }}

	_, err := service.RefreshWithToken(context.Background(), httptest.NewRequest(http.MethodPost, "/", nil), oldRefreshToken, DeviceInput{})
	if err != ErrRefreshInvalid {
		t.Fatalf("expected ErrRefreshInvalid, got: %v", err)
	}

	// Verify that ONLY the current session was revoked (using RevokeSession)
	if repo.revokedSessionID != "session_1" {
		t.Fatalf("expected session_1 to be revoked, got: %q", repo.revokedSessionID)
	}
	if repo.revokedReason != "replay_attack" {
		t.Fatalf("expected revocation reason 'replay_attack', got: %q", repo.revokedReason)
	}

	// Verify that all sessions of the user were NOT revoked (using RevokeAllSessionsByUserID)
	if repo.revokeAllUserID != "" {
		t.Fatalf("expected no call to RevokeAllSessionsByUserID, but got userID: %q", repo.revokeAllUserID)
	}
}



