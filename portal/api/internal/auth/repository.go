package auth

import (
	"context"
	"errors"
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
	session, err := scanSession(row)
	return session, err
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

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Check if there is any paid payment transaction for this guest email
	var hasPaidGuestTx bool
	var paidTxID string
	err = tx.QueryRow(ctx, `
		SELECT "id"
		FROM "PaymentTransaction"
		WHERE LOWER("guestEmail") = LOWER($1) AND "status" = 'paid'
		LIMIT 1
	`, email).Scan(&paidTxID)
	if err == nil {
		hasPaidGuestTx = true
	} else if err != pgx.ErrNoRows {
		return nil, err
	}

	isPro := false
	if hasPaidGuestTx {
		isPro = true
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO "User" ("id", "email", "name", "password", "createdAt", "updatedAt", "isPro")
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, id, email, name, hashedPassword, now, now, isPro)
	if err != nil {
		return nil, err
	}

	if hasPaidGuestTx {
		// Update all payment transactions matching guest email to link to this user
		_, err = tx.Exec(ctx, `
			UPDATE "PaymentTransaction"
			SET "userId" = $1, "updatedAt" = NOW()
			WHERE LOWER("guestEmail") = LOWER($2)
		`, id, email)
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
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

func (r *PgxSessionRepository) UpdateUserPasswordAndName(ctx context.Context, id string, name string, hashedPassword string, now time.Time) (*User, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "User"
		SET "password" = $2, "name" = CASE WHEN TRIM($3) <> '' THEN $3 ELSE "name" END, "updatedAt" = $4
		WHERE "id" = $1
	`, id, hashedPassword, name, now)
	if err != nil {
		return nil, err
	}
	return r.FindUserByID(ctx, id)
}

func (r *PgxSessionRepository) FindUserByID(ctx context.Context, id string) (*User, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	var u User
	var emailVal *string
	var nameVal *string
	err := r.db.QueryRow(ctx, `
		SELECT "id", "email", "name", "displayName", "avatarUrl", "password", "createdAt", "isPro", "isAdmin", "leaderboardOptIn"
		FROM "User"
		WHERE "id" = $1
		LIMIT 1
	`, id).Scan(&u.ID, &emailVal, &nameVal, &u.DisplayName, &u.AvatarURL, &u.Password, &u.CreatedAt, &u.IsPro, &u.IsAdmin, &u.LeaderboardOptIn)
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

func (r *PgxSessionRepository) RevokeSession(ctx context.Context, sessionID string, revokedAt time.Time, reason string) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "AuthSession"
		SET "revokedAt" = $2, "revokedReason" = $3
		WHERE "id" = $1 AND "revokedAt" IS NULL
	`, sessionID, revokedAt, reason)
	return err
}

func (r *PgxSessionRepository) FindActiveSessionsByUserID(ctx context.Context, userID string) ([]*Session, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	rows, err := r.db.Query(ctx, `
		SELECT
			s."id", s."tokenHash", s."accessTokenHash", s."deviceId", s."deviceName", s."platform",
			s."expiresAt", s."accessExpiresAt", s."createdAt", s."lastSeenAt", s."trustedAt",
			s."revokedAt", s."revokedReason", s."userId",
			u."id", u."email", u."name", u."displayName", u."avatarUrl", u."createdAt",
			u."isPro", u."isAdmin", u."leaderboardOptIn"
		FROM "AuthSession" s
		JOIN "User" u ON u."id" = s."userId"
		WHERE s."userId" = $1 AND s."revokedAt" IS NULL AND s."expiresAt" > $2
		ORDER BY s."lastSeenAt" DESC
	`, userID, time.Now())
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sessions []*Session
	for rows.Next() {
		var s Session
		var u User
		var emailVal *string
		var nameVal *string
		err := rows.Scan(
			&s.ID,
			&s.TokenHash,
			&s.AccessTokenHash,
			&s.DeviceID,
			&s.DeviceName,
			&s.Platform,
			&s.ExpiresAt,
			&s.AccessExpiresAt,
			&s.CreatedAt,
			&s.LastSeenAt,
			&s.TrustedAt,
			&s.RevokedAt,
			&s.RevokedReason,
			&s.UserID,
			&u.ID,
			&emailVal,
			&nameVal,
			&u.DisplayName,
			&u.AvatarURL,
			&u.CreatedAt,
			&u.IsPro,
			&u.IsAdmin,
			&u.LeaderboardOptIn,
		)
		if err != nil {
			return nil, err
		}
		u.Email = emailVal
		u.Name = nameVal
		s.User = u
		sessions = append(sessions, &s)
	}
	return sessions, nil
}

func (r *PgxSessionRepository) FindAllSessionsByUserID(ctx context.Context, userID string) ([]*Session, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	rows, err := r.db.Query(ctx, `
		SELECT
			s."id", s."tokenHash", s."accessTokenHash", s."deviceId", s."deviceName", s."platform",
			s."expiresAt", s."accessExpiresAt", s."createdAt", s."lastSeenAt", s."trustedAt",
			s."revokedAt", s."revokedReason", s."userId",
			u."id", u."email", u."name", u."displayName", u."avatarUrl", u."createdAt",
			u."isPro", u."isAdmin", u."leaderboardOptIn"
		FROM "AuthSession" s
		JOIN "User" u ON u."id" = s."userId"
		WHERE s."userId" = $1
		ORDER BY s."lastSeenAt" DESC, s."createdAt" DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sessions []*Session
	for rows.Next() {
		var s Session
		var u User
		var emailVal *string
		var nameVal *string
		err := rows.Scan(
			&s.ID,
			&s.TokenHash,
			&s.AccessTokenHash,
			&s.DeviceID,
			&s.DeviceName,
			&s.Platform,
			&s.ExpiresAt,
			&s.AccessExpiresAt,
			&s.CreatedAt,
			&s.LastSeenAt,
			&s.TrustedAt,
			&s.RevokedAt,
			&s.RevokedReason,
			&s.UserID,
			&u.ID,
			&emailVal,
			&nameVal,
			&u.DisplayName,
			&u.AvatarURL,
			&u.CreatedAt,
			&u.IsPro,
			&u.IsAdmin,
			&u.LeaderboardOptIn,
		)
		if err != nil {
			return nil, err
		}
		u.Email = emailVal
		u.Name = nameVal
		s.User = u
		sessions = append(sessions, &s)
	}
	return sessions, nil
}

func (r *PgxSessionRepository) RevokeSessionByID(ctx context.Context, sessionID string, userID string) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "AuthSession"
		SET "revokedAt" = NOW(), "revokedReason" = 'user_revoked'
		WHERE "id" = $1 AND "userId" = $2 AND "revokedAt" IS NULL
	`, sessionID, userID)
	return err
}

func (r *PgxSessionRepository) CreateGoogleDriveAuthHandoff(ctx context.Context, id string, tokenHash string, codeChallenge string, accessToken string, refreshToken *string, expiresIn *int, expiresAt time.Time, createdAt time.Time) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO "GoogleDriveAuthHandoff" (
			"id", "tokenHash", "codeChallenge", "accessToken", "refreshToken", "expiresIn", "expiresAt", "createdAt"
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8
		)
	`, id, tokenHash, codeChallenge, accessToken, refreshToken, expiresIn, expiresAt, createdAt)
	return err
}

func (r *PgxSessionRepository) UpdateUserAvatar(ctx context.Context, id string, avatarURL *string) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `UPDATE "User" SET "avatarUrl" = $2, "updatedAt" = NOW() WHERE "id" = $1`, id, avatarURL)
	return err
}

func (r *PgxSessionRepository) SetTrustedDevice(ctx context.Context, userID string, deviceID string, trusted bool) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	var trustedAt *time.Time
	if trusted {
		now := time.Now()
		trustedAt = &now
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "AuthSession"
		SET "trustedAt" = $3, "updatedAt" = NOW()
		WHERE "userId" = $1 AND "deviceId" = $2 AND "revokedAt" IS NULL
	`, userID, deviceID, trustedAt)
	return err
}

