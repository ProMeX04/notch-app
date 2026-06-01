package auth

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"
	"notch/portal/api/internal/httpjson"

	"github.com/go-chi/chi/v5"
	"golang.org/x/crypto/bcrypt"
)

type Handler struct {
	Authenticator          Authenticator
	RefreshService         RefreshService
	CookieConfig           httpauth.CookieConfig
	MaxActiveDevices       int
	Repo                   SessionRepository
	GoogleClientID         string
	GoogleClientSecret     string
	FrontendURL            string
	DriveHandoffEncryptKey string
	HTTPClient             *http.Client
	NativeClientID         string
	NativeRedirectURIs     []string
}

type DeviceSummary struct {
	DeviceID           string  `json:"device_id"`
	DeviceName         string  `json:"device_name"`
	Platform           string  `json:"platform"`
	TrustedAt          *string `json:"trusted_at"`
	CreatedAt          string  `json:"created_at"`
	LastSeenAt         string  `json:"last_seen_at"`
	RevokedAt          *string `json:"revoked_at"`
	RevokedReason      *string `json:"revoked_reason"`
	Active             bool    `json:"active"`
	Current            bool    `json:"current"`
	ActiveSessionCount int     `json:"active_session_count"`
}

type SessionsResponse struct {
	MaxActiveDevices int             `json:"max_active_devices"`
	Devices          []DeviceSummary `json:"devices"`
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
	fmt.Printf("[DEBUG Me] req.Header: %+v\n", req.Header)
	for _, cookie := range req.Cookies() {
		fmt.Printf("[DEBUG Me] cookie: Name=%s, Value=%s\n", cookie.Name, cookie.Value)
	}
	auth, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err == nil {
		fmt.Printf("[DEBUG Me] Success: auth.SessionID=%s, auth.DeviceID=%+v\n", auth.SessionID, auth.DeviceID)
		sessionID := auth.SessionID
		policy := h.getPermissionPolicy(req.Context(), auth.User.IsPro)
		httpjson.JSON(w, http.StatusOK, BuildUserResponse(auth.User, &sessionID, h.MaxActiveDevices, policy))
		return
	}
	fmt.Printf("[DEBUG Me] AuthenticateRequest failed: %v\n", err)

	payload, refreshErr := h.RefreshService.RefreshWithToken(req.Context(), req, httpauth.ReadRefreshTokenCookie(req), DeviceInputFromRefreshRequest(req))
	if refreshErr != nil {
		fmt.Printf("[DEBUG Me] RefreshWithToken failed: %v\n", refreshErr)
		httpauth.ClearAuthCookies(w, req, h.CookieConfig)
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}
	fmt.Printf("[DEBUG Me] RefreshWithToken success: session.ID=%s\n", payload.Session.ID)
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
		IsAdmin:          payload.User.IsAdmin,
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

	policy := h.getPermissionPolicy(req.Context(), user.IsPro)
	httpjson.JSON(w, http.StatusOK, BuildUserResponse(*user, sessionID, h.MaxActiveDevices, policy))
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

	policy := h.getPermissionPolicy(req.Context(), user.IsPro)
	httpjson.JSON(w, http.StatusCreated, BuildUserResponse(*user, sessionID, h.MaxActiveDevices, policy))
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

func (h Handler) ListSessions(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	sessions, err := h.Repo.FindAllSessionsByUserID(req.Context(), authCtx.User.ID)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch sessions")
		return
	}

	now := time.Now()
	devicesMap := make(map[string]*DeviceSummary)

	for _, s := range sessions {
		key := "session:" + s.ID
		if s.DeviceID != nil && *s.DeviceID != "" {
			key = *s.DeviceID
		}

		active := s.RevokedAt == nil && s.ExpiresAt.After(now)
		existing, found := devicesMap[key]

		if !found {
			deviceName := "Unknown device"
			if s.DeviceName != nil {
				deviceName = *s.DeviceName
			}
			platform := "unknown"
			if s.Platform != nil {
				platform = *s.Platform
			}
			var trustedAtStr *string
			if s.TrustedAt != nil {
				val := s.TrustedAt.UTC().Format(time.RFC3339Nano)
				trustedAtStr = &val
			}
			var revokedAtStr *string
			if s.RevokedAt != nil {
				val := s.RevokedAt.UTC().Format(time.RFC3339Nano)
				revokedAtStr = &val
			}
			var revokedReasonStr *string
			if s.RevokedReason != nil {
				revokedReasonStr = s.RevokedReason
			}

			activeCount := 0
			if active {
				activeCount = 1
			}

			summary := &DeviceSummary{
				DeviceID:           key,
				DeviceName:         deviceName,
				Platform:           platform,
				TrustedAt:          trustedAtStr,
				CreatedAt:          s.CreatedAt.UTC().Format(time.RFC3339Nano),
				LastSeenAt:         s.LastSeenAt.UTC().Format(time.RFC3339Nano),
				RevokedAt:          revokedAtStr,
				RevokedReason:      revokedReasonStr,
				Active:             active,
				Current:            s.ID == authCtx.SessionID,
				ActiveSessionCount: activeCount,
			}
			devicesMap[key] = summary
		} else {
			existing.Current = existing.Current || s.ID == authCtx.SessionID
			existing.Active = existing.Active || active
			if active {
				existing.ActiveSessionCount++
			}
			if s.TrustedAt != nil {
				val := s.TrustedAt.UTC().Format(time.RFC3339Nano)
				if existing.TrustedAt == nil || val > *existing.TrustedAt {
					existing.TrustedAt = &val
				}
			}
			lastSeenVal := s.LastSeenAt.UTC().Format(time.RFC3339Nano)
			if lastSeenVal > existing.LastSeenAt {
				existing.LastSeenAt = lastSeenVal
				if s.DeviceName != nil {
					existing.DeviceName = *s.DeviceName
				}
				if s.Platform != nil {
					existing.Platform = *s.Platform
				}
				if s.RevokedAt != nil {
					val := s.RevokedAt.UTC().Format(time.RFC3339Nano)
					existing.RevokedAt = &val
				} else {
					existing.RevokedAt = nil
				}
				existing.RevokedReason = s.RevokedReason
			}
		}
	}

	devicesSlice := make([]DeviceSummary, 0, len(devicesMap))
	for _, dev := range devicesMap {
		devicesSlice = append(devicesSlice, *dev)
	}

	sort.Slice(devicesSlice, func(i, j int) bool {
		a := devicesSlice[i]
		b := devicesSlice[j]
		if a.Current != b.Current {
			return a.Current
		}
		if a.Active != b.Active {
			return a.Active
		}
		return a.LastSeenAt > b.LastSeenAt
	})

	maxActive := h.MaxActiveDevices
	if maxActive <= 0 {
		maxActive = 3
	}

	httpjson.JSON(w, http.StatusOK, SessionsResponse{
		MaxActiveDevices: maxActive,
		Devices:          devicesSlice,
	})
}

