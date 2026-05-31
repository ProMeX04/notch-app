package token

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

const BearerScheme = "Bearer"

type JWTPayload struct {
	UserID           string  `json:"userId"`
	Email            *string `json:"email"`
	Name             *string `json:"name"`
	DisplayName      *string `json:"displayName"`
	AvatarURL        *string `json:"avatarUrl"`
	IsPro            bool    `json:"isPro"`
	IsAdmin          bool    `json:"isAdmin"`
	LeaderboardOptIn bool    `json:"leaderboardOptIn"`
	UserCreatedAt    string  `json:"userCreatedAt"`
	SessionID        string  `json:"sessionId"`
	DeviceID         *string `json:"deviceId"`
	IssuedAt         int64   `json:"iat,omitempty"`
	ExpiresAt        int64   `json:"exp,omitempty"`
}

type jwtHeader struct {
	Algorithm string `json:"alg"`
	Type      string `json:"typ"`
}

var ErrInvalidToken = errors.New("invalid token")

func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func GenerateRefreshToken() (string, error) {
	buf := make([]byte, 48)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func SignJWT(payload JWTPayload, secret string, ttl time.Duration, now time.Time) (string, error) {
	payload.IssuedAt = now.Unix()
	payload.ExpiresAt = now.Add(ttl).Unix()

	headerJSON, err := json.Marshal(jwtHeader{Algorithm: "HS256", Type: "JWT"})
	if err != nil {
		return "", err
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	encodedHeader := base64.RawURLEncoding.EncodeToString(headerJSON)
	encodedPayload := base64.RawURLEncoding.EncodeToString(payloadJSON)
	signingInput := encodedHeader + "." + encodedPayload
	signature := signHS256(signingInput, secret)
	return signingInput + "." + signature, nil
}

func VerifyJWT(token string, secret string, now time.Time) (*JWTPayload, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, ErrInvalidToken
	}

	signingInput := parts[0] + "." + parts[1]
	expected := signHS256(signingInput, secret)
	if !hmac.Equal([]byte(parts[2]), []byte(expected)) {
		return nil, ErrInvalidToken
	}

	payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, ErrInvalidToken
	}
	var payload JWTPayload
	if err := json.Unmarshal(payloadJSON, &payload); err != nil {
		return nil, ErrInvalidToken
	}
	if payload.ExpiresAt != 0 && now.Unix() >= payload.ExpiresAt {
		return nil, ErrInvalidToken
	}
	return &payload, nil
}

func signHS256(signingInput string, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signingInput))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
