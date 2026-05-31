package auth

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"
	"notch/portal/api/internal/httpjson"

	"golang.org/x/crypto/bcrypt"
)

type Handler struct {
	Authenticator    Authenticator
	RefreshService   RefreshService
	CookieConfig     httpauth.CookieConfig
	MaxActiveDevices int
	Repo             SessionRepository
}

type LoginRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DeviceID    string `json:"device_id"`
	DeviceName  string `json:"device_name"`
	Platform    string `json:"platform"`
	TrustDevice any    `json:"trust_device"`
}

type RegisterRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	Name        string `json:"name"`
	DeviceID    string `json:"device_id"`
	DeviceName  string `json:"device_name"`
	Platform    string `json:"platform"`
	TrustDevice any    `json:"trust_device"`
}

func (h Handler) Me(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	auth, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err == nil {
		sessionID := auth.SessionID
		httpjson.JSON(w, http.StatusOK, BuildUserResponse(auth.User, &sessionID, h.MaxActiveDevices))
		return
	}

	payload, refreshErr := h.RefreshService.RefreshWithToken(req.Context(), req, httpauth.ReadRefreshTokenCookie(req), DeviceInputFromRefreshRequest(req))
	if refreshErr != nil {
		httpauth.ClearAuthCookies(w, req, h.CookieConfig)
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}
	applyPayloadCookies(w, req, h.CookieConfig, payload)
	sessionID := payload.Session.ID
	httpjson.JSON(w, http.StatusOK, UserResponse{
		ID:               payload.User.ID,
		Email:            payload.User.Email,
		Name:             payload.User.Name,
		DisplayName:      payload.User.DisplayName,
		AvatarURL:        payload.User.AvatarURL,
		CreatedAt:        payload.User.CreatedAt,
		IsPro:            payload.User.IsPro,
		LeaderboardOptIn: payload.User.LeaderboardOptIn,
		PermissionPolicy: payload.User.PermissionPolicy,
		CurrentSessionID: &sessionID,
		MaxActiveDevices: payload.MaxActiveDevices,
	})
}

func (h Handler) Refresh(w http.ResponseWriter, req *http.Request) {
	body, device := ParseRefreshRequest(req)
	payload, err := h.RefreshService.RefreshWithToken(req.Context(), req, RefreshTokenFromRequest(req, body), device)
	if err != nil {
		httpauth.ClearAuthCookies(w, req, h.CookieConfig)
		httpjson.Detail(w, http.StatusUnauthorized, "Refresh token is invalid or expired.")
		return
	}
	applyPayloadCookies(w, req, h.CookieConfig, payload)
	httpjson.JSON(w, http.StatusOK, payload)
}

func (h Handler) Login(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	var body LoginRequest
	if req.Body != nil {
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
			return
		}
	}

	email := normalizeEmail(body.Email)
	password := body.Password

	if email == "" || password == "" {
		httpjson.Error(w, http.StatusBadRequest, "Vui lòng nhập email và mật khẩu")
		return
	}

	if !isValidEmail(email) {
		httpjson.Error(w, http.StatusBadRequest, "Email không hợp lệ")
		return
	}

	user, err := h.Repo.FindUserByEmail(req.Context(), email)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	if user == nil || user.Password == nil {
		httpjson.Error(w, http.StatusUnauthorized, "Email hoặc mật khẩu không chính xác")
		return
	}

	err = bcrypt.CompareHashAndPassword([]byte(*user.Password), []byte(password))
	if err != nil {
		httpjson.Error(w, http.StatusUnauthorized, "Email hoặc mật khẩu không chính xác")
		return
	}

	deviceInput := deviceInputFromRequest(req, body.DeviceID, body.DeviceName, body.Platform, parseTrustDevice(body.TrustDevice))

	now := time.Now()
	sessionID, err := h.createSessionAndTokens(req.Context(), w, req, *user, deviceInput, now)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to create session")
		return
	}

	httpjson.JSON(w, http.StatusOK, BuildUserResponse(*user, sessionID, h.MaxActiveDevices))
}

func (h Handler) Register(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	var body RegisterRequest
	if req.Body != nil {
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
			return
		}
	}

	email := normalizeEmail(body.Email)
	password := body.Password
	name := strings.TrimSpace(body.Name)

	if email == "" || password == "" {
		httpjson.Error(w, http.StatusBadRequest, "Vui lòng nhập đầy đủ email và mật khẩu")
		return
	}

	if !isValidEmail(email) {
		httpjson.Error(w, http.StatusBadRequest, "Email không hợp lệ")
		return
	}

	existingUser, err := h.Repo.FindUserByEmail(req.Context(), email)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	if existingUser != nil && existingUser.Password != nil && *existingUser.Password != "" {
		httpjson.Error(w, http.StatusBadRequest, "Email này đã được sử dụng")
		return
	}

	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(password), 10)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	hashedPassword := string(hashedBytes)

	now := time.Now()
	var user *User

	if existingUser != nil {
		user, err = h.Repo.UpdateUserPasswordAndName(req.Context(), existingUser.ID, name, hashedPassword, now)
	} else {
		userID := generateUUID()
		if name == "" {
			name = strings.Split(email, "@")[0]
		}
		user, err = h.Repo.CreateUser(req.Context(), userID, email, name, hashedPassword, now)
	}

	if err != nil || user == nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to save user")
		return
	}

	deviceInput := deviceInputFromRequest(req, body.DeviceID, body.DeviceName, body.Platform, parseTrustDevice(body.TrustDevice))

	sessionID, err := h.createSessionAndTokens(req.Context(), w, req, *user, deviceInput, now)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to create session")
		return
	}

	httpjson.JSON(w, http.StatusCreated, BuildUserResponse(*user, sessionID, h.MaxActiveDevices))
}

