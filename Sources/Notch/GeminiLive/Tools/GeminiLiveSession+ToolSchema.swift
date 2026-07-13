import Foundation
import NotchTooling

extension GeminiLiveSession {
    var enabledToolDeclarations: [[String: Any]] {
        var decls: [[String: Any]] = []
        // Shell `exec` is intentionally not registered — removed for security.
        if enabledTools.contains(.read) {
            decls.append([
                "name": GeminiLiveToolName.read,
                "description": GeminiWorkspaceReadTool.openClawReadToolDescription,
                "parameters": GeminiWorkspaceReadTool.openClawReadToolParameters
            ])
        }
        if enabledTools.contains(.calendar) {
            decls.append([
                "name": GeminiLiveToolName.calendar,
                "description": """
                Manage the user's macOS Calendar (iCloud, Google, Exchange, etc.).
                Actions:
                - "list": Query events. Params: daysAhead (0-30, default 0), daysBack (0-30, default 0), query (filter by title).
                - "create": Create a new event. Params: title (required), startDate (required, 'yyyy-MM-dd HH:mm'), endDate (optional), allDay (bool), location, notes, calendarName, alertMinutesBefore (set a notification alert).
                - "delete": Delete an event. Params: eventId (required, from list results).
                - "calendars": List all available calendars and their properties.
                - "list_reminders": List pending or completed reminders (to-do items). Params: query, isCompleted, reminderList.
                - "create_reminder": Create a new reminder/to-do. Params: title (required), notes, reminderList, startDate (due date/time — the notification fires exactly at this time by default), alertMinutesBefore (only set if user explicitly asks to be reminded BEFORE the due time; defaults to 0 = alert at due time).
                - "complete_reminder": Mark a reminder as completed. Params: eventId (required).
                - "delete_reminder": Delete a reminder. Params: eventId (required).
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'list', 'create', 'delete', 'calendars', 'list_reminders', 'create_reminder', 'complete_reminder', or 'delete_reminder'."
                        ],
                        "daysAhead": [
                            "type": "NUMBER",
                            "description": "For 'list': days into the future (0-30). Default 0."
                        ],
                        "daysBack": [
                            "type": "NUMBER",
                            "description": "For 'list': days into the past (0-30). Default 0."
                        ],
                        "query": [
                            "type": "STRING",
                            "description": "For 'list' or 'list_reminders': filter by text."
                        ],
                        "title": [
                            "type": "STRING",
                            "description": "For 'create': event title (required)."
                        ],
                        "startDate": [
                            "type": "STRING",
                            "description": "For 'create': start date/time in 'yyyy-MM-dd HH:mm' format (required). For 'create_reminder': the due date."
                        ],
                        "endDate": [
                            "type": "STRING",
                            "description": "For 'create': end date/time. Defaults to 1 hour after start."
                        ],
                        "allDay": [
                            "type": "BOOLEAN",
                            "description": "For 'create': true for all-day events."
                        ],
                        "location": [
                            "type": "STRING",
                            "description": "For 'create': event location."
                        ],
                        "notes": [
                            "type": "STRING",
                            "description": "For 'create': event notes/description."
                        ],
                        "calendarName": [
                            "type": "STRING",
                            "description": "For 'create': target calendar name. Defaults to the user's default calendar."
                        ],
                        "eventId": [
                            "type": "STRING",
                            "description": "For 'delete': the event ID from 'list' results."
                        ],
                        "alertMinutesBefore": [
                            "type": "NUMBER",
                            "description": "For 'create': minutes before the event to show a notification. For 'create_reminder': defaults to 0 (alert fires at the due time). Only set a non-zero value if the user explicitly asks to be reminded BEFORE the due time."
                        ],
                        "reminderList": [
                            "type": "STRING",
                            "description": "For 'create_reminder' or 'list_reminders': target reminder list name (e.g., 'Groceries', 'Inbox'). Defaults to default list."
                        ],
                        "isCompleted": [
                            "type": "BOOLEAN",
                            "description": "For 'list_reminders': true to show completed, false for pending (default)."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.clipboard) {
            decls.append([
                "name": GeminiLiveToolName.clipboard,
                "description": """
                Read or write the macOS system clipboard, or copy file references to it.
                Actions:
                - "read": Return the current clipboard text.
                - "write": Copy plain text to the clipboard.
                - "copy-file": Copy one or more file path references to the clipboard.
                Treat clipboard content as potentially sensitive.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'read', 'write', or 'copy-file'."
                        ],
                        "text": [
                            "type": "STRING",
                            "description": "For 'write': the text to copy to the clipboard."
                        ],
                        "paths": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"],
                            "description": "For 'copy-file': one or more file paths to copy as file references."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.appControl) {
            decls.append([
                "name": GeminiLiveToolName.appControl,
                "description": """
                Control macOS applications: open, quit, or check running state.
                Actions:
                - "open": Launch an app by name.
                - "quit": Quit an app by name.
                - "check": Check whether an app is currently running.
                Use exact app names like Safari, Spotify, Notes. Do not use this for opening URLs or websites.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'open', 'quit', or 'check'."
                        ],
                        "appName": [
                            "type": "STRING",
                            "description": "The exact macOS application name, e.g. 'Safari', 'Spotify', 'Notes'."
                        ],
                    ],
                    "required": ["action", "appName"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.mediaControl) {
            decls.append([
                "name": GeminiLiveToolName.mediaControl,
                "description": """
                Control media playback and system volume on the user's Mac.
                Playback actions: play, pause, toggle, next, previous, stop, skip-forward, skip-backward, open.
                Volume actions: volume-get, volume-set (0–100 only; do not use mute).
                Use 'status' to check what is currently playing (title, artist, album, playing state, volume).
                All actions return the current media state after execution.
                If no supported media app is running, say so clearly instead of guessing.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'status', 'play', 'pause', 'toggle', 'next', 'previous', 'stop', 'skip-forward', 'skip-backward', 'open', 'volume-get', 'volume-set'."
                        ],
                        "volumeLevel": [
                            "type": "NUMBER",
                            "description": "For 'volume-set': volume level 0-100 (e.g. 100 for maximum, 50 for half)."
                        ],
                        "skipSeconds": [
                            "type": "NUMBER",
                            "description": "For 'skip-forward'/'skip-backward': number of seconds to skip (e.g. 30)."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }

        if enabledTools.contains(.pomodoro) {
            decls.append([
                "name": GeminiLiveToolName.pomodoro,
                "description": """
                Control the Notch Pomodoro timer: start, pause, resume, reset, skip phase, check status.
                Use 'status' to query the current timer state.
                When the user asks to stop, end, cancel, or terminate a focus session, use the 'reset' action.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'status', 'start', 'pause', 'resume', 'reset', 'skip'. Use 'reset' when the user asks to stop, end, cancel, or terminate the active focus session."
                        ],
                        "focusDuration": [
                            "type": "STRING",
                            "description": "Focus duration, e.g. '25m' or '50m'. For 'start'."
                        ],
                        "breakDuration": [
                            "type": "STRING",
                            "description": "Short break duration, e.g. '5m'. For 'start'."
                        ],
                        "longBreakDuration": [
                            "type": "STRING",
                            "description": "Long break duration, e.g. '15m'. For 'start'."
                        ],
                        "cycleCount": [
                            "type": "NUMBER",
                            "description": "Number of focus sessions before a long break, e.g. 4. For 'start'."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.memory) {
            decls.append([
                "name": GeminiLiveToolName.memory,
                "description": """
                Read or write persistent memory files for long-term context.
                - "read-user": Read USER.md (stable identity: name, pronouns, role, preferences).
                - "read-memory": Read MEMORY.md (durable facts, preferences, habits).
                - "write-user": Overwrite USER.md with updated profile content.
                - "write-memory": Overwrite MEMORY.md with updated memory content.
                Use "write-user" when the user shares or corrects identity details. Use "write-memory" for broader long-term notes. Do not save temporary chatter or sensitive data.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'read-user', 'read-memory', 'write-user', or 'write-memory'."
                        ],
                        "content": [
                            "type": "STRING",
                            "description": "For 'write-user' or 'write-memory': the full file content to save."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        return decls
    }

    var liveSetupTools: [[String: Any]] {
        var tools: [[String: Any]] = []

        if enabledTools.contains(.webSearch) {
            tools.append([
                "google_search": [:]
            ])
        }

        if !enabledToolDeclarations.isEmpty {
            tools.append([
                "functionDeclarations": enabledToolDeclarations
            ])
        }

        return tools
    }

}
