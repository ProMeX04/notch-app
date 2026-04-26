function el(id) { return document.getElementById(id); }
function setText(id, val) { const n = el(id); if (n) n.textContent = val; }
function setClass(id, cls) { const n = el(id); if (n) n.className = cls; }

el("refresh-button")?.addEventListener("click", async () => {
  const response = await chrome.runtime.sendMessage({ type: "refresh-state" });
  render(response?.state);
});

el("options-button")?.addEventListener("click", () => {
  chrome.runtime.openOptionsPage();
});

bootstrap();

async function bootstrap() {
  const response = await chrome.runtime.sendMessage({ type: "get-state" });
  render(response?.state);
}

function render(state) {
  if (!state) return;

  setText("bridge-url", state.apiBaseUrl || "http://127.0.0.1:44991");
  setText("focus-state", state.focusActive ? "Blocking active" : state.connected ? "Idle" : "App offline");
  setText("phase", state.phase || "-");
  setText("blocked-count", String((state.blockedHosts || []).length));

  if (!state.connected) {
    setText("connection-status", state.error
      ? `Cannot reach Notch app: ${state.error}`
      : "Cannot reach Notch app.");
    setClass("connection-status", "status status-idle");
  } else if (state.focusActive) {
    setText("connection-status", "Focus session is running. Matching domains will be blocked.");
    setClass("connection-status", "status status-active");
  } else {
    setText("connection-status", "Connected. Waiting for a running focus phase.");
    setClass("connection-status", "status status-connected");
  }

  const blockedHostsEl = el("blocked-hosts");
  if (!blockedHostsEl) return;

  blockedHostsEl.textContent = "";

  if (!state.blockedHosts || state.blockedHosts.length === 0) {
    blockedHostsEl.textContent = "No synced domains.";
    blockedHostsEl.className = "chips empty";
    return;
  }

  blockedHostsEl.className = "chips";

  for (const host of state.blockedHosts) {
    const chip = document.createElement("span");
    chip.className = "chip";
    chip.textContent = host;
    blockedHostsEl.appendChild(chip);
  }
}