func (r *PgxSessionRepository) RevokeDeviceSessions(ctx context.Context, userID string, deviceID string, exceptSessionID string) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "AuthSession"
		SET "revokedAt" = NOW(), "revokedReason" = 'manual_revoke', "updatedAt" = NOW()
		WHERE "userId" = $1 AND "deviceId" = $2 AND "id" != $3 AND "revokedAt" IS NULL
	`, userID, deviceID, exceptSessionID)
	return err
}

func (r *PgxSessionRepository) CreateOAuthAuthorizationCode(ctx context.Context, code *OAuthAuthorizationCode) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO "OAuthAuthorizationCode" (
			"id", "codeHash", "clientId", "redirectUri", "codeChallenge", "codeChallengeMethod", "expiresAt", "createdAt", "userId"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`, code.ID, code.CodeHash, code.ClientID, code.RedirectURI, code.CodeChallenge, code.CodeChallengeMethod, code.ExpiresAt, code.CreatedAt, code.UserID)
	return err
}

func (r *PgxSessionRepository) FindOAuthAuthorizationCode(ctx context.Context, codeHash string) (*OAuthAuthorizationCode, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	var c OAuthAuthorizationCode
	var u User
	var emailVal *string
	var nameVal *string
	var consumedVal *time.Time

	err := r.db.QueryRow(ctx, `
		SELECT 
			c."id", c."codeHash", c."clientId", c."redirectUri", c."codeChallenge", c."codeChallengeMethod", c."expiresAt", c."createdAt", c."consumedAt", c."userId",
			u."id", u."email", u."name", u."displayName", u."avatarUrl", u."password", u."createdAt", u."isPro", u."isAdmin", u."leaderboardOptIn"
		FROM "OAuthAuthorizationCode" c
		JOIN "User" u ON c."userId" = u."id"
		WHERE c."codeHash" = $1
		LIMIT 1
	`, codeHash).Scan(
		&c.ID, &c.CodeHash, &c.ClientID, &c.RedirectURI, &c.CodeChallenge, &c.CodeChallengeMethod, &c.ExpiresAt, &c.CreatedAt, &consumedVal, &c.UserID,
		&u.ID, &emailVal, &nameVal, &u.DisplayName, &u.AvatarURL, &u.Password, &u.CreatedAt, &u.IsPro, &u.IsAdmin, &u.LeaderboardOptIn,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	u.Email = emailVal
	u.Name = nameVal
	c.User = u
	c.ConsumedAt = consumedVal
	return &c, nil
}

func (r *PgxSessionRepository) ConsumeOAuthAuthorizationCode(ctx context.Context, id string, consumedAt time.Time) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "OAuthAuthorizationCode"
		SET "consumedAt" = $2
		WHERE "id" = $1 AND "consumedAt" IS NULL
	`, id, consumedAt)
	return err
}

func (r *PgxSessionRepository) FindGoogleDriveAuthHandoff(ctx context.Context, tokenHash string) (*GoogleDriveAuthHandoff, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	var h GoogleDriveAuthHandoff
	err := r.db.QueryRow(ctx, `
		SELECT "id", "tokenHash", "codeChallenge", "accessToken", "refreshToken", "expiresIn", "expiresAt", "createdAt", "consumedAt"
		FROM "GoogleDriveAuthHandoff"
		WHERE "tokenHash" = $1
		LIMIT 1
	`, tokenHash).Scan(&h.ID, &h.TokenHash, &h.CodeChallenge, &h.AccessToken, &h.RefreshToken, &h.ExpiresIn, &h.ExpiresAt, &h.CreatedAt, &h.ConsumedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &h, nil
}

func (r *PgxSessionRepository) ConsumeGoogleDriveAuthHandoff(ctx context.Context, handoffID string, consumedAt time.Time) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		UPDATE "GoogleDriveAuthHandoff"
		SET "consumedAt" = $2, "accessToken" = '', "refreshToken" = NULL
		WHERE "id" = $1 AND "consumedAt" IS NULL
	`, handoffID, consumedAt)
	return err
}

func (r *PgxSessionRepository) DeleteExpiredGoogleDriveAuthHandoffs(ctx context.Context, maxExpiresAt time.Time) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		DELETE FROM "GoogleDriveAuthHandoff"
		WHERE "expiresAt" <= $1
	`, maxExpiresAt)
	return err
}
