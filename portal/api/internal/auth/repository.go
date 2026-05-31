package auth

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PgxSessionRepository struct {
	db *pgxpool.Pool
}

func NewPgxSessionRepository(db *pgxpool.Pool) *PgxSessionRepository {
	return &PgxSessionRepository{db: db}
}

func (r *PgxSessionRepository) FindSessionByID(ctx context.Context, sessionID string) (*Session, error) {
	return r.findSession(ctx, `s."id" = $1`, sessionID)
}

func (r *PgxSessionRepository) FindSessionByRefreshTokenHash(ctx context.Context, tokenHash string) (*Session, error) {
	return r.findSession(ctx, `s."tokenHash" = $1`, tokenHash)
}

func (r *PgxSessionRepository) RotateSession(ctx context.Context, sessionID string, accessTokenHash string, refreshTokenHash string, accessExpiresAt time.Time, refreshExpiresAt time.Time, device NormalizedDevice, trustedAt *time.Time, now time.Time) (RotatedSession, error) {
	var rotated RotatedSession
	if r == nil || r.db == nil {
		return rotated, pgx.ErrNoRows
	}
	err := r.db.QueryRow(ctx, `
		UPDATE "AuthSession"
		SET
			"tokenHash" = $2,
			"accessTokenHash" = $3,
			"expiresAt" = $4,
			"accessExpiresAt" = $5,
			"lastSeenAt" = $6,
			"trustedAt" = $7,
			"deviceId" = $8,
			"deviceName" = $9,
			"platform" = $10,
			"revokedAt" = NULL,
			"revokedReason" = NULL
		WHERE "id" = $1
		RETURNING "id", "deviceId", "deviceName", "platform", "trustedAt"
	`, sessionID, refreshTokenHash, accessTokenHash, refreshExpiresAt, accessExpiresAt, now, trustedAt, device.DeviceID, device.DeviceName, device.Platform).
		Scan(&rotated.ID, &rotated.DeviceID, &rotated.DeviceName, &rotated.Platform, &rotated.TrustedAt)
	return rotated, err
}

func (r *PgxSessionRepository) UpdateLastSeen(ctx context.Context, sessionID string, seenAt time.Time) error {
	if r == nil || r.db == nil {
		return nil
	}
	_, err := r.db.Exec(ctx, `UPDATE "AuthSession" SET "lastSeenAt" = $2 WHERE "id" = $1`, sessionID, seenAt)
	return err
}

func (r *PgxSessionRepository) MarkSessionExpired(ctx context.Context, sessionID string, expiredAt time.Time) error {
	if r == nil || r.db == nil {
		return nil
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "AuthSession"
		SET "revokedAt" = $2, "revokedReason" = 'expired'
		WHERE "id" = $1 AND "revokedAt" IS NULL
	`, sessionID, expiredAt)
	return err
}

func (r *PgxSessionRepository) findSession(ctx context.Context, where string, arg string) (*Session, error) {
	if r == nil || r.db == nil {
		return nil, nil
	}
	row := r.db.QueryRow(ctx, sessionSelectSQL(where), arg)
	return scanSession(row)
}

type sessionScanner interface {
	Scan(dest ...any) error
}

func scanSession(row sessionScanner) (*Session, error) {
	var session Session
	var user User
	err := row.Scan(
		&session.ID,
		&session.TokenHash,
		&session.AccessTokenHash,
		&session.DeviceID,
		&session.DeviceName,
		&session.Platform,
		&session.ExpiresAt,
		&session.AccessExpiresAt,
		&session.CreatedAt,
		&session.LastSeenAt,
		&session.TrustedAt,
		&session.RevokedAt,
		&session.RevokedReason,
		&session.UserID,
		&user.ID,
		&user.Email,
		&user.Name,
		&user.DisplayName,
		&user.AvatarURL,
		&user.CreatedAt,
		&user.IsPro,
		&user.IsAdmin,
		&user.LeaderboardOptIn,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	session.User = user
	return &session, nil
}

func sessionSelectSQL(where string) string {
	return `
		SELECT
			s."id", s."tokenHash", s."accessTokenHash", s."deviceId", s."deviceName", s."platform",
			s."expiresAt", s."accessExpiresAt", s."createdAt", s."lastSeenAt", s."trustedAt",
			s."revokedAt", s."revokedReason", s."userId",
			u."id", u."email", u."name", u."displayName", u."avatarUrl", u."createdAt",
			u."isPro", u."isAdmin", u."leaderboardOptIn"
		FROM "AuthSession" s
		JOIN "User" u ON u."id" = s."userId"
		WHERE ` + where + `
		LIMIT 1
	`
}

func (r *PgxSessionRepository) FindUserByEmail(ctx context.Context, email string) (*User, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	var u User
	var emailVal *string
	var nameVal *string
	err := r.db.QueryRow(ctx, `
		SELECT "id", "email", "name", "displayName", "avatarUrl", "password", "createdAt", "isPro", "isAdmin", "leaderboardOptIn"
		FROM "User"
		WHERE LOWER("email") = LOWER($1)
		LIMIT 1
	`, email).Scan(&u.ID, &emailVal, &nameVal, &u.DisplayName, &u.AvatarURL, &u.Password, &u.CreatedAt, &u.IsPro, &u.IsAdmin, &u.LeaderboardOptIn)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	u.Email = emailVal
	u.Name = nameVal
	return &u, nil
}

func (r *PgxSessionRepository) CreateUser(ctx context.Context, id string, email string, name string, hashedPassword string, now time.Time) (*User, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO "User" ("id", "email", "name", "password", "createdAt", "updatedAt")
		VALUES ($1, $2, $3, $4, $5, $6)
	`, id, email, name, hashedPassword, now, now)
	if err != nil {
		return nil, err
	}
	return r.FindUserByEmail(ctx, email)
}

func (r *PgxSessionRepository) CreateSession(ctx context.Context, sessionID string, userID string, tokenHash string, accessTokenHash *string, device NormalizedDevice, expiresAt time.Time, accessExpiresAt *time.Time, trustedAt *time.Time, now time.Time) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO "AuthSession" (
			"id", "tokenHash", "accessTokenHash", "deviceId", "deviceName", "platform",
			"expiresAt", "accessExpiresAt", "createdAt", "lastSeenAt", "trustedAt", "updatedAt", "userId"
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13
		)
	`, sessionID, tokenHash, accessTokenHash, device.DeviceID, device.DeviceName, device.Platform, expiresAt, accessExpiresAt, now, now, trustedAt, now, userID)
	return err
}
