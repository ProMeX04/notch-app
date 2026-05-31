package auth

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"

	"github.com/go-chi/chi/v5"
	"golang.org/x/crypto/bcrypt"
)

func TestHandlerRegisterSucceeds(t *testing.T) {
	repo := &fakeSessionRepo{
		byID:         make(map[string]*Session),
		usersByEmail: make(map[string]*User),
	}
	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		RefreshService: RefreshService{
			Repo:            repo,
			JWTSecret:       "testsecret",
			AccessTokenTTL:  time.Hour,
			RefreshTokenTTL: 24 * time.Hour,
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: false,
			Domain: "localhost",
		},
		MaxActiveDevices: 3,
	}

	reqBody := RegisterRequest{
		Email:      "newuser@example.com",
		Password:   "password123",
		Name:       "New User",
		DeviceID:   "device_1",
		DeviceName: "Test Device",
		Platform:   "macOS",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp UserResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp.Email != "newuser@example.com" {
		t.Errorf("expected email %q, got %q", "newuser@example.com", resp.Email)
	}

	if resp.CurrentSessionID == nil || *resp.CurrentSessionID == "" {
		t.Error("expected session ID to be returned")
	}

	// Verify user is in repo
	user, err := repo.FindUserByEmail(context.Background(), "newuser@example.com")
	if err != nil || user == nil {
		t.Fatalf("user was not saved in repo")
	}

	// Verify session is in repo
	session, err := repo.FindSessionByID(context.Background(), *resp.CurrentSessionID)
	if err != nil || session == nil {
		t.Fatalf("session was not created in repo")
	}

	// Check cookies are set
	cookies := rec.Result().Cookies()
	var hasAccess, hasRefresh bool
	for _, c := range cookies {
		if c.Name == httpauth.AccessCookieName {
			hasAccess = true
		}
		if c.Name == httpauth.RefreshCookieName {
			hasRefresh = true
		}
	}
	if !hasAccess || !hasRefresh {
		t.Errorf("cookies not set properly: access=%t, refresh=%t", hasAccess, hasRefresh)
	}
}

func TestHandlerRegisterFailsEmailInUse(t *testing.T) {
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), 10)
	email := "existing@example.com"
	existingUser := &User{
		ID:        "user_1",
		Email:     &email,
		Password:  ptrStr(string(hashedPassword)),
		CreatedAt: time.Now(),
	}

	repo := &fakeSessionRepo{
		byID: make(map[string]*Session),
		usersByEmail: map[string]*User{
			"existing@example.com": existingUser,
		},
	}
	handler := Handler{
		Repo: repo,
	}

	reqBody := RegisterRequest{
		Email:    "existing@example.com",
		Password: "password123",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	if !strings.Contains(rec.Body.String(), "Email này đã được sử dụng") {
		t.Errorf("expected error message for email in use, got: %s", rec.Body.String())
	}
}

func TestHandlerLoginSucceeds(t *testing.T) {
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), 10)
	email := "user@example.com"
	existingUser := &User{
		ID:        "user_1",
		Email:     &email,
		Password:  ptrStr(string(hashedPassword)),
		CreatedAt: time.Now(),
	}

	repo := &fakeSessionRepo{
		byID: make(map[string]*Session),
		usersByEmail: map[string]*User{
			"user@example.com": existingUser,
		},
	}
	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		RefreshService: RefreshService{
			Repo:            repo,
			JWTSecret:       "testsecret",
			AccessTokenTTL:  time.Hour,
			RefreshTokenTTL: 24 * time.Hour,
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: false,
			Domain: "localhost",
		},
		MaxActiveDevices: 3,
	}

	reqBody := LoginRequest{
		Email:    "user@example.com",
		Password: "password123",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/login", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Login(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp UserResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp.Email != "user@example.com" {
		t.Errorf("expected email %q, got %q", "user@example.com", resp.Email)
	}

	if resp.CurrentSessionID == nil || *resp.CurrentSessionID == "" {
		t.Error("expected session ID to be returned")
	}
}

func TestHandlerLoginFailsIncorrectPassword(t *testing.T) {
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), 10)
	email := "user@example.com"
	existingUser := &User{
		ID:        "user_1",
		Email:     &email,
		Password:  ptrStr(string(hashedPassword)),
		CreatedAt: time.Now(),
	}

	repo := &fakeSessionRepo{
		byID: make(map[string]*Session),
		usersByEmail: map[string]*User{
			"user@example.com": existingUser,
		},
	}
	handler := Handler{
		Repo: repo,
	}

	reqBody := LoginRequest{
		Email:    "user@example.com",
		Password: "wrongpassword",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/login", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Login(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	if !strings.Contains(rec.Body.String(), "Email hoặc mật khẩu không chính xác") {
		t.Errorf("expected error message for invalid credentials, got: %s", rec.Body.String())
	}
}

