import re

file_path = "Sources/Notch/GeminiLive/GeminiLiveSession+Tools.swift"
with open(file_path, "r") as f:
    content = f.read()

# Remove '"command": ... ,'
content = re.sub(r'["\']command["\']\s*:\s*[^,]+,\s*', '', content)
# Remove ', "command": ...'
content = re.sub(r',\s*["\']command["\']\s*:\s*[^,}]+', '', content)
# Remove '"command": ...' if it's alone (unlikely, but just in case)
content = re.sub(r'["\']command["\']\s*:\s*[^,}]+', '', content)

# Add executeBrowserControl
browser_func = """
    func executeBrowserControl(action: String, args: [String: Any]) async -> [String: Any] {
        guard let handler = onBrowserBridgeCommand else {
            return ["success": false, "error": "Browser bridge is not available."]
        }
        
        let bridgeResult = await handler(action, args) ?? [:]
        
        var result = bridgeResult
        if result["success"] == nil {
            result["success"] = result["error"] == nil && result["errorMessage"] == nil
        }
        
        return result
    }
}
"""
content = content.replace("\n}\n", browser_func, 1)

with open(file_path, "w") as f:
    f.write(content)
