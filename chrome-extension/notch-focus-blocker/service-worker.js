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
  allowedHosts: [],
  autoOpenUrls: [],
  updatedAt: null,
  checkedAt: null,
  error: null
};

let pollInterval = null;

function ensureFastPolling() {
  if (!pollInterval) {
    pollInterval = setInterval(() => {
      refreshFocusState({ enforce: true });
    }, 1000);
  }
}

chrome.runtime.onInstalled.addListener(async () => {
  await ensureDefaults();
  schedulePolling();
  ensureFastPolling();
  await refreshFocusState({ enforce: true });
});

chrome.runtime.onStartup.addListener(async () => {
  await ensureDefaults();
  schedulePolling();
  ensureFastPolling();
  await refreshFocusState({ enforce: true });
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  ensureFastPolling();
  if (alarm.name !== POLL_ALARM_NAME) {
    return;
  }

  await refreshFocusState({ enforce: true });
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  ensureFastPolling();
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
  ensureFastPolling();
  await refreshFocusState({ enforce: false });
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (tab?.url) {
    await maybeBlockTab(tabId, tab.url);
  }
});

chrome.windows.onFocusChanged.addListener(async () => {
  ensureFastPolling();
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
  const previousHasActiveSession = focusState.hasActiveSession;

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
      allowedHosts: Array.isArray(payload.allowedHosts) ? payload.allowedHosts : [],
      autoOpenUrls: Array.isArray(payload.autoOpenUrls) ? payload.autoOpenUrls : [],
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
      allowedHosts: [],
      autoOpenUrls: [],
      checkedAt: new Date().toISOString(),
      error: error instanceof Error ? error.message : String(error)
    };
  }

  await chrome.storage.local.set({ lastFocusState: focusState });

  // Detect fresh start: hasActiveSession went from false to true
  if (!previousHasActiveSession && focusState.hasActiveSession) {
    await openAutoUrls();
  }

  if (previousFocusActive && !focusState.focusActive) {
    await releaseBlockedTabs();
  }

  if (!enforce) {
    return focusState;
  }

  if (focusState.focusActive) {
    await enforceAcrossTabs();
  }

  return focusState;
}

async function openAutoUrls() {
  const urls = focusState.autoOpenUrls;
  if (!urls.length) return;

  for (const url of urls) {
    const trimmed = url.trim();
    if (!trimmed) continue;
    const fullUrl = trimmed.startsWith("http://") || trimmed.startsWith("https://")
      ? trimmed
      : `https://${trimmed}`;
    await chrome.tabs.create({ url: fullUrl, active: true }).catch(() => null);
  }
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
    if (!tab.id || !isHttpUrl(tab.url)) {
      continue;
    }

    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => {
        const overlay = document.getElementById('notch-focus-blocker-overlay');
        if (overlay) {
          overlay.remove();
        }
        if (document.body) {
          document.body.style.removeProperty('overflow');
        }
      }
    }).catch(() => null);
  }
}

async function maybeBlockTab(tabId, url) {
  if (!focusState.focusActive || !focusState.connected || !isHttpUrl(url)) {
    return;
  }

  const hostname = parseHostname(url);
  if (!hostname || !isBlockedHost(hostname, focusState.blockedHosts, focusState.allowedHosts)) {
    return;
  }

  const iconUrl = chrome.runtime.getURL("icons/icon128.png");

  await chrome.scripting.executeScript({
    target: { tabId },
    func: (iconUrl) => {
      if (document.getElementById('notch-focus-blocker-overlay')) {
        return;
      }
      
      document.querySelectorAll('video, audio').forEach(media => media.pause());

      const overlay = document.createElement('div');
      overlay.id = 'notch-focus-blocker-overlay';
      overlay.style.cssText = `
        position: fixed !important;
        top: 0 !important;
        left: 0 !important;
        width: 100vw !important;
        height: 100vh !important;
        background: rgba(255, 255, 255, 0.75) !important;
        backdrop-filter: blur(24px) saturate(180%) !important;
        -webkit-backdrop-filter: blur(24px) saturate(180%) !important;
        z-index: 2147483647 !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
        justify-content: center !important;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
        color: #1d1d1f !important;
      `;

      const img = document.createElement('img');
      img.src = iconUrl;
      img.style.cssText = `
        width: 120px !important;
        height: 120px !important;
        margin-bottom: 24px !important;
        border-radius: 24px !important;
        box-shadow: 0 8px 32px rgba(0,0,0,0.12) !important;
      `;

      const title = document.createElement('h1');
      title.textContent = 'Oops! 🙈';
      title.style.cssText = `
        font-size: 32px !important;
        font-weight: 700 !important;
        margin: 0 0 12px 0 !important;
        letter-spacing: -0.5px !important;
      `;

      const subtitle = document.createElement('p');
      subtitle.textContent = "You're in a focus session right now. Keep up the great work! ✨";
      subtitle.style.cssText = `
        font-size: 18px !important;
        font-weight: 400 !important;
        margin: 0 !important;
        color: #86868b !important;
      `;

      overlay.appendChild(img);
      overlay.appendChild(title);
      overlay.appendChild(subtitle);
      
      if (document.body) {
        document.body.style.setProperty('overflow', 'hidden', 'important');
      }
      document.documentElement.appendChild(overlay);
    },
    args: [iconUrl]
  }).catch(() => null);
}

function isBlockedHost(hostname, blockedHosts, allowlist = []) {
  if (allowlist.some(rule => {
    const normalized = rule.trim().toLowerCase();
    return normalized && (hostname === normalized || hostname.endsWith(`.${normalized}`));
  })) {
    return false;
  }

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
