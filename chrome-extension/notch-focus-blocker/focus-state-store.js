/**
 * focus-state-store.js
 *
 * Pure state reducer and persistence layer for the extension focus state.
 * No direct tab or socket side-effects — callers decide what to do with the
 * returned state.
 *
 * Public API:
 *   loadPersistedState()          — populate from chrome.storage.local
 *   getState()                    — return a copy of current state
 *   applyFocusStatePush(payload)  — update from a focus-state socket message
 *   applyBridgeStatus(connected)  — update connected flag
 *   applyUrlChange(newUrl)        — update bridge URL (resets connection)
 *   persistState()                — write current state to chrome.storage.local
 *   sanitizeBridgeUrl(value)      — normalize a bridge URL string
 */

const DEFAULT_BRIDGE_URL = "ws://127.0.0.1:44991/v1/ws";

let focusState = {
  apiBaseUrl: DEFAULT_BRIDGE_URL,
  connected: false,
  bridgeVersion: null,
  focusActive: false,
  isRunning: false,
  hasActiveSession: false,
  phase: "Focus",
  remainingSeconds: 0,
  blockedHosts: [],
  allowedHosts: [],
  accessMode: "allowAllExceptBlocked",
  autoOpenUrls: [],
  updatedAt: null,
  checkedAt: null,
  error: null
};

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Load the persisted state from storage and merge it into the in-memory store.
 * Returns the loaded state.
 */
export async function loadPersistedState() {
  const stored = await chrome.storage.local.get({
    apiBaseUrl: DEFAULT_BRIDGE_URL,
    lastFocusState: null
  });

  if (!stored.apiBaseUrl) {
    await chrome.storage.local.set({ apiBaseUrl: DEFAULT_BRIDGE_URL });
  }

  if (stored.lastFocusState) {
    focusState = { ...focusState, ...stored.lastFocusState };
  }

  // Always ensure apiBaseUrl is sane after a load.
  focusState.apiBaseUrl = sanitizeBridgeUrl(stored.apiBaseUrl || focusState.apiBaseUrl);

  return getState();
}

/** Return a shallow copy of the current state. */
export function getState() {
  return { ...focusState };
}

/**
 * Apply a `focus-state` socket message payload.
 * Returns `{ state, previousFocusActive, previousHasActiveSession }` so the
 * caller can decide which tab side-effects to trigger.
 */
export function applyFocusStatePush(payload) {
  const previousFocusActive = focusState.focusActive;
  const previousHasActiveSession = focusState.hasActiveSession;

  focusState = {
    ...focusState,
    connected: true,
    bridgeVersion:
      payload.bridgeVersion != null && payload.bridgeVersion !== ""
        ? String(payload.bridgeVersion)
        : focusState.bridgeVersion,
    focusActive: Boolean(payload.focusActive),
    isRunning: Boolean(payload.isRunning),
    hasActiveSession: Boolean(payload.hasActiveSession),
    phase: payload.phase || "Focus",
    remainingSeconds: payload.remainingSeconds || 0,
    blockedHosts: Array.isArray(payload.blockedHosts) ? payload.blockedHosts : [],
    allowedHosts: Array.isArray(payload.allowedHosts) ? payload.allowedHosts : [],
    accessMode: normalizeAccessMode(payload.accessMode),
    autoOpenUrls: Array.isArray(payload.autoOpenUrls) ? payload.autoOpenUrls : [],
    updatedAt: payload.updatedAt || null,
    checkedAt: new Date().toISOString(),
    error: null
  };

  return { state: getState(), previousFocusActive, previousHasActiveSession };
}

/**
 * Mark the bridge connection as connected or disconnected.
 * Returns the new state.
 */
export function applyBridgeStatus(connected) {
  focusState = {
    ...focusState,
    connected: Boolean(connected),
    checkedAt: new Date().toISOString(),
    error: connected ? null : focusState.error
  };
  return getState();
}

/**
 * Apply a bridge URL change (from options page or storage.onChanged).
 * Resets `connected` so the caller knows to reconnect.
 * Returns the new state.
 */
export function applyUrlChange(newUrl) {
  focusState = {
    ...focusState,
    apiBaseUrl: sanitizeBridgeUrl(newUrl),
    connected: false,
    checkedAt: new Date().toISOString()
  };
  return getState();
}

/** Write the current state to chrome.storage.local. */
export async function persistState() {
  await chrome.storage.local.set({ lastFocusState: focusState });
}

/**
 * Normalize a raw bridge URL string.  Accepts http/https/ws/wss and bare
 * hostnames; always returns a valid ws:// or wss:// URL ending in /v1/ws.
 */
function normalizeAccessMode(value) {
  return value === "blockAllExceptAllowed" ? "blockAllExceptAllowed" : "allowAllExceptBlocked";
}

export function sanitizeBridgeUrl(value) {
  if (typeof value !== "string" || !value.trim()) {
    return DEFAULT_BRIDGE_URL;
  }

  let normalized = value.trim().replace(/\/+$/, "");
  if (normalized.startsWith("http://") || normalized.startsWith("https://")) {
    normalized = normalized.replace(/^http/i, "ws");
  }
  if (!normalized.startsWith("ws://") && !normalized.startsWith("wss://")) {
    normalized = `ws://${normalized}`;
  }
  if (!normalized.endsWith("/v1/ws") && !normalized.endsWith("/ws")) {
    normalized = `${normalized}/v1/ws`;
  }
  return normalized;
}

export { DEFAULT_BRIDGE_URL };
