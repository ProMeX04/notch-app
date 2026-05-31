package auth

import (
	"time"

	"notch/portal/api/internal/auth/token"
)

type AuthPayload struct {
	AccessToken      string             `json:"access_token"`
	TokenType        string             `json:"token_type"`
	ExpiresAt        string             `json:"expires_at"`
	RefreshToken     string             `json:"refresh_token"`
	RefreshExpiresAt string             `json:"refresh_expires_at"`
	User             AuthPayloadUser    `json:"user"`
	Session          AuthPayloadSession `json:"session"`
	MaxActiveDevices int                `json:"max_active_devices"`
}

type AuthPayloadUser struct {
	ID               string           `json:"id"`
	Email            string           `json:"email"`
	Name             *string          `json:"name"`
	DisplayName      *string          `json:"display_name"`
	AvatarURL        *string          `json:"avatar_url"`
	CreatedAt        string           `json:"created_at"`
	IsPro            bool             `json:"is_pro"`
	LeaderboardOptIn bool             `json:"leaderboard_opt_in"`
	PermissionPolicy PermissionPolicy `json:"permission_policy"`
}

type AuthPayloadSession struct {
	ID         string  `json:"id"`
	DeviceID   string  `json:"device_id"`
	DeviceName string  `json:"device_name"`
	Platform   string  `json:"platform"`
	TrustedAt  *string `json:"trusted_at"`
}

type RotatedSession struct {
	ID         string
	DeviceID   string
	DeviceName string
	Platform   string
	TrustedAt  *time.Time
}

func BuildAuthPayload(user User, session RotatedSession, accessToken string, accessExpiresAt time.Time, refreshToken string, refreshExpiresAt time.Time, maxActiveDevices int) AuthPayload {
	email := ""
	if user.Email != nil {
		email = *user.Email
	}
	var trustedAt *string
	if session.TrustedAt != nil {
		value := session.TrustedAt.UTC().Format(time.RFC3339Nano)
		trustedAt = &value
	}
	return AuthPayload{
		AccessToken:      accessToken,
		TokenType:        token.BearerScheme,
		ExpiresAt:        accessExpiresAt.UTC().Format(time.RFC3339Nano),
		RefreshToken:     refreshToken,
		RefreshExpiresAt: refreshExpiresAt.UTC().Format(time.RFC3339Nano),
		User: AuthPayloadUser{
			ID:               user.ID,
			Email:            email,
			Name:             user.Name,
			DisplayName:      user.DisplayName,
			AvatarURL:        user.AvatarURL,
			CreatedAt:        user.CreatedAt.UTC().Format(time.RFC3339Nano),
			IsPro:            user.IsPro,
			LeaderboardOptIn: user.LeaderboardOptIn,
			PermissionPolicy: PermissionPolicy{Features: map[string]bool{}},
		},
		Session: AuthPayloadSession{
			ID:         session.ID,
			DeviceID:   session.DeviceID,
			DeviceName: session.DeviceName,
			Platform:   session.Platform,
			TrustedAt:  trustedAt,
		},
		MaxActiveDevices: maxActiveDevices,
	}
}
