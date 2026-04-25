const connectionStatus = document.getElementById("connection-status");
const focusState = document.getElementById("focus-state");
const phase = document.getElementById("phase");
const blockedCount = document.getElementById("blocked-count");
const bridgeUrl = document.getElementById("bridge-url");
const blockedHosts = document.getElementById("blocked-hosts");
const refreshButton = document.getElementById("refresh-button");
const optionsButton = document.getElementById("options-button");

refreshButton.addEventListener("click", async () => {
  const response = await chrome.runtime.sendMessage({ type: "refresh-state" });
  render(response.state);
});

optionsButton.addEventListener("click", () => {
  chrome.runtime.openOptionsPage();
});

bootstrap();

async function bootstrap() {
  const response = await chrome.runtime.sendMessage({ type: "get-state" });
  render(response.state);
}

function render(state) {
  bridgeUrl.textContent = state.apiBaseUrl || "http://127.0.0.1:44991";
  focusState.textContent = state.focusActive ? "Blocking active" : state.connected ? "Idle" : "App offline";
  phase.textContent = state.phase || "-";
  blockedCount.textContent = String((state.blockedHosts || []).length);

  if (!state.connected) {
    connectionStatus.textContent = state.error
      ? `Cannot reach Notch app: ${state.error}`
      : "Cannot reach Notch app.";
    connectionStatus.className = "status status-idle";
  } else if (state.focusActive) {
    connectionStatus.textContent = "Focus session is running. Matching domains will be blocked.";
    connectionStatus.className = "status status-active";
  } else {
    connectionStatus.textContent = "Connected. Waiting for a running focus phase.";
    connectionStatus.className = "status status-connected";
  }

  blockedHosts.textContent = "";

  if (!state.blockedHosts || state.blockedHosts.length === 0) {
    blockedHosts.textContent = "No synced domains.";
    blockedHosts.className = "chips empty";
    return;
  }

  blockedHosts.className = "chips";

  for (const host of state.blockedHosts) {
    const chip = document.createElement("span");
    chip.className = "chip";
    chip.textContent = host;
    blockedHosts.appendChild(chip);
  }
}
