package admin

import (
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"strconv"
	"time"

	"notch/portal/api/internal/auth"
	"notch/portal/api/internal/events"
	"notch/portal/api/internal/httpjson"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Handler struct {
	DB     *pgxpool.Pool
	Logger *events.Logger
}

func NewHandler(db *pgxpool.Pool, logger *events.Logger) *Handler {
	return &Handler{
		DB:     db,
		Logger: logger,
	}
}

type DailyMetric struct {
	Date             string `json:"date"`
	Users            int    `json:"users"`
	PaidTransactions int    `json:"paidTransactions"`
	Revenue          int    `json:"revenue"`
	Events           int    `json:"events"`
}

type AdminStatsOverview struct {
	TotalUsers           int `json:"totalUsers"`
	ProUsers             int `json:"proUsers"`
	FreeUsers            int `json:"freeUsers"`
	AdminUsers           int `json:"adminUsers"`
	NewUsers7d           int `json:"newUsers7d"`
	NewUsers30d          int `json:"newUsers30d"`
	ActiveSessions       int `json:"activeSessions"`
	PaidTransactions     int `json:"paidTransactions"`
	FailedTransactions   int `json:"failedTransactions"`
	PendingTransactions  int `json:"pendingTransactions"`
	TotalRevenue         int `json:"totalRevenue"`
	RecentRejectedEvents int `json:"recentRejectedEvents"`
	RecentFailedEvents   int `json:"recentFailedEvents"`
}

type AdminStatsActorUser struct {
	Name  *string `json:"name"`
	Email *string `json:"email"`
}

type AdminStatsRecentEvent struct {
	ID            string               `json:"id"`
	CreatedAt     time.Time            `json:"createdAt"`
	EventType     string               `json:"eventType"`
	Outcome       string               `json:"outcome"`
	Source        string               `json:"source"`
	RequestPath   *string              `json:"requestPath"`
	RequestMethod *string              `json:"requestMethod"`
	StatusCode    *int                 `json:"statusCode"`
	ActorUserID   *string              `json:"actorUserId"`
	ActorUser     *AdminStatsActorUser `json:"actorUser"`
}

type AdminStatsResponse struct {
	Overview     AdminStatsOverview      `json:"overview"`
	Trends       []DailyMetric           `json:"trends"`
	RecentEvents []AdminStatsRecentEvent `json:"recentEvents"`
	SystemHealth string                  `json:"systemHealth"`
	GeneratedAt  time.Time               `json:"generatedAt"`
}

func startOfUTCDay(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func metricDateKey(t time.Time) string {
	return t.UTC().Format("2006-01-02")
}

func buildDailyMetrics(start time.Time, days int) ([]DailyMetric, map[string]*DailyMetric) {
	metrics := make([]DailyMetric, 0, days)
	byDate := make(map[string]*DailyMetric, days)
	for i := 0; i < days; i++ {
		date := start.AddDate(0, 0, i)
		metrics = append(metrics, DailyMetric{Date: metricDateKey(date)})
		byDate[metrics[i].Date] = &metrics[i]
	}
	return metrics, byDate
}

func (h *Handler) GetStats(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	now := time.Now().UTC()
	sevenDaysAgo := now.Add(-7 * 24 * time.Hour)
	thirtyDaysAgo := now.Add(-30 * 24 * time.Hour)
	trendDays := 14
	trendStart := startOfUTCDay(now.AddDate(0, 0, -(trendDays - 1)))
	metrics, metricsByDate := buildDailyMetrics(trendStart, trendDays)

	var overview AdminStatsOverview
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "User"`).Scan(&overview.TotalUsers); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "User" WHERE "isPro" = true`).Scan(&overview.ProUsers); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "User" WHERE "isAdmin" = true`).Scan(&overview.AdminUsers); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "User" WHERE "createdAt" >= $1`, sevenDaysAgo).Scan(&overview.NewUsers7d); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "User" WHERE "createdAt" >= $1`, thirtyDaysAgo).Scan(&overview.NewUsers30d); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "AuthSession" WHERE "revokedAt" IS NULL AND "refreshTokenExpiresAt" > $1`, now).Scan(&overview.ActiveSessions); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "PaymentTransaction" WHERE status = 'paid'`).Scan(&overview.PaidTransactions); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "PaymentTransaction" WHERE status = 'failed'`).Scan(&overview.FailedTransactions); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "PaymentTransaction" WHERE status = 'pending'`).Scan(&overview.PendingTransactions); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COALESCE(SUM(amount), 0) FROM "PaymentTransaction" WHERE status = 'paid'`).Scan(&overview.TotalRevenue); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "AppEvent" WHERE outcome = 'rejected' AND "createdAt" >= $1`, sevenDaysAgo).Scan(&overview.RecentRejectedEvents); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	if err := h.DB.QueryRow(ctx, `SELECT COUNT(*) FROM "AppEvent" WHERE outcome = 'failure' AND "createdAt" >= $1`, sevenDaysAgo).Scan(&overview.RecentFailedEvents); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	overview.FreeUsers = int(math.Max(float64(overview.TotalUsers-overview.ProUsers), 0))

	userRows, err := h.DB.Query(ctx, `
		SELECT to_char("createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day, COUNT(*)
		FROM "User"
		WHERE "createdAt" >= $1
		GROUP BY day
	`, trendStart)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	defer userRows.Close()
	for userRows.Next() {
		var day string
		var count int
		if err := userRows.Scan(&day, &count); err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
			return
		}
		if metric := metricsByDate[day]; metric != nil {
			metric.Users = count
		}
	}

	paymentRows, err := h.DB.Query(ctx, `
		SELECT to_char("createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day,
			COUNT(*) FILTER (WHERE status = 'paid'),
			COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0)
		FROM "PaymentTransaction"
		WHERE "createdAt" >= $1
		GROUP BY day
	`, trendStart)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	defer paymentRows.Close()
	for paymentRows.Next() {
		var day string
		var count int
		var revenue int
		if err := paymentRows.Scan(&day, &count, &revenue); err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
			return
		}
		if metric := metricsByDate[day]; metric != nil {
			metric.PaidTransactions = count
			metric.Revenue = revenue
		}
	}

	eventRows, err := h.DB.Query(ctx, `
		SELECT to_char("createdAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day, COUNT(*)
		FROM "AppEvent"
		WHERE "createdAt" >= $1
		GROUP BY day
	`, trendStart)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	defer eventRows.Close()
	for eventRows.Next() {
		var day string
		var count int
		if err := eventRows.Scan(&day, &count); err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
			return
		}
		if metric := metricsByDate[day]; metric != nil {
			metric.Events = count
		}
	}

	recentRows, err := h.DB.Query(ctx, `
		SELECT e.id, e."createdAt", e."eventType", e.outcome, e.source, e."requestPath", e."requestMethod", e."statusCode", e."actorUserId", u.name, u.email
		FROM "AppEvent" e
		LEFT JOIN "User" u ON u.id = e."actorUserId"
		ORDER BY e."createdAt" DESC
		LIMIT 12
	`)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
		return
	}
	defer recentRows.Close()

	recentEvents := make([]AdminStatsRecentEvent, 0, 12)
	for recentRows.Next() {
		var event AdminStatsRecentEvent
		var actorName *string
		var actorEmail *string
		if err := recentRows.Scan(&event.ID, &event.CreatedAt, &event.EventType, &event.Outcome, &event.Source, &event.RequestPath, &event.RequestMethod, &event.StatusCode, &event.ActorUserID, &actorName, &actorEmail); err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch stats")
			return
		}
		if actorName != nil || actorEmail != nil {
			event.ActorUser = &AdminStatsActorUser{Name: actorName, Email: actorEmail}
		}
		recentEvents = append(recentEvents, event)
	}

	systemHealth := "Healthy"
	if overview.RecentFailedEvents > 0 {
		systemHealth = "Degraded"
	}

	httpjson.JSON(w, http.StatusOK, AdminStatsResponse{
		Overview:     overview,
		Trends:       metrics,
		RecentEvents: recentEvents,
		SystemHealth: systemHealth,
		GeneratedAt:  now,
	})
}

type PaginationResponse struct {
	Page       int `json:"page"`
	Limit      int `json:"limit"`
	Total      int `json:"total"`
	TotalPages int `json:"totalPages"`
}

type UserListRow struct {
	ID                 string     `json:"id"`
	Name               *string    `json:"name"`
	Email              *string    `json:"email"`
	IsPro              bool       `json:"isPro"`
	IsAdmin            bool       `json:"isAdmin"`
	CreatedAt          time.Time  `json:"createdAt"`
	UpdatedAt          time.Time  `json:"updatedAt"`
	LastSeenAt         *time.Time `json:"lastSeenAt"`
	LatestEventAt      *time.Time `json:"latestEventAt"`
	LatestPaymentAt    *time.Time `json:"latestPaymentAt"`
	ActiveSessionCount int        `json:"activeSessionCount"`
	TotalSessionCount  int        `json:"totalSessionCount"`
	TrustedDeviceCount int        `json:"trustedDeviceCount"`
	PaidPaymentCount   int        `json:"paidPaymentCount"`
	TotalPaidRevenue   int        `json:"totalPaidRevenue"`
}

type UserListResponse struct {
	Users      []UserListRow      `json:"users"`
	Pagination PaginationResponse `json:"pagination"`
}

func (h *Handler) GetUsers(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	q := r.URL.Query().Get("q")
	plan := r.URL.Query().Get("plan")
	role := r.URL.Query().Get("role")
	sort := r.URL.Query().Get("sort")

	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page <= 0 {
		page = 1
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 25
	}
	if limit > 100 {
		limit = 100
	}
	offset := (page - 1) * limit

	var whereClauses []string
	var args []any
	argID := 1

	if q != "" {
		likePattern := "%" + q + "%"
		whereClauses = append(whereClauses, "(u.email ILIKE $"+strconv.Itoa(argID)+" OR u.name ILIKE $"+strconv.Itoa(argID)+" OR u.id ILIKE $"+strconv.Itoa(argID)+")")
		args = append(args, likePattern)
		argID++
	}

	if plan == "pro" {
		whereClauses = append(whereClauses, `u."isPro" = true`)
	} else if plan == "free" {
		whereClauses = append(whereClauses, `u."isPro" = false`)
	}

	if role == "admin" {
		whereClauses = append(whereClauses, `u."isAdmin" = true`)
	} else if role == "user" {
		whereClauses = append(whereClauses, `u."isAdmin" = false`)
	}

	whereSQL := ""
	if len(whereClauses) > 0 {
		whereSQL = "WHERE "
		for i, clause := range whereClauses {
			if i > 0 {
				whereSQL += " AND "
			}
			whereSQL += clause
		}
	}

	// Count query
	countSQL := `SELECT COUNT(*) FROM "User" u ` + whereSQL
	var total int
	err := h.DB.QueryRow(ctx, countSQL, args...).Scan(&total)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to count users")
		return
	}

	// Order by
	orderBySQL := ` ORDER BY u."createdAt" DESC`
	switch sort {
	case "oldest":
		orderBySQL = ` ORDER BY u."createdAt" ASC`
	case "updated":
		orderBySQL = ` ORDER BY u."updatedAt" DESC`
	case "name":
		orderBySQL = " ORDER BY u.name ASC"
	case "email":
		orderBySQL = " ORDER BY u.email ASC"
	}

	// Query with pagination
	selectSQL := `
		SELECT 
			u.id, 
			u.name, 
			u.email, 
			u."isPro", 
			u."isAdmin", 
			u."createdAt", 
			u."updatedAt",
			(SELECT s."lastSeenAt" FROM "AuthSession" s WHERE s."userId" = u.id ORDER BY s."lastSeenAt" DESC LIMIT 1) AS lastSeenAt,
			(SELECT MAX(COALESCE(p."paidAt", p."createdAt")) FROM "PaymentTransaction" p WHERE p."userId" = u.id) AS latestPaymentAt,
			(SELECT COUNT(*) FROM "AuthSession" s WHERE s."userId" = u.id AND s."revokedAt" IS NULL AND s."refreshTokenExpiresAt" > NOW()) AS activeSessionCount,
			(SELECT COUNT(*) FROM "AuthSession" s WHERE s."userId" = u.id) AS totalSessionCount,
			(SELECT COUNT(DISTINCT s."deviceId") FROM "AuthSession" s WHERE s."userId" = u.id AND s."trustedAt" IS NOT NULL AND s."deviceId" IS NOT NULL) AS trustedDeviceCount,
			(SELECT COUNT(*) FROM "PaymentTransaction" p WHERE p."userId" = u.id AND p.status = 'paid') AS paidPaymentCount,
			(SELECT COALESCE(SUM(p.amount), 0) FROM "PaymentTransaction" p WHERE p."userId" = u.id AND p.status = 'paid') AS totalPaidRevenue
		FROM "User" u
	` + whereSQL + orderBySQL + " LIMIT $" + strconv.Itoa(argID) + " OFFSET $" + strconv.Itoa(argID+1)

	args = append(args, limit, offset)

	rows, err := h.DB.Query(ctx, selectSQL, args...)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch users")
		return
	}
	defer rows.Close()

	var users []UserListRow
	for rows.Next() {
		var row UserListRow
		var lastSeen *time.Time
		var latestPayment *time.Time
		err := rows.Scan(
			&row.ID, &row.Name, &row.Email, &row.IsPro, &row.IsAdmin, &row.CreatedAt, &row.UpdatedAt,
			&lastSeen, &latestPayment, &row.ActiveSessionCount, &row.TotalSessionCount,
			&row.TrustedDeviceCount, &row.PaidPaymentCount, &row.TotalPaidRevenue,
		)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to scan user row")
			return
		}
		row.LastSeenAt = lastSeen
		row.LatestPaymentAt = latestPayment
		row.LatestEventAt = nil
		users = append(users, row)
	}

	totalPages := int(math.Ceil(float64(total) / float64(limit)))
	if totalPages <= 0 {
		totalPages = 1
	}

	httpjson.JSON(w, http.StatusOK, UserListResponse{
		Users: users,
		Pagination: PaginationResponse{
			Page:       page,
			Limit:      limit,
			Total:      total,
			TotalPages: totalPages,
		},
	})
}

type UserDetail struct {
	ID        string    `json:"id"`
	Name      *string   `json:"name"`
	Email     *string   `json:"email"`
	IsPro     bool      `json:"isPro"`
	IsAdmin   bool      `json:"isAdmin"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type TopEventType struct {
	EventType string `json:"eventType"`
	Count     int    `json:"count"`
}

type UserSummary struct {
	AccountAgeDays          int            `json:"accountAgeDays"`
	LastSeenAt              *time.Time     `json:"lastSeenAt"`
	ActiveSessionCount      int            `json:"activeSessionCount"`
	RevokedSessionCount     int            `json:"revokedSessionCount"`
	ExpiredSessionCount     int            `json:"expiredSessionCount"`
	TrustedDeviceCount      int            `json:"trustedDeviceCount"`
	PaidPaymentCount        int            `json:"paidPaymentCount"`
	TotalPaidRevenue        int            `json:"totalPaidRevenue"`
	LatestPaymentAt         *time.Time     `json:"latestPaymentAt"`
	RecentFailureEventCount int            `json:"recentFailureEventCount"`
	TopEventTypes           []TopEventType `json:"topEventTypes"`
}

type SessionDetail struct {
	ID              string     `json:"id"`
	DeviceID        *string    `json:"deviceId"`
	DeviceName      *string    `json:"deviceName"`
	Platform        *string    `json:"platform"`
	Status          string     `json:"status"` // "active", "revoked", "expired"
	ExpiresAt       time.Time  `json:"expiresAt"`
	AccessExpiresAt *time.Time `json:"accessExpiresAt"`
	CreatedAt       time.Time  `json:"createdAt"`
	LastSeenAt      time.Time  `json:"lastSeenAt"`
	TrustedAt       *time.Time `json:"trustedAt"`
	UpdatedAt       time.Time  `json:"updatedAt"`
	RevokedAt       *time.Time `json:"revokedAt"`
	RevokedReason   *string    `json:"revokedReason"`
}

type PaymentDetail struct {
	ID          string     `json:"id"`
	Provider    string     `json:"provider"`
	Status      string     `json:"status"`
	Amount      int        `json:"amount"`
	Currency    string     `json:"currency"`
	OrderID     string     `json:"orderId"`
	RequestID   string     `json:"requestId"`
	ProviderRef *string    `json:"providerRef"`
	OrderInfo   string     `json:"orderInfo"`
	CreatedAt   time.Time  `json:"createdAt"`
	UpdatedAt   time.Time  `json:"updatedAt"`
	PaidAt      *time.Time `json:"paidAt"`
	GuestEmail  *string    `json:"guestEmail"`
}

type EventDetail struct {
	ID            string         `json:"id"`
	CreatedAt     time.Time      `json:"createdAt"`
	EventType     string         `json:"eventType"`
	Outcome       string         `json:"outcome"`
	Source        string         `json:"source"`
	SessionID     *string        `json:"sessionId"`
	DeviceID      *string        `json:"deviceId"`
	RequestPath   *string        `json:"requestPath"`
	RequestMethod *string        `json:"requestMethod"`
	StatusCode    *int           `json:"statusCode"`
	UserAgent     *string        `json:"userAgent"`
	Metadata      map[string]any `json:"metadata"`
}

type UserDetailResponse struct {
	User     UserDetail      `json:"user"`
	Summary  UserSummary     `json:"summary"`
	Sessions []SessionDetail `json:"sessions"`
	Payments []PaymentDetail `json:"payments"`
	Events   []EventDetail   `json:"events"`
}

func (h *Handler) GetUserDetail(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id := chi.URLParam(r, "id")
	if id == "" {
		httpjson.Error(w, http.StatusBadRequest, "User ID is required")
		return
	}

	var u UserDetail
	err := h.DB.QueryRow(ctx, `
		SELECT id, name, email, "isPro", "isAdmin", "createdAt", "updatedAt"
		FROM "User"
		WHERE id = $1
	`, id).Scan(&u.ID, &u.Name, &u.Email, &u.IsPro, &u.IsAdmin, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httpjson.Error(w, http.StatusNotFound, "User not found")
		} else {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch user")
		}
		return
	}

	// Fetch sessions
	sRows, err := h.DB.Query(ctx, `
		SELECT id, "deviceId", "deviceName", platform, "refreshTokenExpiresAt", "accessTokenExpiresAt", "createdAt", "lastSeenAt", "trustedAt", "updatedAt", "revokedAt", "revokedReason"
		FROM "AuthSession"
		WHERE "userId" = $1
		ORDER BY "lastSeenAt" DESC
		LIMIT 50
	`, id)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch user sessions")
		return
	}
	defer sRows.Close()

	var sessions []SessionDetail
	var activeSessionCount int
	var revokedSessionCount int
	var expiredSessionCount int
	trustedDevices := make(map[string]bool)

	now := time.Now()
	for sRows.Next() {
		var s SessionDetail
		err := sRows.Scan(
			&s.ID, &s.DeviceID, &s.DeviceName, &s.Platform, &s.ExpiresAt, &s.AccessExpiresAt,
			&s.CreatedAt, &s.LastSeenAt, &s.TrustedAt, &s.UpdatedAt, &s.RevokedAt, &s.RevokedReason,
		)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to scan session")
			return
		}

		if s.RevokedAt != nil {
			s.Status = "revoked"
			revokedSessionCount++
		} else if s.ExpiresAt.Before(now) {
			s.Status = "expired"
			expiredSessionCount++
		} else {
			s.Status = "active"
			activeSessionCount++
		}

		if s.TrustedAt != nil && s.DeviceID != nil && *s.DeviceID != "" {
			trustedDevices[*s.DeviceID] = true
		}

		sessions = append(sessions, s)
	}

	// Fetch payments
	pRows, err := h.DB.Query(ctx, `
		SELECT id, provider, status, amount, currency, "orderId", "requestId", "providerRef", "orderInfo", "createdAt", "updatedAt", "paidAt", "guestEmail"
		FROM "PaymentTransaction"
		WHERE "userId" = $1
		ORDER BY "createdAt" DESC
		LIMIT 50
	`, id)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch user payments")
		return
	}
	defer pRows.Close()

	var payments []PaymentDetail
	var paidPaymentCount int
	var totalPaidRevenue int
	var latestPaymentAt *time.Time

	for pRows.Next() {
		var p PaymentDetail
		err := pRows.Scan(
			&p.ID, &p.Provider, &p.Status, &p.Amount, &p.Currency, &p.OrderID, &p.RequestID,
			&p.ProviderRef, &p.OrderInfo, &p.CreatedAt, &p.UpdatedAt, &p.PaidAt, &p.GuestEmail,
		)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to scan payment")
			return
		}

		if p.Status == "paid" {
			paidPaymentCount++
			totalPaidRevenue += p.Amount
		}

		payments = append(payments, p)
	}

	if len(payments) > 0 {
		latestPaymentAt = &payments[0].CreatedAt
	}

	// Fetch events
	eRows, err := h.DB.Query(ctx, `
		SELECT id, "createdAt", "eventType", outcome, source, "sessionId", "deviceId", "requestPath", "requestMethod", "statusCode", "userAgent", metadata
		FROM "AppEvent"
		WHERE "actorUserId" = $1
		ORDER BY "createdAt" DESC
		LIMIT 50
	`, id)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch user events")
		return
	}
	defer eRows.Close()

	var eventList []EventDetail
	var recentFailureEventCount int
	eventTypeCounts := make(map[string]int)

	for eRows.Next() {
		var e EventDetail
		var metaBytes []byte
		err := eRows.Scan(
			&e.ID, &e.CreatedAt, &e.EventType, &e.Outcome, &e.Source, &e.SessionID, &e.DeviceID,
			&e.RequestPath, &e.RequestMethod, &e.StatusCode, &e.UserAgent, &metaBytes,
		)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to scan event")
			return
		}

		if len(metaBytes) > 0 {
			_ = json.Unmarshal(metaBytes, &e.Metadata)
		}

		if e.Outcome == "failure" || e.Outcome == "rejected" {
			recentFailureEventCount++
		}

		eventTypeCounts[e.EventType]++
		eventList = append(eventList, e)
	}

	var topEventTypes []TopEventType
	for k, v := range eventTypeCounts {
		topEventTypes = append(topEventTypes, TopEventType{EventType: k, Count: v})
	}
	// Sort top events by count desc
	for i := 0; i < len(topEventTypes); i++ {
		for j := i + 1; j < len(topEventTypes); j++ {
			if topEventTypes[j].Count > topEventTypes[i].Count {
				topEventTypes[i], topEventTypes[j] = topEventTypes[j], topEventTypes[i]
			}
		}
	}
	if len(topEventTypes) > 6 {
		topEventTypes = topEventTypes[:6]
	}

	var lastSeenAt *time.Time
	if len(sessions) > 0 {
		lastSeenAt = &sessions[0].LastSeenAt
	}

	ageDays := int(math.Max(math.Floor(time.Since(u.CreatedAt).Hours()/24.0), 0.0))

	httpjson.JSON(w, http.StatusOK, UserDetailResponse{
		User: u,
		Summary: UserSummary{
			AccountAgeDays:          ageDays,
			LastSeenAt:              lastSeenAt,
			ActiveSessionCount:      activeSessionCount,
			RevokedSessionCount:     revokedSessionCount,
			ExpiredSessionCount:     expiredSessionCount,
			TrustedDeviceCount:      len(trustedDevices),
			PaidPaymentCount:        paidPaymentCount,
			TotalPaidRevenue:        totalPaidRevenue,
			LatestPaymentAt:         latestPaymentAt,
			RecentFailureEventCount: recentFailureEventCount,
			TopEventTypes:           topEventTypes,
		},
		Sessions: sessions,
		Payments: payments,
		Events:   eventList,
	})
}