func (h Handler) Logout(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	var sessionID string
	var err error
	var session *Session

	refreshToken := httpauth.ReadRefreshTokenCookie(req)
	if refreshToken != "" {
		session, err = h.Repo.FindSessionByRefreshTokenHash(req.Context(), token.HashToken(refreshToken))
	}

	if session == nil || err != nil {
		accessToken := accessTokenFromRequest(req)
		if accessToken != "" {
			authCtx, authErr := h.Authenticator.AuthenticateRequest(req.Context(), req)
			if authErr == nil && authCtx != nil {
				sessionID = authCtx.SessionID
			}
		}
	} else {
		sessionID = session.ID
	}

	if sessionID == "" {
		httpauth.ClearAuthCookies(w, req, h.CookieConfig)
		httpjson.Detail(w, http.StatusBadRequest, "Missing session token.")
		return
	}

	now := time.Now()
	_ = h.Repo.RevokeSession(req.Context(), sessionID, now, "logout")

	httpauth.ClearAuthCookies(w, req, h.CookieConfig)
	w.WriteHeader(http.StatusNoContent)
}

func (h Handler) createSessionAndTokens(ctx context.Context, w http.ResponseWriter, req *http.Request, user User, deviceInput DeviceInput, now time.Time) (*string, error) {
	sessionID := generateUUID()

	refreshToken, err := token.GenerateRefreshToken()
	if err != nil {
		return nil, err
	}
	refreshTokenHash := token.HashToken(refreshToken)

	accessTTL := h.RefreshService.AccessTokenTTL
	if accessTTL <= 0 {
		accessTTL = time.Hour
	}
	refreshTTL := h.RefreshService.RefreshTokenTTL
	if refreshTTL <= 0 {
		refreshTTL = 30 * 24 * time.Hour
	}

	accessExpiresAt := now.Add(accessTTL)
	refreshExpiresAt := now.Add(refreshTTL)

	device := NormalizeDevice(req, deviceInput, user.ID+":"+sessionID, nil)
	var trustedAt *time.Time
	if device.TrustDevice {
		trustedAt = &now
	}

	accessToken, err := token.SignJWT(token.JWTPayload{
		UserID:           user.ID,
		Email:            user.Email,
		Name:             user.Name,
		DisplayName:      user.DisplayName,
		AvatarURL:        user.AvatarURL,
		IsPro:            user.IsPro,
		IsAdmin:          user.IsAdmin,
		LeaderboardOptIn: user.LeaderboardOptIn,
		UserCreatedAt:    user.CreatedAt.UTC().Format(time.RFC3339Nano),
		SessionID:        sessionID,
		DeviceID:         &device.DeviceID,
	}, h.RefreshService.JWTSecret, accessTTL, now)
	if err != nil {
		return nil, err
	}
	accessTokenHash := token.HashToken(accessToken)

	err = h.Repo.CreateSession(ctx, sessionID, user.ID, refreshTokenHash, &accessTokenHash, device, refreshExpiresAt, &accessExpiresAt, trustedAt, now)
	if err != nil {
		return nil, err
	}

	httpauth.ApplyAuthCookies(w, req, h.CookieConfig, httpauth.AuthCookiePayload{
		AccessToken:      accessToken,
		AccessExpiresAt:  accessExpiresAt,
		RefreshToken:     refreshToken,
		RefreshExpiresAt: refreshExpiresAt,
	})

	return &sessionID, nil
}

func applyPayloadCookies(w http.ResponseWriter, req *http.Request, cfg httpauth.CookieConfig, payload AuthPayload) {
	accessExpiresAt, _ := time.Parse(time.RFC3339Nano, payload.ExpiresAt)
	refreshExpiresAt, _ := time.Parse(time.RFC3339Nano, payload.RefreshExpiresAt)
	httpauth.ApplyAuthCookies(w, req, cfg, httpauth.AuthCookiePayload{
		AccessToken:      payload.AccessToken,
		AccessExpiresAt:  accessExpiresAt,
		RefreshToken:     payload.RefreshToken,
		RefreshExpiresAt: refreshExpiresAt,
	})
}

func noStore(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")
}

func normalizeEmail(email string) string {
	return strings.TrimSpace(strings.ToLower(email))
}

func isValidEmail(email string) bool {
	parts := strings.Split(email, "@")
	if len(parts) != 2 {
		return false
	}
	return parts[0] != "" && strings.Contains(parts[1], ".")
}

func generateUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

func deviceInputFromRequest(req *http.Request, bodyDeviceID, bodyDeviceName, bodyPlatform string, trustDevice bool) DeviceInput {
	deviceID := bodyDeviceID
	if deviceID == "" && req != nil {
		deviceID = req.Header.Get("x-notch-device-id")
	}
	deviceName := bodyDeviceName
	if deviceName == "" && req != nil {
		deviceName = req.Header.Get("x-notch-device-name")
	}
	platform := bodyPlatform
	if platform == "" && req != nil {
		platform = req.Header.Get("x-notch-platform")
	}
	return DeviceInput{
		DeviceID:    deviceID,
		DeviceName:  deviceName,
		Platform:    platform,
		TrustDevice: trustDevice,
	}
}
