package focus

import (
	"fmt"
	"regexp"
	"strings"

	"notch/portal/api/internal/focus/timeutil"
)

var dateKeyRegex = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

// ValidateFocusSyncRequest validates the incoming focus sync request.
func ValidateFocusSyncRequest(body map[string]any) ([]FocusSyncInput, error) {
	if body == nil {
		return nil, fmt.Errorf("expected a JSON object")
	}

	schemaVersion, ok := body["schema_version"].(float64)
	if !ok || int(schemaVersion) != SchemaVersion {
		return nil, fmt.Errorf("unsupported focus sync schema version")
	}

	entriesRaw, ok := body["entries"].([]any)
	if !ok {
		return nil, fmt.Errorf("expected an entries array")
	}
	if len(entriesRaw) == 0 {
		return []FocusSyncInput{}, nil
	}
	if len(entriesRaw) > MaxBatchSize {
		return nil, fmt.Errorf("a sync batch may contain at most %d entries", MaxBatchSize)
	}

	entries := make([]FocusSyncInput, 0, len(entriesRaw))
	for i, entryRaw := range entriesRaw {
		entry, ok := entryRaw.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("entry %d is invalid", i+1)
		}

		dateStr, ok := entry["date"].(string)
		if !ok || !isValidUTCDateKey(dateStr) {
			return nil, fmt.Errorf("entry %d has an invalid date", i+1)
		}

		if _, hasDeviceID := entry["device_id"]; hasDeviceID {
			return nil, fmt.Errorf("entry %d must not provide device_id", i+1)
		}

		focusSeconds, ok := toInt(entry["focus_seconds"])
		if !ok || focusSeconds < 0 || focusSeconds > MaxSecondsPerDay {
			return nil, fmt.Errorf("entry %d has invalid focus_seconds", i+1)
		}

		sessionCount, ok := toInt(entry["session_count"])
		if !ok || sessionCount < 0 || sessionCount > MaxSessionCountPerDay {
			return nil, fmt.Errorf("entry %d has invalid session_count", i+1)
		}

		entries = append(entries, FocusSyncInput{
			Date:         dateStr,
			FocusSeconds: focusSeconds,
			SessionCount: sessionCount,
		})
	}

	return entries, nil
}

func isValidUTCDateKey(dateKey string) bool {
	if !dateKeyRegex.MatchString(dateKey) {
		return false
	}
	parsed := timeutil.FocusDateFromKey(dateKey)
	return !parsed.IsZero() && parsed.Format("2006-01-02") == dateKey
}

// toInt converts an interface{} to int. Returns false if not a number.
func toInt(v any) (int, bool) {
	switch n := v.(type) {
	case float64:
		if n != float64(int(n)) {
			return 0, false
		}
		return int(n), true
	case int:
		return n, true
	case int64:
		return int(n), true
	default:
		return 0, false
	}
}

// NormalizeDisplayName trims whitespace, collapses internal spaces, and returns nil for empty strings.
func NormalizeDisplayName(raw string) *string {
	normalized := strings.TrimSpace(raw)
	normalized = strings.Join(strings.Fields(normalized), " ")
	if normalized == "" {
		return nil
	}
	if len(normalized) > 80 {
		normalized = normalized[:80]
	}
	return &normalized
}