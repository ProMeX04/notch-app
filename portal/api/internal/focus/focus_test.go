package focus

import (
	"testing"
	"time"

	"notch/portal/api/internal/focus/timeutil"
)

func TestTimeutilStartOfUTCDay(t *testing.T) {
	reference := time.Date(2026, 5, 30, 15, 34, 12, 100, time.UTC)
	got := timeutil.StartOfUTCDay(reference)
	want := time.Date(2026, 5, 30, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("StartOfUTCDay() = %v, want %v", got, want)
	}
}

func TestTimeutilStartOfUTCWeek(t *testing.T) {
	// Thursday May 28, 2026 -> Monday May 25, 2026
	thursday := time.Date(2026, 5, 28, 12, 0, 0, 0, time.UTC)
	got := timeutil.StartOfUTCWeek(thursday)
	want := time.Date(2026, 5, 25, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("StartOfUTCWeek(thursday) = %v, want %v", got, want)
	}

	// Sunday May 31, 2026 -> Monday May 25, 2026
	sunday := time.Date(2026, 5, 31, 12, 0, 0, 0, time.UTC)
	got = timeutil.StartOfUTCWeek(sunday)
	if !got.Equal(want) {
		t.Fatalf("StartOfUTCWeek(sunday) = %v, want %v", got, want)
	}

	// Monday June 1, 2026 -> Monday June 1, 2026
	monday := time.Date(2026, 6, 1, 2, 0, 0, 0, time.UTC)
	got = timeutil.StartOfUTCWeek(monday)
	wantMonday := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
	if !got.Equal(wantMonday) {
		t.Fatalf("StartOfUTCWeek(monday) = %v, want %v", got, wantMonday)
	}
}

func TestValidateFocusSyncRequest(t *testing.T) {
	body := map[string]any{
		"schema_version": float64(2),
		"entries": []any{
			map[string]any{
				"date":          "2026-05-30",
				"focus_seconds": float64(3600),
				"session_count": float64(2),
			},
		},
	}

	entries, err := ValidateFocusSyncRequest(body)
	if err != nil {
		t.Fatalf("unexpected validation error: %v", err)
	}
	if len(entries) != 1 || entries[0].Date != "2026-05-30" || entries[0].FocusSeconds != 3600 || entries[0].SessionCount != 2 {
		t.Fatalf("unexpected validated entries: %#v", entries)
	}

	// Verify rejection of client device_id
	badBody := map[string]any{
		"schema_version": float64(2),
		"entries": []any{
			map[string]any{
				"date":          "2026-05-30",
				"device_id":     "some_client_id",
				"focus_seconds": float64(3600),
				"session_count": float64(2),
			},
		},
	}
	if _, err := ValidateFocusSyncRequest(badBody); err == nil {
		t.Fatal("expected validation to reject client-provided device_id")
	}
}

func TestNormalizeDisplayName(t *testing.T) {
	if got := NormalizeDisplayName("  My   Name  "); got == nil || *got != "My Name" {
		t.Fatalf("NormalizeDisplayName() = %v, want My Name", got)
	}
	if got := NormalizeDisplayName("   "); got != nil {
		t.Fatalf("expected nil for empty displayName, got %v", got)
	}
}
