package focus

import (
	"context"
	"time"
)

// Repository defines the persistence interface for Focus data.
type Repository interface {
	// SyncFocusDailyStats performs a transactional monotonic upsert of multiple daily stats for a user and device.
	SyncFocusDailyStats(ctx context.Context, userID string, entries []FocusSyncInput, deviceID string) (FocusSyncResult, error)
	// ReadFocusSummary aggregates all-time and current week focus stats for a user.
	ReadFocusSummary(ctx context.Context, userID string, weekStart time.Time) (FocusSummary, error)
	// ReadFocusLeaderboard returns the top entries for the leaderboard in the given window (week starting Monday or all-time).
	ReadFocusLeaderboard(ctx context.Context, window string, weekStart time.Time, limit int) ([]LeaderboardEntry, error)
	// GetUserForLeaderboard retrieves user info and checks leaderboard opt-in.
	GetUserForLeaderboard(ctx context.Context, userID string) (string, bool, error)
	// UpdateLeaderboardProfile updates a user's leaderboard settings (opt-in and display name).
	UpdateLeaderboardProfile(ctx context.Context, userID string, displayName *string, optIn bool) (UserFocusProfile, error)
}
