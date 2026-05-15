import Foundation
import NotchTooling

extension GeminiLiveSession {
    var enabledToolDeclarations: [[String: Any]] {
        var decls: [[String: Any]] = []
        if enabledTools.contains(.exec) {
            decls.append([
                "name": GeminiLiveToolName.exec,
                "description": "Run a local shell command on the user's Mac using zsh. Use this for command-line tools such as curl, jq, python3, or git. Commands run in ~/.notch/workspace by default unless a working directory is provided. New or untrusted commands may require approval. Prefer concise commands and read-only inspection unless the user clearly wants a change.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "command": [
                            "type": "STRING",
                            "description": "The exact shell command to run, for example: curl -s https://example.com"
                        ],
                        "workingDirectory": [
                            "type": "STRING",
                            "description": "Optional absolute path or ~/ path to run the command in. If omitted, Notch uses ~/.notch/workspace."
                        ],
                        "timeoutSeconds": [
                            "type": "NUMBER",
                            "description": "Optional timeout in seconds. Use 1-30. Defaults to 15."
                        ]
                    ],
                    "required": ["command"]
                ]
            ])
        }
        if enabledTools.contains(.read) {
            decls.append([
                "name": GeminiLiveToolName.read,
                "description": GeminiWorkspaceCodingTools.openClawReadToolDescription,
                "parameters": GeminiWorkspaceCodingTools.openClawReadToolParameters
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
        if enabledTools.contains(.browserControl) {
            decls.append([
                "name": GeminiLiveToolName.browserControl,
                "description": """
                Control the browser: open URLs, read tab content, navigate, manage tabs, and interact with page elements.
                Actions:
                - "open": Open a URL in the default browser.
                - "lucky": Open the top DuckDuckGo search result. 'youtube' is appended automatically for music queries.
                - "read-tab": Read the current tab's URL, title, and visible text.
                - "navigate": Navigate the current tab to a URL (stays in same tab).
                - "go-back": Go back in browser history.
                - "go-forward": Go forward in browser history.
                - "reload": Reload the current page.
                - "close-tab": Close a tab. IMPORTANT: Use 'tabId' for a specific tab from 'list-tabs' results. If no 'tabId' is provided, the current active tab is closed.
                - "list-tabs": List all tabs in the front window. Returns each tab's unique 'tabId', title, and URL.
                - "switch-tab": Switch to a tab. IMPORTANT: Prefer 'tabId' for reliability. Using 'index' (1-based) is supported but discouraged as indices shift when tabs are moved or closed.
                - "scroll": Scroll the page up or down by a pixel amount (Chrome/Edge: precise; Safari: page scroll).
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'open', 'lucky', 'read-tab', 'navigate', 'go-back', 'go-forward', 'reload', 'close-tab', 'list-tabs', 'switch-tab', or 'scroll'."
                        ],
                        "url": [
                            "type": "STRING",
                            "description": "For 'open', 'navigate': the URL."
                        ],
                        "query": [
                            "type": "STRING",
                            "description": "For 'lucky': the search query."
                        ],
                        "tabId": [
                            "type": "INTEGER",
                            "description": "The unique ID of the tab to target. Get this from 'list-tabs'. Highly recommended for 'close-tab', 'switch-tab', 'read-tab', and 'navigate'."
                        ],
                        "index": [
                            "type": "INTEGER",
                            "description": "For 'switch-tab': 1-based tab index. Discouraged, use 'tabId' instead."
                        ],
                        "direction": [
                            "type": "STRING",
                            "description": "For 'scroll': 'up' or 'down'. Defaults to 'down'."
                        ],
                        "amount": [
                            "type": "INTEGER",
                            "description": "For 'scroll': pixel amount to scroll. Defaults to 500."
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
        if enabledTools.contains(.localFileSearch) {
            decls.append([
                "name": GeminiLiveToolName.localFileSearch,
                "description": "Search indexed local files, folders, apps, and media on the user's Mac.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "query": [
                            "type": "STRING",
                            "description": "Search text."
                        ],
                        "limit": [
                            "type": "INTEGER",
                            "description": "Max results (default 10, max 50)."
                        ],
                        "scope": [
                            "type": "STRING",
                            "description": "Optional: 'home', 'documents', 'desktop', 'downloads', 'applications', or 'all'."
                        ],
                        "kind": [
                            "type": "STRING",
                            "description": "Optional: 'any', 'app', 'folder', 'document', 'image', 'pdf', 'audio', or 'video'."
                        ],
                    ],
                    "required": ["query"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.appleMail) {
            decls.append([
                "name": GeminiLiveToolName.appleMail,
                "description": """
                Search or list recent emails from Apple Mail.
                Actions:
                - "list_recent": List the most recent emails.
                - "search": Search for emails by keyword (sender name, email, subject, or snippet).
                - "read_content": Read the full body and metadata for a specific email when available; falls back to summary/snippet.
                Requires Full Disk Access to read the Mail database and message files.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'list_recent', 'search', or 'read_content'."
                        ],
                        "query": [
                            "type": "STRING",
                            "description": "For 'search': the search keyword."
                        ],
                        "limit": [
                            "type": "NUMBER",
                            "description": "Max number of results to return (default 10)."
                        ],
                        "messageId": [
                            "type": "STRING",
                            "description": "For 'read_content': required database ID of the message. Obtain it from 'search' or 'list_recent'."
                        ]
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.skillWriter) {
            decls.append([
                "name": GeminiLiveToolName.skillWriter,
                "description": """
                Proposes creating or updating a Notch Skill (instructions the model may read via the `read` tool). Writes only after validation and explicit user confirmation in Notch.

                Important:
                - This does not toggle macOS permissions or Gemini tools automatically.
                - Use sparingly — skills should be reusable playbooks rather than ephemeral chat transcripts.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Either \"create\" to add a new skill, or \"update\" to overwrite an existing one.",
                        ],
                        "skillId": [
                            "type": "STRING",
                            "description": "Required when action is \"update\": the SkillRecord id from the Skills list / prior tool responses.",
                        ],
                        "name": [
                            "type": "STRING",
                            "description": "Short skill title shown in Notch Settings.",
                        ],
                        "description": [
                            "type": "STRING",
                            "description": "One-line summary describing when to use this skill.",
                        ],
                        "instructions": [
                            "type": "STRING",
                            "description": "Markdown-friendly instructions loaded when this skill is read.",
                        ],
                    ],
                    "required": ["action", "name", "description", "instructions"],
                ] as [String: Any],
            ])
        }
        if enabledTools.contains(.showResult) {
            decls.append([
                "name": GeminiLiveToolName.showResult,
                "description": """
                Show one or more user-visible results (text summaries, clickable links, or local file attachments) in the Notch Results panel so the user can review, save, or act on them. Use after substantive work products: summaries, extracted data, diagrams described as exports, downloads, paths the user asked to open, etc. Each item has a kind: 'text' (plain Markdown or plain body), 'link' (https URL), or 'file' (absolute path readable on disk). Omit this tool only when no tangible output is meant for the tray.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "items": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "kind": [
                                        "type": "STRING",
                                        "description": "One of: 'text', 'link', 'file'.",
                                    ],
                                    "title": [
                                        "type": "STRING",
                                        "description": "Optional short headline for this item.",
                                    ],
                                    "content": [
                                        "type": "STRING",
                                        "description": "For 'text': body copy. For 'link': absolute http(s) URL. For 'file': absolute POSIX path (~ allowed).",
                                    ],
                                ]
                            ],
                            "description": "Non-empty ordered list of result payloads to append as one tray batch.",
                        ]
                    ],
                    "required": ["items"],
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
