/**
 * browser-commands.js
 *
 * Chrome tab automation.  Contains the full `executeBrowserCommand` switch
 * and all related helper utilities.
 *
 * Public API:
 *   executeBrowserCommand(command)  — execute one browser command; returns result object
 *
 * Tab enforcement helpers (used by service-worker.js):
 *   maybeBlockTab(tabId, url, focusState)
 *   enforceAcrossTabs(focusState)
 *   releaseBlockedTabs()
 *   openAutoUrls(urls)
 */

const BLOCK_PAGE_PATH = "blocked.html";

// ── Public: command dispatch ──────────────────────────────────────────────────

/**
 * Execute a browser command received from the bridge.
 * @param {{ id: string, action: string, args?: Record<string, any> }} command
 * @returns {Promise<{ id: string, success: boolean, result: object, errorMessage: string | null }>}
 */
export async function executeBrowserCommand(command) {
  const { id, action, args: rawArgs } = command;
  const args = rawArgs || {};
  const resultBase = { id, success: false, result: {}, errorMessage: null };

  try {
    switch (action) {
      case "open": {
        const url = ensureFullUrl(args.url);
        const tab = await chrome.tabs.create({ url, active: true });
        return { ...resultBase, success: true, result: { tabId: tab.id, url: tab.url || url } };
      }

      case "lucky": {
        const query = args.query || "";
        const searchUrl = `https://www.google.com/search?btnI=I%27m+Feeling+Lucky&q=${encodeURIComponent(query)}`;
        const tab = await chrome.tabs.create({ url: searchUrl, active: true });
        return { ...resultBase, success: true, result: { tabId: tab.id, url: searchUrl } };
      }

      case "read-tab": {
        const tabId = args.tabId ? Number(args.tabId) : null;
        const tab = tabId
          ? await chrome.tabs.get(tabId)
          : (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0];

        if (!tab) {
          return { ...resultBase, errorMessage: "No active tab found." };
        }

        let text = "";
        let screenshotData = "";

        const isSystemPage =
          tab.url?.startsWith("chrome://") ||
          tab.url?.startsWith("edge://") ||
          tab.url?.startsWith("about:");

        if (isSystemPage) {
          text = "(Internal browser page - content cannot be read for security reasons)";
        } else {
          try {
            const [injection] = await chrome.scripting.executeScript({
              target: { tabId: tab.id },
              func: () => document.body?.innerText?.substring(0, 8000) || ""
            });
            text = injection?.result || "";

            // Capture visible area as JPEG to keep size reasonable.
            screenshotData = await chrome.tabs.captureVisibleTab(tab.windowId, {
              format: "jpeg",
              quality: 50
            });
          } catch (e) {
            console.error("read-tab content access error:", e);
            text = "(Could not access page content)";
          }
        }

        const result = {
          title: tab.title || "",
          url: tab.url || "",
          tabId: tab.id,
          text
        };

        if (screenshotData) {
          // Wrap in contentBlocks so the Swift side knows it's an attachment.
          result.contentBlocks = [{
            type: "image",
            mimeType: "image/jpeg",
            data: screenshotData.split(",")[1], // strip data URL prefix
            displayName: `tab-${tab.id}-screenshot.jpg`
          }];
        }

        return { ...resultBase, success: true, result };
      }

      case "navigate": {
        const url = ensureFullUrl(args.url);
        const tabId = args.tabId ? Number(args.tabId) : null;
        let targetTabId = tabId;
        if (!targetTabId) {
          const [activeTab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
          targetTabId = activeTab?.id;
        }
        if (!targetTabId) return { ...resultBase, errorMessage: "No active tab to navigate." };
        const tab = await chrome.tabs.update(targetTabId, { url });
        return { ...resultBase, success: true, result: { tabId: tab.id, url } };
      }

      case "go-back": {
        const tabId = args.tabId ? Number(args.tabId) : null;
        let targetTabId = tabId;
        if (!targetTabId) {
          const [activeTab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
          targetTabId = activeTab?.id;
        }
        if (!targetTabId) return { ...resultBase, errorMessage: "No active tab." };
        await chrome.tabs.goBack(targetTabId);
        return { ...resultBase, success: true, result: { tabId: targetTabId } };
      }

      case "go-forward": {
        const tabId = args.tabId ? Number(args.tabId) : null;
        let targetTabId = tabId;
        if (!targetTabId) {
          const [activeTab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
          targetTabId = activeTab?.id;
        }
        if (!targetTabId) return { ...resultBase, errorMessage: "No active tab." };
        await chrome.tabs.goForward(targetTabId);
        return { ...resultBase, success: true, result: { tabId: targetTabId } };
      }

      case "reload": {
        const tabId = args.tabId ? Number(args.tabId) : null;
        let targetTabId = tabId;
        if (!targetTabId) {
          const [activeTab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
          targetTabId = activeTab?.id;
        }
        if (!targetTabId) return { ...resultBase, errorMessage: "No active tab." };
        await chrome.tabs.reload(targetTabId);
        return { ...resultBase, success: true, result: { tabId: targetTabId } };
      }

      case "close-tab": {
        const tabId = args.tabId ? Number(args.tabId) : null;
        if (!tabId) {
          const [activeTab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
          if (activeTab?.id) {
            await chrome.tabs.remove(activeTab.id);
            return { ...resultBase, success: true, result: { tabId: activeTab.id } };
          }
          return { ...resultBase, errorMessage: "Provide a specific tabId to close." };
        }
        await chrome.tabs.remove(tabId);
        return { ...resultBase, success: true, result: { tabId } };
      }

      case "list-tabs": {
        // Use lastFocusedWindow so this works even when Chrome is not the active app.
        let tabs = await chrome.tabs.query({ lastFocusedWindow: true });
        if (!tabs || tabs.length === 0) {
          tabs = await chrome.tabs.query({});
        }
        const list = tabs.map((t, i) => ({
          index: i + 1,
          tabId: t.id,
          windowId: t.windowId,
          title: t.title || "",
          url: t.url || "",
          active: t.active
        }));
        return { ...resultBase, success: true, result: { tabs: list, count: list.length } };
      }

      case "switch-tab": {
        const index = args.index != null ? Number(args.index) : null;
        const tabId = args.tabId ? Number(args.tabId) : null;

        if (tabId) {
          await chrome.tabs.update(tabId, { active: true });
          return { ...resultBase, success: true, result: { tabId } };
        }
        if (index != null) {
          const tabs = await chrome.tabs.query({ lastFocusedWindow: true });
          const target = tabs[index - 1];
          if (!target) return { ...resultBase, errorMessage: `Tab index ${index} out of range.` };
          await chrome.tabs.update(target.id, { active: true });
          return { ...resultBase, success: true, result: { tabId: target.id } };
        }
        return { ...resultBase, errorMessage: "Provide index or tabId." };
      }

      case "scroll": {
        const direction = args.direction || "down";
        const amount = Number(args.amount) || 500;
        const tabId = args.tabId ? Number(args.tabId) : null;
        let targetTabId = tabId;
        if (!targetTabId) {
          const [activeTab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
          targetTabId = activeTab?.id;
        }
        if (!targetTabId) return { ...resultBase, errorMessage: "No active tab." };
        await chrome.scripting.executeScript({
          target: { tabId: targetTabId },
          func: (dir, px) => { window.scrollBy({ top: dir === "up" ? -px : px, behavior: "smooth" }); },
          args: [direction, amount]
        });
        return { ...resultBase, success: true, result: { tabId: targetTabId, direction, amount } };
      }

      default:
        return { ...resultBase, errorMessage: `Unknown action: ${action}` };
    }
  } catch (error) {
    return {
      ...resultBase,
      errorMessage: error instanceof Error ? error.message : String(error)
    };
  }
}

// ── Public: tab enforcement helpers ──────────────────────────────────────────

/**
 * Block `tabId` if it navigates to a blocked hostname during an active focus
 * session.  No-ops if focus is inactive or the URL is not HTTP.
 */
export async function maybeBlockTab(tabId, url, focusState) {
  if (!focusState.focusActive || !focusState.connected || !isHttpUrl(url)) return;

  const hostname = parseHostname(url);
  if (!hostname || !isBlockedHost(hostname, focusState.blockedHosts, focusState.allowedHosts)) return;

  const iconUrl = chrome.runtime.getURL("icons/icon128.png");

  await chrome.scripting.executeScript({
    target: { tabId },
    func: (iconUrl) => {
      if (document.getElementById("notch-focus-blocker-overlay")) return;

      document.querySelectorAll("video, audio").forEach(media => media.pause());

      const overlay = document.createElement("div");
      overlay.id = "notch-focus-blocker-overlay";
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

      const img = document.createElement("img");
      img.src = iconUrl;
      img.style.cssText = `
        width: 120px !important;
        height: 120px !important;
        margin-bottom: 24px !important;
        border-radius: 24px !important;
        box-shadow: 0 8px 32px rgba(0,0,0,0.12) !important;
      `;

      const title = document.createElement("h1");
      title.textContent = "Oops! 🙈";
      title.style.cssText = `
        font-size: 32px !important;
        font-weight: 700 !important;
        margin: 0 0 12px 0 !important;
        letter-spacing: -0.5px !important;
      `;

      const subtitle = document.createElement("p");
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
        document.body.style.setProperty("overflow", "hidden", "important");
      }
      document.documentElement.appendChild(overlay);
    },
    args: [iconUrl]
  }).catch(() => null);
}

/** Block all currently open tabs that match the blocked host list. */
export async function enforceAcrossTabs(focusState) {
  const tabs = await chrome.tabs.query({});
  for (const tab of tabs) {
    if (!tab.id || !tab.url) continue;
    await maybeBlockTab(tab.id, tab.url, focusState);
  }
}

/** Remove the focus-blocker overlay from every tab. */
export async function releaseBlockedTabs() {
  const tabs = await chrome.tabs.query({});
  for (const tab of tabs) {
    if (!tab.id || !isHttpUrl(tab.url)) continue;
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => {
        const overlay = document.getElementById("notch-focus-blocker-overlay");
        if (overlay) overlay.remove();
        if (document.body) document.body.style.removeProperty("overflow");
      }
    }).catch(() => null);
  }
}

/** Open each URL in `urls` in a new tab. */
export async function openAutoUrls(urls) {
  if (!urls?.length) return;
  for (const url of urls) {
    const trimmed = url.trim();
    if (!trimmed) continue;
    const fullUrl = trimmed.startsWith("http://") || trimmed.startsWith("https://")
      ? trimmed
      : `https://${trimmed}`;
    await chrome.tabs.create({ url: fullUrl, active: true }).catch(() => null);
  }
}

// ── Internal utilities ────────────────────────────────────────────────────────

function ensureFullUrl(url) {
  if (!url) return "about:blank";
  const trimmed = url.trim();
  if (
    trimmed.startsWith("http://") ||
    trimmed.startsWith("https://") ||
    trimmed.startsWith("chrome://")
  ) {
    return trimmed;
  }
  return `https://${trimmed}`;
}

function isBlockedHost(hostname, blockedHosts, allowlist = []) {
  if (
    allowlist.some(rule => {
      const normalized = rule.trim().toLowerCase();
      return normalized && (hostname === normalized || hostname.endsWith(`.${normalized}`));
    })
  ) {
    return false;
  }
  return blockedHosts.some(rule => {
    const normalizedRule = normalizeHostRule(rule);
    if (!normalizedRule) return false;
    return hostname === normalizedRule || hostname.endsWith(`.${normalizedRule}`);
  });
}

function normalizeHostRule(rule) {
  if (typeof rule !== "string") return null;
  return rule.trim().replace(/^\*\./, "").replace(/\.+$/, "").toLowerCase() || null;
}

function parseHostname(url) {
  try { return new URL(url).hostname.toLowerCase(); } catch { return null; }
}

function isHttpUrl(url) {
  return typeof url === "string" && (url.startsWith("http://") || url.startsWith("https://"));
}
