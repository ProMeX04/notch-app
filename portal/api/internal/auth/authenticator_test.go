package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"
)

type fakeHandoffRecord struct {
	ID            string
	TokenHash     string
	CodeChallenge string
	AccessToken   string
	RefreshToken  *string
	ExpiresIn     *int
	ExpiresAt     time.Time
	CreatedAt     time.Time
}

type fakeSessionRepo struct {
	byID           map[string]*Session
	usersByEmail   map[string]*User
	lastSeenID     string
	expiredID      string
	handoffs       []fakeHandoffRecord
	updatedAvatars map[string]*string
}

func (r *fakeSessionRepo) FindSessionByID(_ context.Context, sessionID string) (*Session, error) {
	return r.byID[sessionID], nil
}
func (r *fakeSessionRepo) FindSessionByRefreshTokenHash(_ context.Context, tokenHash string) (*Session, error) {
	for _, s := range r.byID {
		if s.TokenHash == tokenHash {
			return s, nil
		}
	}
	return nil, nil
}
func (r *fakeSessionRepo) RotateSession(_ context.Context, sessionID string, accessTokenHash string, refreshTokenHash string, accessExpiresAt time.Time, refreshExpiresAt time.Time, device NormalizedDevice, trustedAt *time.Time, _ time.Time) (RotatedSession, error) {
	if s, ok := r.byID[sessionID]; ok {
		s.TokenHash = refreshTokenHash
		s.AccessTokenHash = &accessTokenHash
		s.AccessExpiresAt = &accessExpiresAt
		s.ExpiresAt = refreshExpiresAt
		s.DeviceID = &device.DeviceID
		s.Platform = &device.Platform
		s.TrustedAt = trustedAt
	}
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
	u := &User{ID: id, Email: &email, Name: &name, Password: &hashedPassword, CreatedAt: now}
	if r.usersByEmail == nil {
		r.usersByEmail = make(map[string]*User)
	}
	r.usersByEmail[strings.ToLower(email)] = u
	return u, nil
}
func (r *fakeSessionRepo) FindUserByEmail(_ context.Context, email string) (*User, error) {
	if r.usersByEmail == nil {
		return nil, nil
	}
	return r.usersByEmail[strings.ToLower(email)], nil
}
func (r *fakeSessionRepo) CreateSession(_ context.Context, sessionID string, userID string, tokenHash string, accessTokenHash *string, device NormalizedDevice, expiresAt time.Time, accessExpiresAt *time.Time, trustedAt *time.Time, now time.Time) error {
	s := &Session{
		ID:              sessionID,
		TokenHash:       tokenHash,
		AccessTokenHash: accessTokenHash,
		DeviceID:        &device.DeviceID,
		ExpiresAt:       expiresAt,
		AccessExpiresAt: accessExpiresAt,
		UserID:          userID,
		CreatedAt:       now,
	}
	if r.byID == nil {
		r.byID = make(map[string]*Session)
	}
	r.byID[sessionID] = s
	return nil
}
func (r *fakeSessionRepo) UpdateUserPasswordAndName(_ context.Context, id string, name string, hashedPassword string, now time.Time) (*User, error) {
	var user *User
	for _, u := range r.usersByEmail {
		if u.ID == id {
			u.Password = &hashedPassword
			if name != "" {
				u.Name = &name
			}
			user = u
			break
		}
	}
	return user, nil
}
func (r *fakeSessionRepo) FindUserByID(_ context.Context, id string) (*User, error) {
	for _, u := range r.usersByEmail {
		if u.ID == id {
			return u, nil
		}
	}
	return nil, nil
}
func (r *fakeSessionRepo) RevokeSession(_ context.Context, sessionID string, revokedAt time.Time, reason string) error {
	if s, ok := r.byID[sessionID]; ok {
		s.RevokedAt = &revokedAt
		s.RevokedReason = &reason
	}
	return nil
}
func (r *fakeSessionRepo) FindActiveSessionsByUserID(_ context.Context, userID string) ([]*Session, error) {
	var active []*Session
	for _, s := range r.byID {
		if s.UserID == userID && s.RevokedAt == nil {
			active = append(active, s)
		}
	}
	return active, nil
}
func (r *fakeSessionRepo) FindAllSessionsByUserID(_ context.Context, userID string) ([]*Session, error) {
	var all []*Session
	for _, s := range r.byID {
		if s.UserID == userID {
			all = append(all, s)
		}
	}
	return all, nil
}
func (r *fakeSessionRepo) RevokeSessionByID(_ context.Context, sessionID string, userID string) error {
	if s, ok := r.byID[sessionID]; ok && s.UserID == userID {
		now := time.Now()
		reason := "user_revoked"
		s.RevokedAt = &now
		s.RevokedReason = &reason
	}
	return nil
}
func (r *fakeSessionRepo) CreateGoogleDriveAuthHandoff(_ context.Context, id string, tokenHash string, codeChallenge string, accessToken string, refreshToken *string, expiresIn *int, expiresAt time.Time, createdAt time.Time) error {
	r.handoffs = append(r.handoffs, fakeHandoffRecord{
		ID:            id,
		TokenHash:     tokenHash,
		CodeChallenge: codeChallenge,
		AccessToken:   accessToken,
		RefreshToken:  refreshToken,
		ExpiresIn:     expiresIn,
		ExpiresAt:     expiresAt,
		CreatedAt:     createdAt,
	})
	return nil
}
func (r *fakeSessionRepo) UpdateUserAvatar(_ context.Context, id string, avatarURL *string) error {
	if r.updatedAvatars == nil {
		r.updatedAvatars = make(map[string]*string)
	}
	r.updatedAvatars[id] = avatarURL
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
