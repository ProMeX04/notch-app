package auth

import "time"

type PermissionPolicy struct {
	Version   int               `json:"version"`
	Features  map[string]string `json:"features"`
	UpdatedAt string            `json:"updated_at,omitempty"`
}

type UserResponse struct {
	ID               string           `json:"id"`
	Email            string           `json:"email"`
	Name             *string          `json:"name"`
	DisplayName      *string          `json:"display_name"`
	AvatarURL        *string          `json:"avatar_url"`
	CreatedAt        string           `json:"created_at"`
	IsPro            bool             `json:"is_pro"`
	IsAdmin          bool             `json:"is_admin"`
	LeaderboardOptIn bool             `json:"leaderboard_opt_in"`
	PermissionPolicy PermissionPolicy `json:"permission_policy"`
	CurrentSessionID *string          `json:"current_session_id"`
	MaxActiveDevices int              `json:"max_active_devices"`
}

func BuildUserResponse(user User, sessionID *string, maxActiveDevices int, policy PermissionPolicy) UserResponse {
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
		IsAdmin:          user.IsAdmin,
		LeaderboardOptIn: user.LeaderboardOptIn,
		PermissionPolicy: policy,
		CurrentSessionID: sessionID,
		MaxActiveDevices: maxActiveDevices,
	}
}
