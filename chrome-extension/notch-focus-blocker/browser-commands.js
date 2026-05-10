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
        const followResult = await followGoogleRedirectNotice(tab.id);
        return {
          ...resultBase,
          success: true,
          result: {
            tabId: tab.id,
            url: followResult.url || searchUrl,
            redirected: followResult.redirected
          }
        };
      }

      case "read-tab": {
        const tabId = args.tabId ? Number(args.tabId) : null;
        let tab = tabId
          ? await chrome.tabs.get(tabId)
          : (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0];

        if (!tab) {
          return { ...resultBase, errorMessage: "No active tab found." };
        }

        tab = await waitForTabLoaded(tab.id);

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

            // Focus Chrome + shutter flash *before* capture so the user sees it; overlay is gone before JPEG is taken.
            await bringTabToFront(tab.id, tab.windowId);
            await new Promise((r) => setTimeout(r, 80));
            console.log("[notch] read-tab: shutter flash starting on tab", tab.id);
            await awaitShutterFlash(tab.id);
            console.log("[notch] read-tab: shutter flash done, capturing");

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

/** Bring the tab + browser window forward so the shutter is visible (e.g. when triggered from Notch). */
async function bringTabToFront(tabId, windowId) {
  if (tabId != null) {
    try {
      await chrome.tabs.update(tabId, { active: true });
    } catch {
      /* ignore */
    }
  }
  if (windowId == null) return;
  try {
    await chrome.windows.update(windowId, { focused: true });
  } catch {
    /* ignore — missing windows permission or invalid id */
  }
}

/**
 * Subtle "screenshot taken" cue: a soft blue glow on the viewport edges.
 * No flash — just a brief inner border highlight then fade out.
 */
async function awaitShutterFlash(tabId) {
  if (tabId == null) return;
  try {
    const [res] = await chrome.scripting.executeScript({
      target: { tabId },
      world: "MAIN",
      func: () => {
        return new Promise((resolve) => {
          try {
            const ROOT_ID = "notch-bridge-shutter-root";
            document.getElementById(ROOT_ID)?.remove();

            const importantAll = (obj) =>
              Object.entries(obj)
                .map(([k, v]) => `${k}:${v} !important`)
                .join(";");

            const root = document.createElement("div");
            root.id = ROOT_ID;
            root.setAttribute("aria-hidden", "true");
            root.style.cssText = importantAll({
              position: "fixed",
              left: "0",
              top: "0",
              right: "0",
              bottom: "0",
              "z-index": "2147483647",
              "pointer-events": "none",
              overflow: "hidden",
              opacity: "1",
              transition: "opacity 720ms ease-out"
            });

            const border = document.createElement("div");
            border.style.cssText = importantAll({
              position: "absolute",
              left: "0",
              top: "0",
              right: "0",
              bottom: "0",
              "box-shadow":
                "inset 0 0 0 3px rgba(64, 156, 255, 0.95), " +
                "inset 0 0 28px 6px rgba(64, 156, 255, 0.45)",
              "border-radius": "2px"
            });

            root.appendChild(border);
            const host = document.body || document.documentElement;
            host.appendChild(root);

            // Force reflow so the opacity transition runs from 1 → 0.
            void root.offsetWidth;

            const HOLD_MS = 480;
            const FADE_MS = 720;

            setTimeout(() => {
              try {
                root.style.setProperty("opacity", "0", "important");
              } catch {}
            }, HOLD_MS);

            setTimeout(() => {
              try {
                root.remove();
              } catch {}
              resolve({ ok: true });
            }, HOLD_MS + FADE_MS + 40);
          } catch (e) {
            resolve({ ok: false, error: String(e && e.message || e) });
          }
        });
      }
    });
    if (res?.result && res.result.ok === false) {
      console.warn("[notch] shutter flash error inside page:", res.result.error);
    }
  } catch (err) {
    console.warn("[notch] shutter flash skipped:", err?.message || err);
  }
}

function waitForTabLoaded(tabId, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let timeoutId = null;
    let listening = false;

    const settle = async () => {
      if (settled) return;
      settled = true;
      if (listening) chrome.tabs.onUpdated.removeListener(handleUpdated);
      if (timeoutId) clearTimeout(timeoutId);
      try {
        resolve(await chrome.tabs.get(tabId));
      } catch (error) {
        reject(error);
      }
    };

    const handleUpdated = (updatedTabId, changeInfo) => {
      if (updatedTabId === tabId && changeInfo.status === "complete") {
        settle();
      }
    };

    chrome.tabs.get(tabId).then(tab => {
      if (tab.status === "complete") {
        settle();
        return;
      }
      chrome.tabs.onUpdated.addListener(handleUpdated);
      listening = true;
      timeoutId = setTimeout(settle, timeoutMs);
    }).catch(reject);
  });
}

