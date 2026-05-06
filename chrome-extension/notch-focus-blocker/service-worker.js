/**
 * service-worker.js  — wiring only
 *
 * Wires together bridge-client.js, focus-state-store.js, and
 * browser-commands.js.  Contains no direct state management, tab logic,
 * or WebSocket frame handling.
 *
 * Requires Chrome 116+ (service-worker WebSocket + ES module support).
 */

import * as BridgeClient from "./bridge-client.js";
import * as Store from "./focus-state-store.js";
import * as BrowserCommands from "./browser-commands.js";

// ── Alarm names ───────────────────────────────────────────────────────────────

const ALARM_KEEPALIVE = "notch-bridge-keepalive"; // fires every 20 s
const ALARM_HEAL = "notch-focus-heal";             // fires every 60 s

// ── Lifecycle ─────────────────────────────────────────────────────────────────

chrome.runtime.onInstalled.addListener(async () => {
  await _startup();
});

chrome.runtime.onStartup.addListener(async () => {
  await _startup();
});

async function _startup() {
  const state = await Store.loadPersistedState();
  _scheduleAlarms();
  BridgeClient.connectBridge(state.apiBaseUrl, _bridgeHandlers);
}

function _scheduleAlarms() {
  // 20 s keepalive — prevents the socket from going idle.
  chrome.alarms.create(ALARM_KEEPALIVE, { periodInMinutes: 20 / 60 });
  // 60 s heal — re-connects if the worker woke up without a live socket.
  chrome.alarms.create(ALARM_HEAL, { periodInMinutes: 1 });
}

// ── Alarm handler ─────────────────────────────────────────────────────────────

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_KEEPALIVE) {
    BridgeClient.onKeepaliveAlarm();
    return;
  }
  if (alarm.name === ALARM_HEAL) {
    if (!BridgeClient.isBridgeConnected()) {
      const { apiBaseUrl } = Store.getState();
      BridgeClient.connectBridge(apiBaseUrl, _bridgeHandlers);
    }
  }
});

// ── Bridge event handlers ─────────────────────────────────────────────────────

const _bridgeHandlers = {
  onOpen() {
    const state = Store.applyBridgeStatus(true);
    Store.persistState();
    // Push current focus state immediately so the extension doesn't poll.
    BridgeClient.sendBridgeMessage({ ...state, type: "focus-state" });
  },

  onClose() {
    Store.applyBridgeStatus(false);
    Store.persistState();
  },

  async onMessage(msg) {
    const type = msg?.type;

    switch (type) {
      case "focus-state": {
        const { state, previousFocusActive, previousHasActiveSession } =
          Store.applyFocusStatePush(msg);
        await Store.persistState();

        if (!previousHasActiveSession && state.hasActiveSession) {
          await BrowserCommands.openAutoUrls(state.autoOpenUrls);
        }
        if (previousFocusActive && !state.focusActive) {
          await BrowserCommands.releaseBlockedTabs();
        }
        if (state.focusActive) {
          await BrowserCommands.enforceAcrossTabs(state);
        }
        break;
      }

      case "browser-command": {
        // Command must have an id; unknown commands without id are silently dropped.
        const command = msg;
        if (!command.id) {
          console.warn("[notch] Received browser-command with no id — ignored");
          break;
        }
        let result;
        try {
          result = await BrowserCommands.executeBrowserCommand(command);
        } catch (error) {
          result = {
            id: command.id,
            success: false,
            result: {},
            errorMessage: error instanceof Error ? error.message : String(error)
          };
        }
        BridgeClient.sendBridgeMessage({ type: "browser-command-result", ...result });
        break;
      }

      case "bridge-keepalive":
        // No-op; just keeps the connection alive.
        break;

      default:
        if (type !== undefined) {
          console.log("[notch] Unrecognised message type ignored:", type);
        }
        break;
    }
  }
};

// ── Tab event listeners ───────────────────────────────────────────────────────

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  const state = Store.getState();
  if (changeInfo.url) {
    await BrowserCommands.maybeBlockTab(tabId, changeInfo.url, state);
    return;
  }
  if (changeInfo.status === "complete" && tab.url) {
    await BrowserCommands.maybeBlockTab(tabId, tab.url, state);
  }
});

chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (tab?.url) {
    await BrowserCommands.maybeBlockTab(tabId, tab.url, Store.getState());
  }
});

// ── Storage change listener ───────────────────────────────────────────────────

chrome.storage.onChanged.addListener(async (changes, areaName) => {
  if (areaName !== "local" || !changes.apiBaseUrl) return;
  const state = Store.applyUrlChange(changes.apiBaseUrl.newValue);
  await Store.persistState();
  BridgeClient.connectBridge(state.apiBaseUrl, _bridgeHandlers, { forceReconnect: true });
});

// ── chrome.runtime.onMessage (popup / options communication) ──────────────────

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  (async () => {
    switch (message?.type) {
      case "get-state":
        sendResponse({ ok: true, state: Store.getState() });
        break;

      case "get-bridge-url":
        sendResponse({ ok: true, bridgeUrl: Store.getState().apiBaseUrl });
        break;

      case "refresh-state": {
        const { apiBaseUrl } = Store.getState();
        BridgeClient.connectBridge(apiBaseUrl, _bridgeHandlers, { forceReconnect: true });
        sendResponse({ ok: true, state: Store.getState() });
        break;
      }

      case "save-api-base-url": {
        const state = Store.applyUrlChange(message.value);
        await chrome.storage.local.set({
          apiBaseUrl: state.apiBaseUrl,
          lastFocusState: state
        });
        BridgeClient.connectBridge(state.apiBaseUrl, _bridgeHandlers, { forceReconnect: true });
        sendResponse({ ok: true, state });
        break;
      }

      default:
        sendResponse({ ok: false, error: "Unsupported message." });
        break;
    }
  })();

  return true; // keep message channel open for async response
});