func (h Handler) RevokeSession(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	sessionID := chi.URLParam(req, "id")
	if strings.TrimSpace(sessionID) == "" {
		httpjson.Error(w, http.StatusBadRequest, "Missing session ID")
		return
	}

	err = h.Repo.RevokeSessionByID(req.Context(), sessionID, authCtx.User.ID)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to revoke session")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h Handler) PatchSessions(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	type SessionPatchRequest struct {
		Action   string `json:"action"`
		DeviceID string `json:"device_id"`
	}

	var body SessionPatchRequest
	if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "Invalid request payload")
		return
	}

	deviceID := strings.TrimSpace(body.DeviceID)
	if deviceID == "" {
		httpjson.Error(w, http.StatusBadRequest, "Missing device_id")
		return
	}

	action := strings.ToLower(strings.TrimSpace(body.Action))
	if action != "trust" && action != "untrust" && action != "revoke" {
		httpjson.Error(w, http.StatusBadRequest, "Unsupported or missing action")
		return
	}

	switch action {
	case "trust":
		err = h.Repo.SetTrustedDevice(req.Context(), authCtx.User.ID, deviceID, true)
	case "untrust":
		err = h.Repo.SetTrustedDevice(req.Context(), authCtx.User.ID, deviceID, false)
	case "revoke":
		err = h.Repo.RevokeDeviceSessions(req.Context(), authCtx.User.ID, deviceID, authCtx.SessionID)
	}

	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to execute session patch action")
		return
	}

	h.ListSessions(w, req)
}

