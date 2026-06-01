package focus

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PgxRepository struct {
	db *pgxpool.Pool
}

func NewPgxRepository(db *pgxpool.Pool) *PgxRepository {
	return &PgxRepository{db: db}
}

func (r *PgxRepository) SyncFocusDailyStats(ctx context.Context, userID string, entries []FocusSyncInput, deviceID string) (FocusSyncResult, error) {
	if len(entries) == 0 {
		return FocusSyncResult{Synced: 0}, nil
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return FocusSyncResult{}, err
	}
	defer tx.Rollback(ctx)

	// In development / dev-break mode, we reject old schema versions directly (handled in validators)
	// We upsert each entry one-by-one or in batch using PostgreSQL ON CONFLICT GREATEST merge.
	// This matches the atomic monotonic merge requirement.
	for _, entry := range entries {
		t, err := time.Parse("2006-01-02", entry.Date)
		if err != nil {
			return FocusSyncResult{}, err
		}
		dateUTC := t.UTC()

		_, err = tx.Exec(ctx, `
			INSERT INTO "FocusDailyStat" (
				"id", "userId", "date", "deviceId", "focusSeconds", "sessionCount", "createdAt", "updatedAt"
			) VALUES (
				gen_random_uuid()::text, $1, $2, $3, $4, $5, NOW(), NOW()
			)
			ON CONFLICT ("userId", "date", "deviceId")
			DO UPDATE SET
				"focusSeconds" = GREATEST("FocusDailyStat"."focusSeconds", EXCLUDED."focusSeconds"),
				"sessionCount" = GREATEST("FocusDailyStat"."sessionCount", EXCLUDED."sessionCount"),
				"updatedAt" = NOW()
		`, userID, dateUTC, deviceID, entry.FocusSeconds, entry.SessionCount)
		if err != nil {
			return FocusSyncResult{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return FocusSyncResult{}, err
	}

	return FocusSyncResult{Synced: len(entries)}, nil
}

func (r *PgxRepository) ReadFocusSummary(ctx context.Context, userID string, weekStart time.Time) (FocusSummary, error) {
	var summary FocusSummary
	summary.Week.StartsAt = weekStart.Format("2006-01-02")

	// 1. All-time sum
	var allTimeSeconds, allTimeSessions *int
	err := r.db.QueryRow(ctx, `
		SELECT SUM("focusSeconds"), SUM("sessionCount")
		FROM "FocusDailyStat"
		WHERE "userId" = $1
	`, userID).Scan(&allTimeSeconds, &allTimeSessions)
	if err != nil && err != pgx.ErrNoRows {
		return summary, err
	}
	if allTimeSeconds != nil {
		summary.AllTime.FocusSeconds = *allTimeSeconds
	}
	if allTimeSessions != nil {
		summary.AllTime.SessionCount = *allTimeSessions
	}

	// 2. Week sum
	var weekSeconds, weekSessions *int
	err = r.db.QueryRow(ctx, `
		SELECT SUM("focusSeconds"), SUM("sessionCount")
		FROM "FocusDailyStat"
		WHERE "userId" = $1 AND "date" >= $2
	`, userID, weekStart).Scan(&weekSeconds, &weekSessions)
	if err != nil && err != pgx.ErrNoRows {
		return summary, err
	}
	if weekSeconds != nil {
		summary.Week.FocusSeconds = *weekSeconds
	}
	if weekSessions != nil {
		summary.Week.SessionCount = *weekSessions
	}

	return summary, nil
}

func (r *PgxRepository) ReadFocusLeaderboard(ctx context.Context, window string, weekStart time.Time, limit int) ([]LeaderboardEntry, error) {
	var rows pgx.Rows
	var err error

	if window == "week" {
		rows, err = r.db.Query(ctx, `
			SELECT
				s."userId",
				COALESCE(u."displayName", u."name", 'Notch user'),
				COALESCE(u."email", ''),
				SUM(s."focusSeconds") as total_seconds,
				SUM(s."sessionCount") as total_sessions,
				u."leaderboardOptIn",
				u."avatarUrl"
			FROM "FocusDailyStat" s
			JOIN "User" u ON u."id" = s."userId"
			WHERE s."date" >= $1
			GROUP BY s."userId", u."displayName", u."name", u."email", u."leaderboardOptIn", u."avatarUrl"
			ORDER BY total_seconds DESC
			LIMIT $2
		`, weekStart, limit)
	} else {
		rows, err = r.db.Query(ctx, `
			SELECT
				s."userId",
				COALESCE(u."displayName", u."name", 'Notch user'),
				COALESCE(u."email", ''),
				SUM(s."focusSeconds") as total_seconds,
				SUM(s."sessionCount") as total_sessions,
				u."leaderboardOptIn",
				u."avatarUrl"
			FROM "FocusDailyStat" s
			JOIN "User" u ON u."id" = s."userId"
			GROUP BY s."userId", u."displayName", u."name", u."email", u."leaderboardOptIn", u."avatarUrl"
			ORDER BY total_seconds DESC
			LIMIT $1
		`, limit)
	}

	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var entries []LeaderboardEntry
	rank := 1
	for rows.Next() {
		var entry LeaderboardEntry
		var email string
		var displayName *string
		var optIn bool
		var avatarURL *string
		err := rows.Scan(&entry.UserID, &displayName, &email, &entry.FocusSeconds, &entry.SessionCount, &optIn, &avatarURL)
		if err != nil {
			return nil, err
		}
		entry.Rank = rank
		if optIn {
			entry.DisplayName = resolvePublicName(displayName, email)
			entry.AvatarURL = avatarURL
		} else {
			entry.DisplayName = "Ẩn danh"
			entry.AvatarURL = nil
		}
		entries = append(entries, entry)
		rank++
	}

	return entries, nil
}

func (r *PgxRepository) GetUserForLeaderboard(ctx context.Context, userID string) (string, bool, error) {
	var displayName *string
	var optIn bool
	var name *string
	err := r.db.QueryRow(ctx, `
		SELECT "displayName", "leaderboardOptIn", "name"
		FROM "User"
		WHERE "id" = $1
	`, userID).Scan(&displayName, &optIn, &name)
	if err != nil {
		return "", false, err
	}
	resolved := ""
	if displayName != nil {
		resolved = *displayName
	} else if name != nil {
		resolved = *name
	}
	return resolved, optIn, nil
}

func (r *PgxRepository) UpdateLeaderboardProfile(ctx context.Context, userID string, displayName *string, optIn bool) (UserFocusProfile, error) {
	var profile UserFocusProfile
	profile.User.ID = userID

	var scanDisp *string
	var scanName *string
	err := r.db.QueryRow(ctx, `
		UPDATE "User"
		SET "displayName" = $2, "leaderboardOptIn" = $3, "updatedAt" = NOW()
		WHERE "id" = $1
		RETURNING "displayName", "leaderboardOptIn", "name"
	`, userID, displayName, optIn).Scan(&scanDisp, &profile.User.LeaderboardOptIn, &scanName)
	if err != nil {
		return profile, err
	}

	if scanDisp != nil && *scanDisp != "" {
		profile.User.DisplayName = *scanDisp
	} else if scanName != nil {
		profile.User.DisplayName = *scanName
	}

	return profile, nil
}

func resolvePublicName(displayName *string, email string) string {
	if displayName != nil && strings.TrimSpace(*displayName) != "" {
		return strings.TrimSpace(*displayName)
	}
	if email == "" {
		return "Notch user"
	}
	parts := strings.Split(email, "@")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "Notch user"
	}
	local := parts[0]
	visibleLen := len(local)
	if visibleLen > 2 {
		visibleLen = 2
	}
	visible := local[:visibleLen]
	mask := "*"
	if len(local) > 2 {
		mask = "***"
	}
	return fmt.Sprintf("%s%s@%s", visible, mask, parts[1])
}

func (r *PgxRepository) ReadUserWeeklyRankAndStreak(ctx context.Context, userID string, weekStart time.Time) (int, int, error) {
	// 1. Get weekly rank
	var rank int
	err := r.db.QueryRow(ctx, `
		WITH WeeklyRanking AS (
			SELECT
				s."userId",
				ROW_NUMBER() OVER (ORDER BY SUM(s."focusSeconds") DESC) as rank
			FROM "FocusDailyStat" s
			JOIN "User" u ON u."id" = s."userId"
			WHERE s."date" >= $1
			GROUP BY s."userId"
		)
		SELECT rank FROM WeeklyRanking WHERE "userId" = $2;
	`, weekStart, userID).Scan(&rank)
	if err != nil && err != pgx.ErrNoRows {
		return 0, 0, err
	}

	// 2. Get active focus streak in days
	var streak int
	err = r.db.QueryRow(ctx, `
		WITH DistinctDays AS (
			SELECT DISTINCT date_trunc('day', "date")::date as active_date
			FROM "FocusDailyStat"
			WHERE "userId" = $1 AND "focusSeconds" > 0
		),
		NumberedDays AS (
			SELECT active_date, active_date - ROW_NUMBER() OVER (ORDER BY active_date)::int as grp
			FROM DistinctDays
		),
		Runs AS (
			SELECT grp, COUNT(*) as run_length, MAX(active_date) as last_active_date
			FROM NumberedDays
			GROUP BY grp
		)
		SELECT COALESCE(MAX(run_length), 0)
		FROM Runs
		WHERE last_active_date >= (CURRENT_DATE - INTERVAL '1 day')::date;
	`, userID).Scan(&streak)
	if err != nil && err != pgx.ErrNoRows {
		return rank, 0, err
	}

	return rank, streak, nil
}
