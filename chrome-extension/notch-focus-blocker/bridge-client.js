/**
 * bridge-client.js
 *
 * Owns the WebSocket connection to the Notch macOS bridge inside the service
 * worker.  Chrome 116+ supports WebSocket in service workers natively, so no
 * offscreen document is needed.
 *
 * Public API (module-level functions):
 *   connectBridge(url, handlers)   — open / reconnect
 *   reconnectBridge()              — force-close and re-open with same url
 *   sendBridgeMessage(obj)         — JSON-serialize and send a WS frame
 *   isBridgeConnected()            — synchronous connected check
 *   onKeepaliveAlarm()             — called by the alarm every 20 s
 *   disconnectBridge()             — close cleanly (no reconnect)
 */

/** @type {WebSocket | null} */
let ws = null;
/** @type {ReturnType<typeof setTimeout> | null} */
let reconnectTimer = null;
let reconnectDelay = 500; // ms, doubles up to MAX_RECONNECT_DELAY
const MAX_RECONNECT_DELAY = 5000;

let activeUrl = "";
/** @type {{ onOpen: Function, onMessage: Function, onClose: Function } | null} */
let activeHandlers = null;

const KEEPALIVE_MSG = JSON.stringify({ type: "bridge-keepalive" });

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Open a WebSocket connection to `url`.
 * `handlers.onOpen()`, `handlers.onMessage(parsed)`, `handlers.onClose()` will
 * be called on the appropriate WS events.
 *
 * Idempotent: if already connected to the same URL, does nothing.
 * If `forceReconnect` is true, closes and re-opens even if already connected.
 */
export function connectBridge(url, handlers, { forceReconnect = false } = {}) {
  activeHandlers = handlers;

  const urlChanged = activeUrl && activeUrl !== url;
  if (forceReconnect || urlChanged) {
    _teardown(/* scheduleReconnect= */ false);
  }

  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }

  activeUrl = url;
  _open();
}

/**
 * Force-close the current socket and immediately reconnect to the active URL.
 */
export function reconnectBridge() {
  _teardown(/* scheduleReconnect= */ false);
  _open();
}

/**
 * JSON-serialize `obj` and send it as a WebSocket text frame.
 * Returns false if the socket is not open.
 */
export function sendBridgeMessage(obj) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return false;
  try {
    ws.send(JSON.stringify(obj));
    return true;
  } catch {
    return false;
  }
}

/** Returns true if the WebSocket is currently open. */
export function isBridgeConnected() {
  return ws !== null && ws.readyState === WebSocket.OPEN;
}

/**
 * Called by the `notch-bridge-keepalive` alarm (every 20 s).
 * Sends a keepalive ping if connected, or attempts reconnect if not.
 */
export function onKeepaliveAlarm() {
  if (ws && ws.readyState === WebSocket.OPEN) {
    try { ws.send(KEEPALIVE_MSG); } catch { /* ignore */ }
  } else if (!reconnectTimer && activeUrl) {
    _open();
  }
}

/**
 * Close the WebSocket cleanly.  Does not schedule a reconnect.
 */
export function disconnectBridge() {
  _teardown(/* scheduleReconnect= */ false);
  activeUrl = "";
  activeHandlers = null;
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function _open() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  if (!activeUrl) return;

  try {
    ws = new WebSocket(activeUrl);
  } catch (err) {
    console.error("[notch] WebSocket construction failed:", err);
    _scheduleReconnect();
    return;
  }

  ws.onopen = () => {
    reconnectDelay = 500;
    console.log("[notch] Bridge connected to", activeUrl);
    activeHandlers?.onOpen();
  };

  ws.onmessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch { return; }
    if (!msg) return;
    activeHandlers?.onMessage(msg);
  };

  ws.onclose = () => {
    ws = null;
    console.log("[notch] Bridge disconnected");
    activeHandlers?.onClose();
    _scheduleReconnect();
  };

  ws.onerror = () => {
    // onerror is always followed by onclose; let onclose handle reconnect.
    try { ws?.close(); } catch { /* ignore */ }
  };
}

function _teardown(scheduleReconnect) {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (ws) {
    ws.onclose = null; // prevent onclose from firing and double-scheduling
    try { ws.close(); } catch { /* ignore */ }
    ws = null;
  }
  if (scheduleReconnect) {
    _scheduleReconnect();
  }
}

function _scheduleReconnect() {
  if (reconnectTimer || !activeUrl) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    _open();
  }, reconnectDelay);
  reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY);
}
