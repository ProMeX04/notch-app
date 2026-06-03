package auth

import (
	"context"
	"time"
)

type User struct {
	ID               string
	Email            *string
	Name             *string
	DisplayName      *string
	AvatarURL        *string
	Password         *string
	CreatedAt        time.Time
	IsPro            bool
	IsAdmin          bool
	LeaderboardOptIn bool
}

type Session struct {
	ID              string
	TokenHash       string
	AccessTokenHash *string
	DeviceID        *string
	DeviceName      *string
	Platform        *string
	ExpiresAt       time.Time
	AccessExpiresAt *time.Time
	CreatedAt       time.Time
	LastSeenAt      time.Time
	TrustedAt       *time.Time
	RevokedAt       *time.Time
	RevokedReason   *string
	UserID          string
	User            User
}

type AuthContext struct {
	SessionID string
	DeviceID  *string
	User      User
}

type OAuthAuthorizationCode struct {
	ID                  string
	CodeHash            string
	ClientID            string
	RedirectURI         string
	CodeChallenge       string
	CodeChallengeMethod string
	ExpiresAt           time.Time
	CreatedAt           time.Time
	ConsumedAt          *time.Time
	UserID              string
	User                User
}

type SessionRepository interface {
	FindSessionByID(ctx context.Context, sessionID string) (*Session, error)
	FindSessionByRefreshTokenHash(ctx context.Context, tokenHash string) (*Session, error)
	RotateSession(ctx context.Context, sessionID string, accessTokenHash string, refreshTokenHash string, accessExpiresAt time.Time, refreshExpiresAt time.Time, device NormalizedDevice, trustedAt *time.Time, now time.Time) (RotatedSession, error)
	UpdateLastSeen(ctx context.Context, sessionID string, seenAt time.Time) error
	MarkSessionExpired(ctx context.Context, sessionID string, expiredAt time.Time) error
	CreateUser(ctx context.Context, id string, email string, name string, hashedPassword string, now time.Time) (*User, error)
	FindUserByEmail(ctx context.Context, email string) (*User, error)
	CreateSession(ctx context.Context, sessionID string, userID string, tokenHash string, accessTokenHash *string, device NormalizedDevice, expiresAt time.Time, accessExpiresAt *time.Time, trustedAt *time.Time, now time.Time) error
	UpdateUserPasswordAndName(ctx context.Context, id string, name string, hashedPassword string, now time.Time) (*User, error)
	FindUserByID(ctx context.Context, id string) (*User, error)
	RevokeSession(ctx context.Context, sessionID string, revokedAt time.Time, reason string) error
	FindActiveSessionsByUserID(ctx context.Context, userID string) ([]*Session, error)
	FindAllSessionsByUserID(ctx context.Context, userID string) ([]*Session, error)
	RevokeSessionByID(ctx context.Context, sessionID string, userID string) error
	CreateGoogleDriveAuthHandoff(ctx context.Context, id string, tokenHash string, codeChallenge string, accessToken string, refreshToken *string, expiresIn *int, expiresAt time.Time, createdAt time.Time) error
	UpdateUserAvatar(ctx context.Context, id string, avatarURL *string) error
	SetTrustedDevice(ctx context.Context, userID string, deviceID string, trusted bool) error
	RevokeDeviceSessions(ctx context.Context, userID string, deviceID string, exceptSessionID string) error

	CreateOAuthAuthorizationCode(ctx context.Context, code *OAuthAuthorizationCode) error
	FindOAuthAuthorizationCode(ctx context.Context, codeHash string) (*OAuthAuthorizationCode, error)
	ConsumeOAuthAuthorizationCode(ctx context.Context, id string, consumedAt time.Time) error

	FindGoogleDriveAuthHandoff(ctx context.Context, tokenHash string) (*GoogleDriveAuthHandoff, error)
	ConsumeGoogleDriveAuthHandoff(ctx context.Context, handoffID string, consumedAt time.Time) error
	DeleteExpiredGoogleDriveAuthHandoffs(ctx context.Context, maxExpiresAt time.Time) error
}

type GoogleDriveAuthHandoff struct {
	ID            string
	TokenHash     string
	CodeChallenge string
	AccessToken   string
	RefreshToken  *string
	ExpiresIn     *int
	ExpiresAt     time.Time
	CreatedAt     time.Time
	ConsumedAt    *time.Time
}
