package capabilities

import (
	"encoding/json"
	"sync"
)

// Static embedded representation matching /portal/src/lib/capabilities/notch-capabilities.json
const rawDefaultManifest = `{
  "version": 1,
  "capabilities": [
    {"key": "gemini_live", "name": "Gemini Live", "description": "Trải nghiệm trò chuyện trực tiếp bằng giọng nói với AI", "requirement": "pro"},
    {"key": "advanced_pomodoro", "name": "Focus Pomodoro", "description": "Hỗ trợ tập trung và quản lý phiên làm việc nâng cao", "requirement": "free"},
    {"key": "website_blocking", "name": "Chặn website", "description": "Chặn trang web gây xao nhãng", "requirement": "free"},
    {"key": "media_control", "name": "Điều khiển nhạc", "description": "Điều khiển nhạc trên Notch", "requirement": "free"},
    {"key": "browser_integration", "name": "Kết nối trình duyệt", "description": "Kết nối ứng dụng với trình duyệt", "requirement": "free"},
    {"key": "shelf_sync", "name": "Shelf", "description": "Lưu tạm file, văn bản và đường dẫn trong Notch", "requirement": "pro"}
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