func TestHandlerLogout(t *testing.T) {
	now := time.Now()
	email := "user@example.com"
	user := User{ID: "user_1", Email: &email, CreatedAt: now}
	accessToken, _ := token.SignJWT(token.JWTPayload{
		UserID:    "user_1",
		SessionID: "session_1",
	}, "testsecret", time.Hour, now)
	accessTokenHash := token.HashToken(accessToken)

	session := &Session{
		ID:              "session_1",
		TokenHash:       token.HashToken("refresh-token"),
		AccessTokenHash: &accessTokenHash,
		ExpiresAt:       now.Add(24 * time.Hour),
		AccessExpiresAt: ptrTime(now.Add(time.Hour)),
		UserID:          "user_1",
		User:            user,
	}

	repo := &fakeSessionRepo{
		byID: map[string]*Session{
			"session_1": session,
		},
		usersByEmail: map[string]*User{
			"user@example.com": &user,
		},
	}

	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: false,
			Domain: "localhost",
		},
	}

	req := httptest.NewRequest(http.MethodPost, "/api/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	rec := httptest.NewRecorder()

	handler.Logout(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected status 204, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify session was revoked in repo
	sess := repo.byID["session_1"]
	if sess.RevokedAt == nil {
		t.Error("expected session to be marked revoked")
	}

	// Check clear cookies header
	cookies := rec.Result().Cookies()
	var clearedAccess, clearedRefresh bool
	for _, c := range cookies {
		if c.Name == httpauth.AccessCookieName && c.Value == "" {
			clearedAccess = true
		}
		if c.Name == httpauth.RefreshCookieName && c.Value == "" {
			clearedRefresh = true
		}
	}
	if !clearedAccess || !clearedRefresh {
		t.Errorf("cookies not cleared properly: access=%t, refresh=%t", clearedAccess, clearedRefresh)
	}
}

func TestHandlerListSessions(t *testing.T) {
	now := time.Now()
	email := "user@example.com"
	user := User{ID: "user_1", Email: &email, CreatedAt: now}
	deviceID := "device_mac"
	accessToken, _ := token.SignJWT(token.JWTPayload{
		UserID:    "user_1",
		SessionID: "session_1",
		DeviceID:  &deviceID,
	}, "testsecret", time.Hour, now)
	accessTokenHash := token.HashToken(accessToken)

	session1 := &Session{
		ID:              "session_1",
		TokenHash:       token.HashToken("refresh-token-1"),
		AccessTokenHash: &accessTokenHash,
		ExpiresAt:       now.Add(24 * time.Hour),
		AccessExpiresAt: ptrTime(now.Add(time.Hour)),
		UserID:          "user_1",
		User:            user,
		DeviceID:        ptrStr("device_mac"),
		DeviceName:      ptrStr("Macbook Pro"),
		Platform:        ptrStr("macOS"),
		CreatedAt:       now,
		LastSeenAt:      now,
	}
	session2 := &Session{
		ID:              "session_2",
		TokenHash:       token.HashToken("refresh-token-2"),
		ExpiresAt:       now.Add(-time.Hour),
		UserID:          "user_1",
		User:            user,
		DeviceID:        ptrStr("device_phone"),
		DeviceName:      ptrStr("iPhone"),
		Platform:        ptrStr("iOS"),
		CreatedAt:       now.Add(-24 * time.Hour),
		LastSeenAt:      now.Add(-time.Hour),
	}

	repo := &fakeSessionRepo{
		byID: map[string]*Session{
			"session_1": session1,
			"session_2": session2,
		},
		usersByEmail: map[string]*User{
			"user@example.com": &user,
		},
	}

	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		MaxActiveDevices: 3,
	}

	req := httptest.NewRequest(http.MethodGet, "/api/auth/sessions", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("X-Notch-Device-Id", "device_mac")
	rec := httptest.NewRecorder()

	handler.ListSessions(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp SessionsResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp.MaxActiveDevices != 3 {
		t.Errorf("expected max active devices 3, got %d", resp.MaxActiveDevices)
	}

	if len(resp.Devices) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(resp.Devices))
	}

	// Verify sorting and contents (current session comes first)
	if resp.Devices[0].DeviceID != "device_mac" || !resp.Devices[0].Current {
		t.Errorf("expected current device_mac first, got device %s (current: %t)", resp.Devices[0].DeviceID, resp.Devices[0].Current)
	}
}

