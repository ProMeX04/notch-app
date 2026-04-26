const params = new URLSearchParams(window.location.search);
const originalUrl = params.get("url") || "";
const host = params.get("host") || "-";

function el(id) {
  return document.getElementById(id);
}

function setText(id, text) {
  const node = el(id);
  if (node) node.textContent = text;
}

function setDisplay(id, display) {
  const node = el(id);
  if (node) node.style.display = display;
}

setText("host", host);
setText("site-name", host);
const siteIcon = el("site-icon");
if (siteIcon && host !== "-") {
  siteIcon.src = `https://www.google.com/s2/favicons?domain=${host}&sz=64`;
}

el("retry-button")?.addEventListener("click", () => {
  if (originalUrl) window.location.href = originalUrl;
});

el("refresh-button")?.addEventListener("click", refreshState);

refreshState();
setInterval(refreshState, 1000);

async function refreshState() {
  try {
    const response = await chrome.runtime.sendMessage({ type: "refresh-state" });
    const state = response?.state;

    if (!state) {
      setText("status", "Could not read focus state.");
      setDisplay("timer-container", "none");
      return;
    }

    if (!state.connected) {
      setText("status", state.error
        ? `Notch app is offline: ${state.error}`
        : "Notch app is offline.");
      setDisplay("timer-container", "none");
      return;
    }

    if (state.focusActive) {
      const minutes = Math.floor((state.remainingSeconds || 0) / 60);
      const seconds = (state.remainingSeconds || 0) % 60;
      setText("timer", `${minutes}:${seconds.toString().padStart(2, "0")}`);
      setText("phase", state.phase || "Focus");
      setDisplay("timer-container", "flex");
      setText("status", "Focus is active. This page will unlock automatically once your session ends.");
      return;
    }

    setDisplay("timer-container", "none");
    setText("status", "Focus blocking is no longer active. Redirecting...");
    if (originalUrl) {
      window.location.href = originalUrl;
    }
  } catch (err) {
    setText("status", "Error communicating with extension.");
    setDisplay("timer-container", "none");
  }
}