func parseEncryptionKey(base64Key string) ([]byte, error) {
	key, err := base64.StdEncoding.DecodeString(strings.TrimSpace(base64Key))
	if err != nil {
		return nil, err
	}
	if len(key) != 32 {
		return nil, fmt.Errorf("encryption key must be 32 bytes, got %d", len(key))
	}
	return key, nil
}

func encryptGoogleDriveHandoffValue(value string, base64Key string) (string, error) {
	key, err := parseEncryptionKey(base64Key)
	if err != nil {
		return "", err
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	iv := make([]byte, 12)
	if _, err := io.ReadFull(rand.Reader, iv); err != nil {
		return "", err
	}

	ciphertextAndTag := aesgcm.Seal(nil, iv, []byte(value), nil)
	tagSize := aesgcm.Overhead()
	ciphertext := ciphertextAndTag[:len(ciphertextAndTag)-tagSize]
	authTag := ciphertextAndTag[len(ciphertextAndTag)-tagSize:]

	encodedIV := base64.RawURLEncoding.EncodeToString(iv)
	encodedTag := base64.RawURLEncoding.EncodeToString(authTag)
	encodedCiphertext := base64.RawURLEncoding.EncodeToString(ciphertext)

	return fmt.Sprintf("v1.%s.%s.%s", encodedIV, encodedTag, encodedCiphertext), nil
}

func decryptGoogleDriveHandoffValue(value string, base64Key string) (string, error) {
	parts := strings.Split(value, ".")
	if len(parts) != 4 || parts[0] != "v1" {
		return "", errors.New("invalid Google Drive handoff payload")
	}

	encodedIV := parts[1]
	encodedTag := parts[2]
	encodedCiphertext := parts[3]

	iv, err := base64.RawURLEncoding.DecodeString(encodedIV)
	if err != nil {
		return "", err
	}

	authTag, err := base64.RawURLEncoding.DecodeString(encodedTag)
	if err != nil {
		return "", err
	}

	ciphertext, err := base64.RawURLEncoding.DecodeString(encodedCiphertext)
	if err != nil {
		return "", err
	}

	key, err := parseEncryptionKey(base64Key)
	if err != nil {
		return "", err
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	ciphertextAndTag := append(ciphertext, authTag...)
	plaintext, err := aesgcm.Open(nil, iv, ciphertextAndTag, nil)
	if err != nil {
		return "", err
	}

	return string(plaintext), nil
}

func (h Handler) GoogleLogin(w http.ResponseWriter, req *http.Request) {
	q := req.URL.Query()
	desktopState := q.Get("state")
	codeChallenge := q.Get("code_challenge")
	gdrive := q.Get("gdrive")

	if h.GoogleClientID == "" {
		httpjson.Error(w, http.StatusInternalServerError, "Google Client ID is not configured")
		return
	}

	scheme := "http"
	if req.TLS != nil || req.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	redirectURI := fmt.Sprintf("%s://%s/api/auth/google/callback", scheme, req.Host)

	googleAuthURL := "https://accounts.google.com/o/oauth2/v2/auth"
	authURL := fmt.Sprintf("%s?client_id=%s&redirect_uri=%s&response_type=code", googleAuthURL, h.GoogleClientID, url.QueryEscape(redirectURI))

	if gdrive == "true" {
		stateParams := fmt.Sprintf("gdrive=true&desktop_state=%s&code_challenge=%s", url.QueryEscape(desktopState), url.QueryEscape(codeChallenge))
		authURL = fmt.Sprintf("%s&scope=%s&access_type=offline&prompt=consent&state=%s", authURL, url.QueryEscape("https://www.googleapis.com/auth/drive.file"), url.QueryEscape(stateParams))
	} else {
		state := q.Encode()
		authURL = fmt.Sprintf("%s&scope=%s&access_type=online&state=%s", authURL, url.QueryEscape("openid email profile"), url.QueryEscape(state))
	}

	http.Redirect(w, req, authURL, http.StatusTemporaryRedirect)
}

func (h Handler) GoogleCallback(w http.ResponseWriter, req *http.Request) {
	q := req.URL.Query()
	code := q.Get("code")
	state := q.Get("state")

	stateParams, _ := url.ParseQuery(state)
	gdrive := stateParams.Get("gdrive")
	desktopState := stateParams.Get("desktop_state")
	driveCodeChallenge := stateParams.Get("code_challenge")

	scheme := "http"
	if req.TLS != nil || req.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	redirectURI := fmt.Sprintf("%s://%s/api/auth/google/callback", scheme, req.Host)

	if code == "" {
		if gdrive == "true" {
			deepLink := fmt.Sprintf("notch://gdrive/callback?state=%s&error=%s", url.QueryEscape(desktopState), url.QueryEscape(q.Get("error")))
			if q.Get("error") == "" {
				deepLink = fmt.Sprintf("notch://gdrive/callback?state=%s&error=Canceled", url.QueryEscape(desktopState))
			}
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.WriteHeader(http.StatusOK)
			_, _ = fmt.Fprintf(w, `<!doctype html><meta charset="utf-8"><title>Notch Google Drive</title><p>Google Drive authorization was canceled.</p><a href="%s">Return to Notch</a><script>window.location.href=%s;</script>`, escapeHTMLAttribute(deepLink), stringifyJSON(deepLink))
			return
		}
		// Redirect back to frontend with error
		http.Redirect(w, req, h.FrontendURL+"/?error=Canceled", http.StatusTemporaryRedirect)
		return
	}

	if h.GoogleClientID == "" || h.GoogleClientSecret == "" {
		httpjson.Error(w, http.StatusInternalServerError, "Google OAuth is not configured")
		return
	}

	httpClient := h.HTTPClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}

	// 1. Exchange Auth Code
	resp, err := httpClient.PostForm("https://oauth2.googleapis.com/token", url.Values{
		"client_id":     {h.GoogleClientID},
		"client_secret": {h.GoogleClientSecret},
		"code":          {code},
		"grant_type":    {"authorization_code"},
		"redirect_uri":  {redirectURI},
	})
	if err != nil {
		fmt.Printf("[DEBUG GoogleCallback] Google token exchange request failed: %v\n", err)
		if gdrive == "true" {
			httpjson.Error(w, http.StatusBadRequest, "Failed to exchange token: "+err.Error())
		} else {
			http.Redirect(w, req, h.FrontendURL+"/?error=Failed to exchange token", http.StatusTemporaryRedirect)
		}
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		fmt.Printf("[DEBUG GoogleCallback] Google token exchange returned HTTP %d: %s\n", resp.StatusCode, string(bodyBytes))
		if gdrive == "true" {
			httpjson.Error(w, http.StatusBadRequest, fmt.Sprintf("Failed to exchange token: Google returned %d", resp.StatusCode))
		} else {
			http.Redirect(w, req, h.FrontendURL+"/?error=Failed to exchange token", http.StatusTemporaryRedirect)
		}
		return
	}

	type GoogleTokenResponse struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int    `json:"expires_in"`
	}

	var tokenData GoogleTokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tokenData); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal Server Error")
		return
	}

	if tokenData.AccessToken == "" {
		httpjson.Error(w, http.StatusBadRequest, "Google token exchange returned no access token")
		return
	}

	if gdrive == "true" {
		if driveCodeChallenge == "" || len(driveCodeChallenge) != 43 {
			httpjson.Error(w, http.StatusBadRequest, "Missing or invalid Google Drive handoff challenge")
			return
		}

		encAccess, err := encryptGoogleDriveHandoffValue(tokenData.AccessToken, h.DriveHandoffEncryptKey)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to encrypt access token")
			return
		}

		var encRefresh *string
		if tokenData.RefreshToken != "" {
			ref, err := encryptGoogleDriveHandoffValue(tokenData.RefreshToken, h.DriveHandoffEncryptKey)
			if err != nil {
				httpjson.Error(w, http.StatusInternalServerError, "Failed to encrypt refresh token")
				return
			}
			encRefresh = &ref
		}

		// Generate Handoff Token (random 32 bytes encoded as base64url)
		handoffBytes := make([]byte, 32)
		_, _ = rand.Read(handoffBytes)
		handoffToken := base64.RawURLEncoding.EncodeToString(handoffBytes)

		// Generate Handoff ID
		idBytes := make([]byte, 12)
		_, _ = rand.Read(idBytes)
		handoffID := "gdh_" + hex.EncodeToString(idBytes)

		expiresAt := time.Now().Add(5 * time.Minute)
		createdAt := time.Now()

		err = h.Repo.CreateGoogleDriveAuthHandoff(req.Context(), handoffID, token.HashToken(handoffToken), driveCodeChallenge, encAccess, encRefresh, &tokenData.ExpiresIn, expiresAt, createdAt)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Failed to create handoff record")
			return
		}

		deepLink := fmt.Sprintf("notch://gdrive/callback?handoff_token=%s&state=%s", url.QueryEscape(handoffToken), url.QueryEscape(desktopState))
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)

		_, _ = fmt.Fprintf(w, `
<!DOCTYPE html>
<html>
<head>
  <title>Notch Google Drive Connection</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      background-color: #0d0d0e;
      color: #f3f4f6;
      margin: 0;
      padding: 16px;
      box-sizing: border-box;
    }
    .card {
      text-align: center;
      max-width: 420px;
      width: 100%%;
      padding: 32px;
      background: rgba(255, 255, 255, 0.03);
      border-radius: 24px;
      border: 1px solid rgba(255, 255, 255, 0.08);
      box-shadow: 0 20px 40px rgba(0,0,0,0.5);
      backdrop-filter: blur(20px);
    }
    h2 {
      font-size: 1.5rem;
      margin-top: 0;
      margin-bottom: 8px;
      font-weight: 700;
      letter-spacing: -0.025em;
    }
    p {
      font-size: 0.95rem;
      color: #9ca3af;
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 14px 28px;
      background: linear-gradient(135deg, #3b82f6, #1d4ed8);
      color: #fff;
      text-decoration: none;
      border-radius: 12px;
      font-weight: 600;
      font-size: 0.95rem;
      transition: all 0.2s ease;
      box-shadow: 0 4px 12px rgba(37, 99, 235, 0.3);
      border: none;
      cursor: pointer;
      width: 100%%;
      box-sizing: border-box;
    }
    .button:hover {
      transform: translateY(-1px);
      box-shadow: 0 6px 20px rgba(37, 99, 235, 0.4);
    }
    .button:active {
      transform: translateY(1px);
    }
    .logo {
      width: 64px;
      height: 64px;
      margin: 0 auto 20px;
      background: rgba(255,255,255,0.05);
      border-radius: 18px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .logo svg {
      width: 32px;
      height: 32px;
      fill: #3b82f6;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">
      <svg viewBox="0 0 24 24">
        <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM19 18H6c-2.21 0-4-1.79-4-4 0-2.05 1.53-3.76 3.56-3.97l1.07-.11.5-.95C8.08 7.14 9.94 6 12 6c2.62 0 4.88 1.86 5.39 4.43l.3 1.5 1.53.11c1.56.1 2.78 1.41 2.78 2.96 0 1.65-1.35 3-3 3z"/>
      </svg>
    </div>
    <h2>Kết nối Google Drive thành công!</h2>
    <p>Ứng dụng Notch sẽ tự động mở để hoàn tất liên kết. Nếu không thấy phản hồi, vui lòng nhấn nút bên dưới.</p>
    <a href="%s" class="button">Hoàn tất liên kết</a>
  </div>
  <script>
    window.location.href = %s;
  </script>
</body>
</html>
`, escapeHTMLAttribute(deepLink), stringifyJSON(deepLink))
		return
	}

	// 2. Fetch User Profile
	reqProfile, err := http.NewRequest(http.MethodGet, "https://www.googleapis.com/oauth2/v2/userinfo", nil)
	if err != nil {
		http.Redirect(w, req, h.FrontendURL+"/?error=Internal Error", http.StatusTemporaryRedirect)
		return
	}
	reqProfile.Header.Set("Authorization", "Bearer "+tokenData.AccessToken)
	respProfile, err := httpClient.Do(reqProfile)
	if err != nil || respProfile.StatusCode != http.StatusOK {
		http.Redirect(w, req, h.FrontendURL+"/?error=Failed to fetch profile", http.StatusTemporaryRedirect)
		return
	}
	defer respProfile.Body.Close()

	type GoogleUserInfo struct {
		Email   string `json:"email"`
		Name    string `json:"name"`
		Picture string `json:"picture"`
	}

	var profile GoogleUserInfo
	if err := json.NewDecoder(respProfile.Body).Decode(&profile); err != nil || profile.Email == "" {
		http.Redirect(w, req, h.FrontendURL+"/?error=Failed to fetch profile", http.StatusTemporaryRedirect)
		return
	}

	lowerEmail := normalizeEmail(profile.Email)
	avatarURL := normalizedGoogleAvatarURL(profile.Picture)

	// 3. Find or Create User
	user, err := h.Repo.FindUserByEmail(req.Context(), lowerEmail)
	if err != nil {
		http.Redirect(w, req, h.FrontendURL+"/?error=Internal Error", http.StatusTemporaryRedirect)
		return
	}

	now := time.Now()
	if user == nil {
		userID := generateUUID()
		user, err = h.Repo.CreateUser(req.Context(), userID, lowerEmail, profile.Name, "", now)
		if err == nil && user != nil && avatarURL != nil {
			_ = h.Repo.UpdateUserAvatar(req.Context(), user.ID, avatarURL)
			user.AvatarURL = avatarURL
		}
	} else if (avatarURL != nil && user.AvatarURL == nil) || (avatarURL != nil && user.AvatarURL != nil && *avatarURL != *user.AvatarURL) {
		err = h.Repo.UpdateUserAvatar(req.Context(), user.ID, avatarURL)
		if err == nil {
			user.AvatarURL = avatarURL
		}
	}

	if err != nil || user == nil {
		http.Redirect(w, req, h.FrontendURL+"/?error=Internal Error", http.StatusTemporaryRedirect)
		return
	}

	// 4. Create Session
	deviceInput := DeviceInput{
		DeviceID:   "google-oauth",
		DeviceName: "Browser",
		Platform:   "Web",
	}

	_, err = h.createSessionAndTokens(req.Context(), w, req, *user, deviceInput, now)
	if err != nil {
		http.Redirect(w, req, h.FrontendURL+"/?error=Failed to create session", http.StatusTemporaryRedirect)
		return
	}

	// 5. Redirect Destination
	redirectDestination := h.FrontendURL + "/account"
	if strings.Contains(state, "client_id=") {
		redirectDestination = h.FrontendURL + "/oauth/authorize?" + state
	}

	http.Redirect(w, req, redirectDestination, http.StatusTemporaryRedirect)
}