type UpdateUserRequest struct {
	IsPro   *bool `json:"isPro"`
	IsAdmin *bool `json:"isAdmin"`
}

func (h *Handler) UpdateUser(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id := chi.URLParam(r, "id")
	if id == "" {
		httpjson.Error(w, http.StatusBadRequest, "User ID is required")
		return
	}

	var req UpdateUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	// First verify user exists and get current values
	var currentIsPro, currentIsAdmin bool
	err := h.DB.QueryRow(ctx, `SELECT "isPro", "isAdmin" FROM "User" WHERE id = $1`, id).Scan(&currentIsPro, &currentIsAdmin)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httpjson.Error(w, http.StatusNotFound, "User not found")
		} else {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to verify user")
		}
		return
	}

	isPro := currentIsPro
	if req.IsPro != nil {
		isPro = *req.IsPro
	}

	isAdmin := currentIsAdmin
	if req.IsAdmin != nil {
		isAdmin = *req.IsAdmin
	}

	_, err = h.DB.Exec(ctx, `
		UPDATE "User"
		SET "isPro" = $1, "isAdmin" = $2, "updatedAt" = NOW()
		WHERE id = $3
	`, isPro, isAdmin, id)
	if err != nil {
		h.logAdminEvent(r, "admin.user_update_failed", "failure", http.StatusInternalServerError, map[string]any{
			"targetUserId": id,
			"error":        err.Error(),
		})
		httpjson.Error(w, http.StatusInternalServerError, "Failed to update user")
		return
	}

	// Fetch updated user
	var u UserDetail
	_ = h.DB.QueryRow(ctx, `
		SELECT id, name, email, "isPro", "isAdmin", "createdAt", "updatedAt"
		FROM "User"
		WHERE id = $1
	`, id).Scan(&u.ID, &u.Name, &u.Email, &u.IsPro, &u.IsAdmin, &u.CreatedAt, &u.UpdatedAt)

	h.logAdminEvent(r, "admin.user_update_succeeded", "success", http.StatusOK, map[string]any{
		"targetUserId": id,
		"oldIsPro":     currentIsPro,
		"newIsPro":     isPro,
		"oldIsAdmin":   currentIsAdmin,
		"newIsAdmin":   isAdmin,
	})

	httpjson.JSON(w, http.StatusOK, u)
}

func (h *Handler) logAdminEvent(req *http.Request, eventType, outcome string, statusCode int, metadata map[string]any) {
	if h.Logger == nil {
		return
	}
	authCtx, _ := req.Context().Value(auth.AuthContextKey).(*auth.AuthContext)
	var actorUserID *string
	var sessionID *string
	var deviceID *string
	if authCtx != nil {
		actorUserID = &authCtx.User.ID
		sessionID = &authCtx.SessionID
		deviceID = authCtx.DeviceID
	}

	h.Logger.Log(req.Context(), req, events.Event{
		EventType:   eventType,
		Outcome:     outcome,
		Source:      "web",
		ActorUserID: actorUserID,
		SessionID:   sessionID,
		DeviceID:    deviceID,
		StatusCode:  &statusCode,
		Metadata:    metadata,
	})
}
