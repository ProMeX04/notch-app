package auth

import "time"

type PermissionPolicy struct {
	Features map[string]bool `json:"features"`
}

type UserResponse struct {
	ID               string           `json:"id"`
	Email            string           `json:"email"`
	Name             *string          `json:"name"`
	DisplayName      *string          `json:"display_name"`
	AvatarURL        *string          `json:"avatar_url"`
	CreatedAt        string           `json:"created_at"`
	IsPro            bool             `json:"is_pro"`
	LeaderboardOptIn bool             `json:"leaderboard_opt_in"`
	PermissionPolicy PermissionPolicy `json:"permission_policy"`
	CurrentSessionID *string          `json:"current_session_id"`
	MaxActiveDevices int              `json:"max_active_devices"`
}

func BuildUserResponse(user User, sessionID *string, maxActiveDevices int) UserResponse {
	email := ""
	if user.Email != nil {
		email = *user.Email
	}
	createdAt := user.CreatedAt.UTC().Format(time.RFC3339Nano)
	return UserResponse{
		ID:               user.ID,
		Email:            email,
		Name:             user.Name,
		DisplayName:      user.DisplayName,
		AvatarURL:        user.AvatarURL,
		CreatedAt:        createdAt,
		IsPro:            user.IsPro,
		LeaderboardOptIn: user.LeaderboardOptIn,
		PermissionPolicy: PermissionPolicy{Features: map[string]bool{}},
		CurrentSessionID: sessionID,
		MaxActiveDevices: maxActiveDevices,
	}
}