func TestHandlerRevokeSession(t *testing.T) {
	now := time.Now()
	email := "user@example.com"
	user := User{ID: "user_1", Email: &email, CreatedAt: now}
	accessToken, _ := token.SignJWT(token.JWTPayload{
		UserID:    "user_1",
		SessionID: "session_1",
	}, "testsecret", time.Hour, now)
	accessTokenHash := token.HashToken(accessToken)

	session1 := &Session{
		ID:              "session_1",
		TokenHash:       token.HashToken("refresh-token-1"),
		AccessTokenHash: &accessTokenHash,
		ExpiresAt:       now.Add(24 * time.Hour),
		AccessExpiresAt: ptrTime(now.Add(time.Hour)),
		UserID:          "user_1",
		User:            user,
		CreatedAt:       now,
		LastSeenAt:      now,
	}
	session2 := &Session{
		ID:              "session_2",
		TokenHash:       token.HashToken("refresh-token-2"),
		ExpiresAt:       now.Add(24 * time.Hour),
		UserID:          "user_1",
		User:            user,
		CreatedAt:       now,
		LastSeenAt:      now,
	}

	repo := &fakeSessionRepo{
		byID: map[string]*Session{
			"session_1": session1,
			"session_2": session2,
		},
		usersByEmail: map[string]*User{
			"user@example.com": &user,
		},
	}

	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
	}

	req := httptest.NewRequest(http.MethodDelete, "/api/auth/sessions/session_2", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)

	// Mock chi URL Param "id" -> "session_2"
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("id", "session_2")
	req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

	rec := httptest.NewRecorder()

	handler.RevokeSession(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected status 204, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify session2 was revoked in repo
	sess := repo.byID["session_2"]
	if sess.RevokedAt == nil || *sess.RevokedReason != "user_revoked" {
		t.Errorf("expected session2 to be revoked with user_revoked, got revokedAt: %v, reason: %v", sess.RevokedAt, sess.RevokedReason)
	}
}

func TestGoogleDriveHandoffCryptography(t *testing.T) {
	// Generate a 32-byte key and base64 encode it
	keyBytes := make([]byte, 32)
	_, _ = rand.Read(keyBytes)
	base64Key := base64.StdEncoding.EncodeToString(keyBytes)

	originalPlaintext := "my-secret-access-token-12345"

	// Encrypt
	encrypted, err := encryptGoogleDriveHandoffValue(originalPlaintext, base64Key)
	if err != nil {
		t.Fatalf("encryption failed: %v", err)
	}

	if !strings.HasPrefix(encrypted, "v1.") {
		t.Errorf("expected prefix v1., got %s", encrypted)
	}

	// Decrypt
	decrypted, err := decryptGoogleDriveHandoffValue(encrypted, base64Key)
	if err != nil {
		t.Fatalf("decryption failed: %v", err)
	}

	if decrypted != originalPlaintext {
		t.Errorf("decrypted value mismatch: got %q, want %q", decrypted, originalPlaintext)
	}
}

func ptrStr(s string) *string {
	return &s
}

func ptrTime(t time.Time) *time.Time {
	return &t
}

type mockTransport struct {
	roundTripFunc func(req *http.Request) (*http.Response, error)
}

func (m *mockTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	return m.roundTripFunc(req)
}

func TestHandlerGoogleLogin(t *testing.T) {
	handler := Handler{
		GoogleClientID: "mock-client-id",
	}

	t.Run("standard login redirect", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/auth/google?state=somestate", nil)
		rec := httptest.NewRecorder()

		handler.GoogleLogin(rec, req)

		if rec.Code != http.StatusTemporaryRedirect {
			t.Fatalf("expected redirect status, got %d", rec.Code)
		}

		loc := rec.Header().Get("Location")
		if !strings.Contains(loc, "accounts.google.com") {
			t.Errorf("expected location to be accounts.google.com, got %q", loc)
		}
		if !strings.Contains(loc, "client_id=mock-client-id") {
			t.Errorf("expected client_id param, got %q", loc)
		}
		if !strings.Contains(loc, "scope=openid+email+profile") {
			t.Errorf("expected login scopes, got %q", loc)
		}
	})

	t.Run("gdrive handoff redirect", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/auth/google?gdrive=true&state=desktopstate&code_challenge=challenge_abc", nil)
		rec := httptest.NewRecorder()

		handler.GoogleLogin(rec, req)

		if rec.Code != http.StatusTemporaryRedirect {
			t.Fatalf("expected redirect status, got %d", rec.Code)
		}

		loc := rec.Header().Get("Location")
		if !strings.Contains(loc, "accounts.google.com") {
			t.Errorf("expected location to be accounts.google.com, got %q", loc)
		}
		if !strings.Contains(loc, "scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.file") {
			t.Errorf("expected gdrive scope, got %q", loc)
		}
		if !strings.Contains(loc, "prompt=consent") {
			t.Errorf("expected prompt=consent, got %q", loc)
		}
		if !strings.Contains(loc, "access_type=offline") {
			t.Errorf("expected access_type=offline, got %q", loc)
		}
	})
}

