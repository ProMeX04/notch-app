package focus

import (
	"strings"
)

type EventType string

const (
	SyncSucceeded             EventType = "focus.sync_succeeded"
	SyncRejected              EventType = "focus.sync_rejected"
	SyncFailed                EventType = "focus.sync_failed"
	LeaderboardProfileUpdated EventType = "focus.leaderboard_profile_updated"
	LeaderboardProfileRejected EventType = "focus.leaderboard_profile_rejected"
	LeaderboardProfileFailed  EventType = "focus.leaderboard_profile_failed"
)

type RejectedReason string

const (
	ReasonUnauthorized   RejectedReason = "unauthorized"
	ReasonInvalidPayload RejectedReason = "invalid_payload"
	ReasonDeviceNotBound RejectedReason = "device_not_bound"
)

// FocusRejectedMetadata builds minimal sanitizing metadata for rejected events.
func FocusRejectedMetadata(reason RejectedReason) map[string]any {
	return map[string]any{
		"reason": string(reason),
	}
}

// FocusSyncSucceededMetadata builds metadata for succeeded sync events.
func FocusSyncSucceededMetadata(entryCount, syncedCount int) map[string]any {
	return map[string]any{
		"entryCount":  entryCount,
		"syncedCount": syncedCount,
	}
}

// FocusSyncFailedMetadata builds metadata for failed sync events.
func FocusSyncFailedMetadata(entryCount int, err error) map[string]any {
	name := "UnknownError"
	if err != nil {
		name = errorName(err)
	}
	return map[string]any{
		"entryCount": entryCount,
		"errorName":  name,
	}
}

// LeaderboardProfileUpdatedMetadata builds metadata for updated profile events.
func LeaderboardProfileUpdatedMetadata(optIn bool, displayName *string) map[string]any {
	hasDisplayName := false
	if displayName != nil && strings.TrimSpace(*displayName) != "" {
		hasDisplayName = true
	}
	return map[string]any{
		"leaderboardOptIn":      optIn,
		"displayNameConfigured": hasDisplayName,
	}
}

// LeaderboardProfileFailedMetadata builds metadata for failed profile events.
func LeaderboardProfileFailedMetadata(err error) map[string]any {
	name := "UnknownError"
	if err != nil {
		name = errorName(err)
	}
	return map[string]any{
		"errorName": name,
	}
}

func errorName(err error) string {
	msg := err.Error()
	// Derive clean error class name from message if not concrete type
	switch {
	case strings.Contains(msg, "unauthorized"):
		return "UnauthorizedError"
	case strings.Contains(msg, "invalid"):
		return "ValidationError"
	default:
		return "DatabaseError"
	}
}