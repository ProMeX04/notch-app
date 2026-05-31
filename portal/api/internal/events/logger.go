package events

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Logger struct {
	db     *pgxpool.Pool
	logger *slog.Logger
	ipSalt string
}

type Event struct {
	EventType   string
	Outcome     string
	Source      string
	ActorUserID *string
	SessionID   *string
	DeviceID    *string
	StatusCode  *int
	Metadata    map[string]any
}

func NewLogger(db *pgxpool.Pool, logger *slog.Logger, ipSalt string) *Logger {
	return &Logger{db: db, logger: logger, ipSalt: ipSalt}
}

func (l *Logger) Log(ctx context.Context, req *http.Request, event Event) {
	if l == nil || l.db == nil {
		return
	}
	metadata := SanitizeMetadata(event.Metadata)
	path, method, userAgent, ipHash := requestFields(req, l.ipSalt)

	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	_, err := l.db.Exec(ctx, `
		INSERT INTO "AppEvent" (
			"id", "eventType", "outcome", "source", "actorUserId", "sessionId", "deviceId",
			"requestPath", "requestMethod", "statusCode", "ipHash", "userAgent", "metadata", "createdAt"
		) VALUES (
			gen_random_uuid()::text, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW()
		)
	`, event.EventType, event.Outcome, event.Source, event.ActorUserID, event.SessionID, event.DeviceID, path, method, event.StatusCode, ipHash, userAgent, metadata)
	if err != nil && l.logger != nil {
		l.logger.Warn("failed to write app event", "event_type", event.EventType, "error", err)
	}
}

func requestFields(req *http.Request, salt string) (path *string, method *string, userAgent *string, ipHash *string) {
	if req == nil {
		return nil, nil, nil, nil
	}
	pathValue := req.URL.Path
	methodValue := req.Method
	ua := strings.TrimSpace(req.UserAgent())
	path = &pathValue
	method = &methodValue
	if ua != "" {
		userAgent = &ua
	}
	ip := clientIP(req)
	if ip != "" && salt != "" {
		sum := sha256.Sum256([]byte(salt + ":" + ip))
		value := hex.EncodeToString(sum[:])
		ipHash = &value
	}
	return path, method, userAgent, ipHash
}

func clientIP(req *http.Request) string {
	if forwarded := strings.TrimSpace(req.Header.Get("x-forwarded-for")); forwarded != "" {
		parts := strings.Split(forwarded, ",")
		return strings.TrimSpace(parts[0])
	}
	if realIP := strings.TrimSpace(req.Header.Get("x-real-ip")); realIP != "" {
		return realIP
	}
	host, _, err := net.SplitHostPort(req.RemoteAddr)
	if err == nil {
		return host
	}
	return strings.TrimSpace(req.RemoteAddr)
}
