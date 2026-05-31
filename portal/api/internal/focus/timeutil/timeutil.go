package timeutil

import "time"

// StartOfUTCDay returns midnight UTC for the given date.
func StartOfUTCDay(t time.Time) time.Time {
	return time.Date(t.UTC().Year(), t.UTC().Month(), t.UTC().Day(), 0, 0, 0, 0, time.UTC)
}

// StartOfUTCWeek returns the Monday of the week containing t (ISO week, Monday = 1).
// If t falls on Sunday, it returns the Monday of the previous week.
func StartOfUTCWeek(t time.Time) time.Time {
	dayStart := StartOfUTCDay(t)
	weekday := int(dayStart.Weekday()) // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
	// Monday = 1, so offset to Monday is: if Sunday (0) -> -6, else 1-weekday
	if weekday == 0 {
		weekday = 7 // treat Sunday as end of week, move back 6 days
	}
	offset := 1 - weekday
	return dayStart.AddDate(0, 0, offset)
}

// ParseFocusWindow returns "week" for any value other than "all".
func ParseFocusWindow(raw string) string {
	if raw == "all" {
		return "all"
	}
	return "week"
}

// FocusDateFromKey parses a "2006-01-02" date key into a UTC time at midnight.
func FocusDateFromKey(dateKey string) time.Time {
	t, err := time.Parse("2006-01-02", dateKey)
	if err != nil {
		return time.Time{}
	}
	return t.UTC()
}