package capabilities

import (
	"encoding/json"
	"sync"
)

// Static embedded representation matching /portal/src/lib/capabilities/notch-capabilities.json
const rawDefaultManifest = `{
  "version": 1,
  "capabilities": [
    {"key": "talk_connection", "name": "Gemini Live", "description": "Trò chuyện với AI trực tiếp từ Notch", "requirement": "pro"},
    {"key": "focus_pomodoro", "name": "Focus Pomodoro", "description": "Hỗ trợ tập trung và quản lý phiên làm việc", "requirement": "free"},
    {"key": "media_controls", "name": "Điều khiển nhạc", "description": "Điều khiển nhạc trên Notch", "requirement": "free"},
    {"key": "panel_shelf", "name": "Shelf", "description": "Lưu tạm file, văn bản và đường dẫn trong Notch", "requirement": "pro"}
  ]
}`

var (
	parsedManifest CapabilitiesManifest
	manifestOnce   sync.Once
)

// GetDefaultManifest returns the thread-safe static capability manifest defaults.
func GetDefaultManifest() CapabilitiesManifest {
	manifestOnce.Do(func() {
		if err := json.Unmarshal([]byte(rawDefaultManifest), &parsedManifest); err != nil {
			panic("failed to parse static capabilities manifest: " + err.Error())
		}
	})
	return parsedManifest
}
