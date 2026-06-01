package focus

import (
	"encoding/json"
	"net/http"
	"time"

	"notch/portal/api/internal/auth"
	"notch/portal/api/internal/events"
	"notch/portal/api/internal/focus/timeutil"
	"notch/portal/api/internal/httpjson"
)

type Handler struct {
	Repo          Repository
	Authenticator auth.Authenticator
	EventLog      *events.Logger
}

func NewHandler(repo Repository, authenticator auth.Authenticator, eventLog *events.Logger) *Handler {
	return &Handler{Repo: repo, Authenticator: authenticator, EventLog: eventLog}
}

func (h *Handler) Leaderboard(w http.ResponseWriter, req *http.Request) {
	window := timeutil.ParseFocusWindow(req.URL.Query().Get("window"))
	now := time.Now().UTC()
	weekStart := timeutil.StartOfUTCWeek(now)

	leaderboard, err := h.Repo.ReadFocusLeaderboard(req.Context(), window, weekStart, PublicLeaderboardLimit)
	if err != nil {
		println("[ERROR Leaderboard] ReadFocusLeaderboard failed:", err.Error())
		httpjson.Detail(w, http.StatusInternalServerError, "Failed to read leaderboard.")
		return
	}

	httpjson.JSON(w, http.StatusOK, LeaderboardResponse{
		Window:      window,
		Leaderboard: leaderboard,
	})
}

func (h *Handler) Me(w http.ResponseWriter, req *http.Request) {
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	now := time.Now().UTC()
	weekStart := timeutil.StartOfUTCWeek(now)
	summary, err := h.Repo.ReadFocusSummary(req.Context(), authCtx.User.ID, weekStart)
	if err != nil {
		httpjson.Detail(w, http.StatusInternalServerError, "Failed to read focus summary.")
		return
	}

	name := ""
	if authCtx.User.Name != nil {
		name = *authCtx.User.Name
	}
	displayName := ""
	if authCtx.User.DisplayName != nil {
		displayName = *authCtx.User.DisplayName
	} else {
		displayName = name
	}

	rank, streak, err := h.Repo.ReadUserWeeklyRankAndStreak(req.Context(), authCtx.User.ID, weekStart)
	if err != nil {
		println("[ERROR Handler.Me] ReadUserWeeklyRankAndStreak failed:", err.Error())
		rank = 0
		streak = 0
	}
	println("[DEBUG Focus Me] called for userID:", authCtx.User.ID, "rank:", rank, "streak:", streak, "optIn:", authCtx.User.LeaderboardOptIn)

	httpjson.JSON(w, http.StatusOK, map[string]any{
		"user": map[string]any{
			"id":                 authCtx.User.ID,
			"display_name":       displayName,
			"leaderboard_opt_in": authCtx.User.LeaderboardOptIn,
			"weekly_rank":        rank,
			"streak_days":        streak,
		},
		"week":     summary.Week,
		"all_time": summary.AllTime,
	})
}

func (h *Handler) Profile(w http.ResponseWriter, req *http.Request) {
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		h.logEvent(req, string(LeaderboardProfileRejected), "rejected", nil, nil, nil, http.StatusUnauthorized, FocusRejectedMetadata(ReasonUnauthorized))
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	var body map[string]any
	err = json.NewDecoder(req.Body).Decode(&body)
	optInVal, hasOptIn := body["leaderboard_opt_in"]
	optIn, isBool := optInVal.(bool)

	if err != nil || !hasOptIn || !isBool {
		h.logEvent(req, string(LeaderboardProfileRejected), "rejected", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusBadRequest, FocusRejectedMetadata(ReasonInvalidPayload))
		httpjson.Detail(w, http.StatusBadRequest, "leaderboard_opt_in must be a boolean.") // Next returns 400
		return
	}

	rawDisp, _ := body["display_name"].(string)
	displayName := NormalizeDisplayName(rawDisp)

	profile, err := h.Repo.UpdateLeaderboardProfile(req.Context(), authCtx.User.ID, displayName, optIn)
	if err != nil {
		h.logEvent(req, string(LeaderboardProfileFailed), "failure", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusInternalServerError, LeaderboardProfileFailedMetadata(err))
		httpjson.Detail(w, http.StatusInternalServerError, "Failed to update leaderboard profile.")
		return
	}

	h.logEvent(req, string(LeaderboardProfileUpdated), "success", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusOK, LeaderboardProfileUpdatedMetadata(profile.User.LeaderboardOptIn, &profile.User.DisplayName))
	httpjson.JSON(w, http.StatusOK, profile)
}

func (h *Handler) Sync(w http.ResponseWriter, req *http.Request) {
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		h.logEvent(req, string(SyncRejected), "rejected", nil, nil, nil, http.StatusUnauthorized, FocusRejectedMetadata(ReasonUnauthorized))
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	if authCtx.DeviceID == nil {
		h.logEvent(req, string(SyncRejected), "rejected", &authCtx.User.ID, &authCtx.SessionID, nil, http.StatusUnauthorized, FocusRejectedMetadata(ReasonDeviceNotBound))
		httpjson.Detail(w, http.StatusUnauthorized, "Sign in again to bind this device before syncing focus stats.")
		return
	}

	var body map[string]any
	_ = json.NewDecoder(req.Body).Decode(&body)

	entries, err := ValidateFocusSyncRequest(body)
	if err != nil {
		h.logEvent(req, string(SyncRejected), "rejected", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusBadRequest, FocusRejectedMetadata(ReasonInvalidPayload))
		httpjson.Detail(w, http.StatusBadRequest, err.Error())
		return
	}

	result, err := h.Repo.SyncFocusDailyStats(req.Context(), authCtx.User.ID, entries, *authCtx.DeviceID)
	if err != nil {
		h.logEvent(req, string(SyncFailed), "failure", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusInternalServerError, FocusSyncFailedMetadata(len(entries), err))
		httpjson.Detail(w, http.StatusInternalServerError, "Failed to sync focus daily stats.")
		return
	}

	h.logEvent(req, string(SyncSucceeded), "success", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusOK, FocusSyncSucceededMetadata(len(entries), result.Synced))
	httpjson.JSON(w, http.StatusOK, result)
}

func (h *Handler) logEvent(req *http.Request, eventType, outcome string, actorUserID, sessionID, deviceID *string, statusCode int, metadata map[string]any) {
	if h.EventLog == nil {
		return
	}
	h.EventLog.Log(req.Context(), req, events.Event{
		EventType:   eventType,
		Outcome:     outcome,
		Source:      "desktop",
		ActorUserID: actorUserID,
		SessionID:   sessionID,
		DeviceID:    deviceID,
		StatusCode:  &statusCode,
		Metadata:    metadata,
	})
}
