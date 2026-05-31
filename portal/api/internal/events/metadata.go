package events

import (
	"fmt"
	"strings"
)

const (
	maxDepth     = 4
	maxStringLen = 240
	maxArrayLen  = 25
)

var sensitiveKeyFragments = []string{
	"password",
	"token",
	"secret",
	"api_key",
	"apikey",
	"authorization",
	"cookie",
	"code",
	"verifier",
	"signature",
	"securehash",
	"prompt",
	"transcript",
	"message",
	"content",
	"system_instruction",
	"raw",
	"url",
	"query",
	"email",
	"display_name",
	"displayname",
}

func SanitizeMetadata(value map[string]any) map[string]any {
	if value == nil {
		return nil
	}
	sanitized, ok := sanitizeMap(value, 0).(map[string]any)
	if !ok {
		return nil
	}
	return sanitized
}

func sanitizeValue(value any, depth int) any {
	if depth >= maxDepth {
		return "[redacted-depth]"
	}

	switch typed := value.(type) {
	case nil, bool, int, int32, int64, float32, float64:
		return typed
	case string:
		return truncate(typed)
	case []any:
		limit := len(typed)
		if limit > maxArrayLen {
			limit = maxArrayLen
		}
		out := make([]any, 0, limit)
		for i := 0; i < limit; i++ {
			out = append(out, sanitizeValue(typed[i], depth+1))
		}
		return out
	case map[string]any:
		return sanitizeMap(typed, depth+1)
	default:
		return truncate(strings.TrimSpace(toString(typed)))
	}
}

func sanitizeMap(input map[string]any, depth int) any {
	out := make(map[string]any, len(input))
	for key, value := range input {
		if isSensitiveKey(key) {
			continue
		}
		out[key] = sanitizeValue(value, depth+1)
	}
	return out
}

func isSensitiveKey(key string) bool {
	normalized := strings.ToLower(strings.ReplaceAll(strings.TrimSpace(key), "-", "_"))
	for _, fragment := range sensitiveKeyFragments {
		if strings.Contains(normalized, fragment) {
			return true
		}
	}
	return false
}

func truncate(value string) string {
	if len(value) <= maxStringLen {
		return value
	}
	return value[:maxStringLen] + "…"
}

func toString(value any) string {
	return fmt.Sprint(value)
}
