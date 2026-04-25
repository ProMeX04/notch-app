const DEFAULT_API_BASE_URL = "http://127.0.0.1:44991";
const FOCUS_STATE_PATH = "/v1/focus-state";
const POLL_ALARM_NAME = "notch-focus-state-poll";
const BLOCK_PAGE_PATH = "blocked.html";

let focusState = {
  apiBaseUrl: DEFAULT_API_BASE_URL,
  connected: false,
  focusActive: false,
  isRunning: false,
  hasActiveSession: false,
  phase: "Focus",
  remainingSeconds: 0,
  blockedHosts: [],
  updatedAt: null,
  checkedAt: null,
  error: null
};

chrome.runtime.onInstalled.addListener(async () => {
  await ensureDefaults();
  schedulePolling();
  await refreshFocusState({ enforce: true });
});

chrome.runtime.onStartup.addListener(async () => {
  await ensureDefaults();
  schedulePolling();
  await refreshFocusState({ enforce: true });
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== POLL_ALARM_NAME) {
    return;
  }

  await refreshFocusState({ enforce: true });
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (changeInfo.url) {
    await refreshFocusState({ enforce: false });
    await maybeBlockTab(tabId, changeInfo.url);
    return;
  }

  if (changeInfo.status === "complete" && tab.url) {
    await maybeBlockTab(tabId, tab.url);
  }
});

chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  await refreshFocusState({ enforce: false });
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (tab?.url) {
    await maybeBlockTab(tabId, tab.url);
  }
});

chrome.windows.onFocusChanged.addListener(async () => {
  await refreshFocusState({ enforce: false });
});

chrome.storage.onChanged.addListener(async (changes, areaName) => {
  if (areaName !== "local" || !changes.apiBaseUrl) {
    return;
  }

  await refreshFocusState({ enforce: true });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    switch (message?.type) {
      case "get-state":
        sendResponse({ ok: true, state: focusState });
        break;
      case "refresh-state":
        await refreshFocusState({ enforce: true });
        sendResponse({ ok: true, state: focusState });
        break;
      case "save-api-base-url":
        await chrome.storage.local.set({ apiBaseUrl: sanitizeApiBaseUrl(message.value) });
        await refreshFocusState({ enforce: true });
        sendResponse({ ok: true, state: focusState });
        break;
      default:
        sendResponse({ ok: false, error: "Unsupported message." });
        break;
    }
  })();

  return true;
});

async function ensureDefaults() {
  const stored = await chrome.storage.local.get({
    apiBaseUrl: DEFAULT_API_BASE_URL,
    lastFocusState: null
  });

  if (!stored.apiBaseUrl) {
    await chrome.storage.local.set({ apiBaseUrl: DEFAULT_API_BASE_URL });
  }

  if (stored.lastFocusState) {
    focusState = { ...focusState, ...stored.lastFocusState };
  }
}

function schedulePolling() {
  chrome.alarms.create(POLL_ALARM_NAME, { periodInMinutes: 0.5 });
}

async function refreshFocusState({ enforce } = { enforce: false }) {
  const { apiBaseUrl = DEFAULT_API_BASE_URL } = await chrome.storage.local.get({
    apiBaseUrl: DEFAULT_API_BASE_URL
  });
  const previousFocusActive = focusState.focusActive;

  try {
    const response = await fetch(`${sanitizeApiBaseUrl(apiBaseUrl)}${FOCUS_STATE_PATH}`, {
      cache: "no-store"
    });

    if (!response.ok) {
      throw new Error(`Bridge returned ${response.status}`);
    }

    const payload = await response.json();
    focusState = {
      apiBaseUrl: sanitizeApiBaseUrl(apiBaseUrl),
      connected: true,
      focusActive: Boolean(payload.focusActive),
      isRunning: Boolean(payload.isRunning),
      hasActiveSession: Boolean(payload.hasActiveSession),
      phase: payload.phase || "Focus",
      remainingSeconds: payload.remainingSeconds || 0,
      blockedHosts: Array.isArray(payload.blockedHosts) ? payload.blockedHosts : [],
      updatedAt: payload.updatedAt || null,
      checkedAt: new Date().toISOString(),
      error: null
    };
  } catch (error) {
    focusState = {
      ...focusState,
      apiBaseUrl: sanitizeApiBaseUrl(apiBaseUrl),
      connected: false,
      focusActive: false,
      isRunning: false,
      hasActiveSession: false,
      remainingSeconds: 0,
      blockedHosts: [],
      checkedAt: new Date().toISOString(),
      error: error instanceof Error ? error.message : String(error)
    };
  }

  await chrome.storage.local.set({ lastFocusState: focusState });

  if (!enforce) {
    return focusState;
  }

  if (previousFocusActive && !focusState.focusActive) {
    await releaseBlockedTabs();
    return focusState;
  }

  if (focusState.focusActive) {
    await enforceAcrossTabs();
  }

  return focusState;
}

async function enforceAcrossTabs() {
  const tabs = await chrome.tabs.query({});

  for (const tab of tabs) {
    if (!tab.id || !tab.url) {
      continue;
    }

    await maybeBlockTab(tab.id, tab.url);
  }
}

async function releaseBlockedTabs() {
  const tabs = await chrome.tabs.query({});

  for (const tab of tabs) {
    if (!tab.id || !isBlockPageUrl(tab.url)) {
      continue;
    }

    const originalUrl = extractOriginalUrl(tab.url);
    if (!originalUrl) {
      continue;
    }

    await chrome.tabs.update(tab.id, { url: originalUrl }).catch(() => null);
  }
}

async function maybeBlockTab(tabId, url) {
  if (!focusState.focusActive || !focusState.connected || isBlockPageUrl(url) || !isHttpUrl(url)) {
    return;
  }

  const hostname = parseHostname(url);
  if (!hostname || !isBlockedHost(hostname, focusState.blockedHosts)) {
    return;
  }

  const redirectUrl = buildBlockedPageUrl(url, hostname);
  await chrome.tabs.update(tabId, { url: redirectUrl }).catch(() => null);
}

function isBlockedHost(hostname, blockedHosts) {
  return blockedHosts.some((rule) => {
    const normalizedRule = normalizeHostRule(rule);
    if (!normalizedRule) {
      return false;
    }

    return hostname === normalizedRule || hostname.endsWith(`.${normalizedRule}`);
  });
}

function normalizeHostRule(rule) {
  if (typeof rule !== "string") {
    return null;
  }

  return rule.trim().replace(/^\*\./, "").replace(/\.+$/, "").toLowerCase() || null;
}

function parseHostname(url) {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function isHttpUrl(url) {
  return typeof url === "string" && (url.startsWith("http://") || url.startsWith("https://"));
}

function buildBlockedPageUrl(originalUrl, hostname) {
  const params = new URLSearchParams({
    url: originalUrl,
    host: hostname
  });
  return chrome.runtime.getURL(`${BLOCK_PAGE_PATH}?${params.toString()}`);
}

function isBlockPageUrl(url) {
  return typeof url === "string" && url.startsWith(chrome.runtime.getURL(BLOCK_PAGE_PATH));
}

function extractOriginalUrl(blockPageUrl) {
  try {
    const parsed = new URL(blockPageUrl);
    return parsed.searchParams.get("url");
  } catch {
    return null;
  }
}

function sanitizeApiBaseUrl(value) {
  if (typeof value !== "string" || !value.trim()) {
    return DEFAULT_API_BASE_URL;
  }

  return value.trim().replace(/\/+$/, "");
}
