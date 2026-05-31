package token

import (
	"encoding/base64"
	"encoding/json"
	"strings"
)

const PortableSessionTokenPrefix = "nts_"

type PortableSession struct {
	AccessToken      string `json:"access_token"`
	ExpiresAt        string `json:"expires_at"`
	RefreshToken     string `json:"refresh_token"`
	RefreshExpiresAt string `json:"refresh_expires_at"`
}

type BridgeBackedSessionToken struct {
	TokenKind        string `json:"token_kind"`
	BridgeToken      string `json:"bridge_token"`
	AccessToken      string `json:"access_token"`
	ExpiresAt        string `json:"expires_at"`
	RefreshToken     string `json:"refresh_token"`
	RefreshExpiresAt string `json:"refresh_expires_at"`
}

type DecodedSessionToken struct {
	Kind         string
	BridgeToken  string
	AccessToken  string
	RefreshToken string
}

func EncodeSessionToken(payload any) (string, error) {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	return PortableSessionTokenPrefix + base64.RawURLEncoding.EncodeToString(encoded), nil
}

func CreateBridgeBackedSessionToken(bridgeToken string, expiresAt string) (string, error) {
	return EncodeSessionToken(BridgeBackedSessionToken{
		TokenKind:        "bridge",
		BridgeToken:      bridgeToken,
		AccessToken:      "",
		ExpiresAt:        expiresAt,
		RefreshToken:     "",
		RefreshExpiresAt: expiresAt,
	})
}

func DecodeSessionToken(sessionToken string) (*DecodedSessionToken, error) {
	trimmed := strings.TrimSpace(sessionToken)
	if !strings.HasPrefix(trimmed, PortableSessionTokenPrefix) {
		return nil, ErrInvalidToken
	}
	encoded := strings.TrimPrefix(trimmed, PortableSessionTokenPrefix)
	decoded, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return nil, ErrInvalidToken
	}

	var raw map[string]any
	if err := json.Unmarshal(decoded, &raw); err != nil {
		return nil, ErrInvalidToken
	}
	if tokenKind, _ := raw["token_kind"].(string); tokenKind == "bridge" {
		bridgeToken, ok := raw["bridge_token"].(string)
		if !ok {
			return nil, ErrInvalidToken
		}
		return &DecodedSessionToken{Kind: "bridge", BridgeToken: bridgeToken}, nil
	}

	accessToken, accessOK := raw["access_token"].(string)
	_, expiresOK := raw["expires_at"].(string)
	refreshToken, refreshOK := raw["refresh_token"].(string)
	_, refreshExpiresOK := raw["refresh_expires_at"].(string)
	if !accessOK || !expiresOK || !refreshOK || !refreshExpiresOK {
		return nil, ErrInvalidToken
	}
	return &DecodedSessionToken{Kind: "portable", AccessToken: accessToken, RefreshToken: refreshToken}, nil
}