func TestHandlerGoogleCallbackSucceedsStandardLogin(t *testing.T) {
	repo := &fakeSessionRepo{
		byID:         make(map[string]*Session),
		usersByEmail: make(map[string]*User),
	}

	mockHTTP := &http.Client{
		Transport: &mockTransport{
			roundTripFunc: func(req *http.Request) (*http.Response, error) {
				if req.URL.String() == "https://oauth2.googleapis.com/token" {
					resp := `{
						"access_token": "mock-access-token-123",
						"refresh_token": "mock-refresh-token-123",
						"expires_in": 3600
					}`
					return &http.Response{
						StatusCode: http.StatusOK,
						Body:       io.NopCloser(strings.NewReader(resp)),
						Header:     make(http.Header),
					}, nil
				}
				if req.URL.String() == "https://www.googleapis.com/oauth2/v2/userinfo" {
					if req.Header.Get("Authorization") != "Bearer mock-access-token-123" {
						return &http.Response{
							StatusCode: http.StatusUnauthorized,
							Body:       io.NopCloser(strings.NewReader(`{"error": "unauthorized"}`)),
							Header:     make(http.Header),
						}, nil
					}
					resp := `{
						"email": "googleuser@example.com",
						"name": "Google User",
						"picture": "https://lh3.googleusercontent.com/a/mock-picture-url"
					}`
					return &http.Response{
						StatusCode: http.StatusOK,
						Body:       io.NopCloser(strings.NewReader(resp)),
						Header:     make(http.Header),
					}, nil
				}
				return &http.Response{
					StatusCode: http.StatusNotFound,
					Body:       io.NopCloser(strings.NewReader(`{}`)),
					Header:     make(http.Header),
				}, nil
			},
		},
	}

	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		RefreshService: RefreshService{
			Repo:            repo,
			JWTSecret:       "testsecret",
			AccessTokenTTL:  time.Hour,
			RefreshTokenTTL: 24 * time.Hour,
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: false,
			Domain: "localhost",
		},
		MaxActiveDevices: 3,
		GoogleClientID:     "mock-client-id",
		GoogleClientSecret: "mock-client-secret",
		FrontendURL:        "http://frontend.local",
		HTTPClient:         mockHTTP,
	}

	req := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=mock-auth-code&state=state_param", nil)
	rec := httptest.NewRecorder()

	handler.GoogleCallback(rec, req)

	if rec.Code != http.StatusTemporaryRedirect {
		t.Fatalf("expected redirect status, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	loc := rec.Header().Get("Location")
	if loc != "http://frontend.local/account" {
		t.Errorf("expected redirect to account page, got %q", loc)
	}

	// Verify user is created in database
	u, err := repo.FindUserByEmail(context.Background(), "googleuser@example.com")
	if err != nil || u == nil {
		t.Fatalf("expected user to be created in database")
	}
	if *u.Name != "Google User" {
		t.Errorf("expected user name 'Google User', got %q", *u.Name)
	}
	if u.AvatarURL == nil || *u.AvatarURL != "https://lh3.googleusercontent.com/a/mock-picture-url" {
		t.Errorf("expected avatar URL to match, got %v", u.AvatarURL)
	}

	// Verify cookies set
	cookies := rec.Result().Cookies()
	var hasAccess, hasRefresh bool
	for _, c := range cookies {
		if c.Name == httpauth.AccessCookieName {
			hasAccess = true
		}
		if c.Name == httpauth.RefreshCookieName {
			hasRefresh = true
		}
	}
	if !hasAccess || !hasRefresh {
		t.Errorf("expected cookies to be set, access=%t, refresh=%t", hasAccess, hasRefresh)
	}
}

func TestHandlerGoogleCallbackSucceedsDriveHandoff(t *testing.T) {
	repo := &fakeSessionRepo{
		byID:         make(map[string]*Session),
		usersByEmail: make(map[string]*User),
	}

	mockHTTP := &http.Client{
		Transport: &mockTransport{
			roundTripFunc: func(req *http.Request) (*http.Response, error) {
				if req.URL.String() == "https://oauth2.googleapis.com/token" {
					resp := `{
						"access_token": "mock-drive-access-token-123",
						"refresh_token": "mock-drive-refresh-token-123",
						"expires_in": 3600
					}`
					return &http.Response{
						StatusCode: http.StatusOK,
						Body:       io.NopCloser(strings.NewReader(resp)),
						Header:     make(http.Header),
					}, nil
				}
				return &http.Response{
					StatusCode: http.StatusNotFound,
					Body:       io.NopCloser(strings.NewReader(`{}`)),
					Header:     make(http.Header),
				}, nil
			},
		},
	}

	keyBytes := make([]byte, 32)
	_, _ = rand.Read(keyBytes)
	base64Key := base64.StdEncoding.EncodeToString(keyBytes)

	handler := Handler{
		Repo: repo,
		GoogleClientID:     "mock-client-id",
		GoogleClientSecret: "mock-client-secret",
		DriveHandoffEncryptKey: base64Key,
		HTTPClient:         mockHTTP,
	}

	// state contains urlencoded fields: gdrive=true, desktop_state, code_challenge
	// The driveCodeChallenge must be exactly 43 characters
	driveCodeChallenge := "challenge_123456789012345678901234567890123" // 43 chars
	desktopState := "my-desktop-state"
	stateVal := "gdrive=true&desktop_state=" + url.QueryEscape(desktopState) + "&code_challenge=" + url.QueryEscape(driveCodeChallenge)

	req := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?code=mock-auth-code&state="+url.QueryEscape(stateVal), nil)
	rec := httptest.NewRecorder()

	handler.GoogleCallback(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	contentType := rec.Header().Get("Content-Type")
	if !strings.Contains(contentType, "text/html") {
		t.Errorf("expected content type text/html, got %q", contentType)
	}

	bodyStr := rec.Body.String()
	if !strings.Contains(bodyStr, "notch://gdrive/callback") {
		t.Errorf("expected deep link in body, got: %s", bodyStr)
	}

	// Verify handoff record in fake repo
	if len(repo.handoffs) != 1 {
		t.Fatalf("expected exactly 1 handoff record to be created, got %d", len(repo.handoffs))
	}

	handoff := repo.handoffs[0]
	if handoff.CodeChallenge != driveCodeChallenge {
		t.Errorf("expected code challenge %q, got %q", driveCodeChallenge, handoff.CodeChallenge)
	}

	// Decrypt stored access token
	decAccess, err := decryptGoogleDriveHandoffValue(handoff.AccessToken, base64Key)
	if err != nil {
		t.Fatalf("failed to decrypt access token: %v", err)
	}
	if decAccess != "mock-drive-access-token-123" {
		t.Errorf("expected decrypted access token %q, got %q", "mock-drive-access-token-123", decAccess)
	}

	// Decrypt stored refresh token
	if handoff.RefreshToken == nil {
		t.Fatalf("expected refresh token to be stored")
	}
	decRefresh, err := decryptGoogleDriveHandoffValue(*handoff.RefreshToken, base64Key)
	if err != nil {
		t.Fatalf("failed to decrypt refresh token: %v", err)
	}
	if decRefresh != "mock-drive-refresh-token-123" {
		t.Errorf("expected decrypted refresh token %q, got %q", "mock-drive-refresh-token-123", decRefresh)
	}
}

func TestHandlerGoogleCallbackFailures(t *testing.T) {
	handler := Handler{
		GoogleClientID:     "mock-client-id",
		GoogleClientSecret: "mock-client-secret",
		FrontendURL:        "http://frontend.local",
	}

	t.Run("missing code standard login redirect", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?error=access_denied", nil)
		rec := httptest.NewRecorder()

		handler.GoogleCallback(rec, req)

		if rec.Code != http.StatusTemporaryRedirect {
			t.Fatalf("expected redirect, got %d", rec.Code)
		}
		loc := rec.Header().Get("Location")
		if loc != "http://frontend.local/?error=Canceled" {
			t.Errorf("expected canceled redirect, got %q", loc)
		}
	})

	t.Run("missing code drive handoff deep link", func(t *testing.T) {
		stateVal := "gdrive=true&desktop_state=state123"
		req := httptest.NewRequest(http.MethodGet, "/api/auth/google/callback?error=access_denied&state="+url.QueryEscape(stateVal), nil)
		rec := httptest.NewRecorder()

		handler.GoogleCallback(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
		bodyStr := rec.Body.String()
		if !strings.Contains(bodyStr, "notch://gdrive/callback") || !strings.Contains(bodyStr, "state=state123") || !strings.Contains(bodyStr, "error=access_denied") {
			t.Errorf("expected deep link with error in body, got: %s", bodyStr)
		}
	})
}