func normalizedGoogleAvatarURL(value string) *string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	u, err := url.Parse(trimmed)
	if err != nil {
		return nil
	}
	hostname := strings.ToLower(u.Hostname())
	isGoogleAvatarHost := hostname == "googleusercontent.com" ||
		strings.HasSuffix(hostname, ".googleusercontent.com") ||
		hostname == "google.com" ||
		strings.HasSuffix(hostname, ".google.com")

	if u.Scheme != "https" || !isGoogleAvatarHost {
		return nil
	}
	val := u.String()
	return &val
}

func escapeHTMLAttribute(value string) string {
	r := strings.NewReplacer("&", "&amp;", "\"", "&quot;", "<", "&lt;", ">", "&gt;")
	return r.Replace(value)
}

func stringifyJSON(value any) string {
	b, err := json.Marshal(value)
	if err != nil {
		return "null"
	}
	return string(b)
}

func (h Handler) getPermissionPolicy(ctx context.Context, isPro bool) PermissionPolicy {
	features := map[string]string{
		"talk_connection":         "pro",
		"focus_pomodoro":          "free",
		"focus_website_blocklist": "free",
		"media_controls":          "free",
		"browser_bridge":          "free",
		"panel_shelf":             "pro",
	}

	pgxRepo, ok := h.Repo.(*PgxSessionRepository)
	if ok && pgxRepo != nil && pgxRepo.db != nil {
		rows, err := pgxRepo.db.Query(ctx, `SELECT "key", "isProOnly", "isEnabled" FROM "FeatureConfig"`)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var key string
				var isProOnly bool
				var isEnabled bool
				if err := rows.Scan(&key, &isProOnly, &isEnabled); err == nil {
					if !isEnabled {
						features[key] = "disabled"
					} else if isProOnly {
						features[key] = "pro"
					} else {
						features[key] = "free"
					}
				}
			}
		}
	}

	return PermissionPolicy{
		Version:   1,
		Features:  features,
		UpdatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
}
