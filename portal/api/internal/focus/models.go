package focus

import "time"

const (
	SchemaVersion          = 2
	MaxBatchSize           = 120
	MaxSecondsPerDay       = 24 * 60 * 60
	MaxSessionCountPerDay  = 500
	PublicLeaderboardLimit = 50
)

// FocusSyncInput represents a single daily focus entry from the client.
type FocusSyncInput struct {
	Date         string `json:"date"`
	FocusSeconds int    `json:"focus_seconds"`
	SessionCount int    `json:"session_count"`
}

// FocusSyncRequest is the request body for POST /api/focus/sync.
type FocusSyncRequest struct {
	SchemaVersion int              `json:"schema_version"`
	Entries       []FocusSyncInput `json:"entries"`
}

// FocusSyncResult is the response for POST /api/focus/sync.
type FocusSyncResult struct {
	Synced int `json:"synced"`
}

// FocusSummary is the focus summary for a user.
type FocusSummary struct {
	Week struct {
		FocusSeconds int    `json:"focus_seconds"`
		SessionCount int    `json:"session_count"`
		StartsAt     string `json:"starts_at"`
	} `json:"week"`
	AllTime struct {
		FocusSeconds int `json:"focus_seconds"`
		SessionCount int `json:"session_count"`
	} `json:"all_time"`
}

// UserFocusProfile is the response for GET /api/focus/me and PATCH /api/focus/profile.
type UserFocusProfile struct {
	User struct {
		ID               string `json:"id"`
		DisplayName      string `json:"display_name"`
		LeaderboardOptIn bool   `json:"leaderboard_opt_in"`
	} `json:"user"`
}

// LeaderboardEntry is a single row in the leaderboard.
type LeaderboardEntry struct {
	Rank         int    `json:"rank"`
	UserID       string `json:"user_id"`
	DisplayName  string `json:"display_name"`
	FocusSeconds int    `json:"focus_seconds"`
	SessionCount int    `json:"session_count"`
}

// LeaderboardResponse is the response for GET /api/focus/leaderboard.
type LeaderboardResponse struct {
	Window      string             `json:"window"`
	Leaderboard []LeaderboardEntry `json:"leaderboard"`
}

// ProfileUpdateRequest is the request body for PATCH /api/focus/profile.
type ProfileUpdateRequest struct {
	DisplayName      *string `json:"display_name"`
	LeaderboardOptIn *bool   `json:"leaderboard_opt_in"`
}

// ProfileUpdateResponse mirrors UserFocusProfile.
type ProfileUpdateResponse = UserFocusProfile

// FocusDailyStat represents a daily aggregated focus stat row.
type FocusDailyStat struct {
	ID           string
	UserID       string
	Date         time.Time
	DeviceID     string
	FocusSeconds int
	SessionCount int
	CreatedAt    time.Time
	UpdatedAt    time.Time
}