async function followGoogleRedirectNotice(tabId, timeoutMs = 3500) {
  if (tabId == null) return { redirected: false, url: "" };

  let tab = null;
  try {
    tab = await waitForTabLoaded(tabId, timeoutMs);
  } catch {
    tab = await chrome.tabs.get(tabId).catch(() => null);
  }

  if (!tab) return { redirected: false, url: "" };

  const targetUrl =
    extractGoogleRedirectTargetFromUrl(tab.url) ||
    await extractGoogleRedirectTargetFromPage(tabId).catch(() => null);

  if (!targetUrl) {
    return { redirected: false, url: tab.url || "" };
  }

  await chrome.tabs.update(tabId, { url: targetUrl });
  return { redirected: true, url: targetUrl };
}

function extractGoogleRedirectTargetFromUrl(urlString) {
  try {
    const url = new URL(urlString);
    if (!isGoogleHost(url.hostname) || !url.pathname.endsWith("/url")) return null;

    return sanitizeExternalHttpUrl(url.searchParams.get("url") || url.searchParams.get("q"));
  } catch {
    return null;
  }
}

async function extractGoogleRedirectTargetFromPage(tabId) {
  const [injection] = await chrome.scripting.executeScript({
    target: { tabId },
    func: () => {
      const host = location.hostname.toLowerCase();
      const isGoogle =
        host === "google.com" ||
        host.endsWith(".google.com") ||
        host.startsWith("www.google.") ||
        host.includes(".google.");

      if (!isGoogle) return null;

      const pageText = `${document.title}\n${document.body?.innerText || ""}`;
      if (!/redirect notice|thông báo chuyển hướng|chuyển hướng/i.test(pageText)) {
        return null;
      }

      const anchors = Array.from(document.querySelectorAll("a[href]"));
      const externalAnchor = anchors.find((anchor) => {
        try {
          const url = new URL(anchor.href);
          const anchorHost = url.hostname.toLowerCase();
          const anchorIsGoogle =
            anchorHost === "google.com" ||
            anchorHost.endsWith(".google.com") ||
            anchorHost.startsWith("www.google.") ||
            anchorHost.includes(".google.");

          return (url.protocol === "http:" || url.protocol === "https:") && !anchorIsGoogle;
        } catch {
          return false;
        }
      });

      return externalAnchor?.href || null;
    }
  });

  return sanitizeExternalHttpUrl(injection?.result);
}

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

function sanitizeExternalHttpUrl(rawUrl) {
  if (!rawUrl || typeof rawUrl !== "string") return null;

  try {
    const url = new URL(rawUrl.trim());
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (isGoogleHost(url.hostname)) return null;
    return url.href;
  } catch {
    return null;
  }
}

function isGoogleHost(hostname) {
  const host = String(hostname || "").toLowerCase();
  return (
    host === "google.com" ||
    host.endsWith(".google.com") ||
    host.startsWith("www.google.") ||
    host.includes(".google.")
  );
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
