const apiBaseUrlInput = document.getElementById("api-base-url");
const saveButton = document.getElementById("save-button");
const testButton = document.getElementById("test-button");
const connectionText = document.getElementById("connection-text");
const focusText = document.getElementById("focus-text");
const phaseText = document.getElementById("phase-text");
const countText = document.getElementById("count-text");
const detailText = document.getElementById("detail-text");

saveButton.addEventListener("click", saveApiBaseUrl);
testButton.addEventListener("click", refreshState);

bootstrap();

async function bootstrap() {
  const { apiBaseUrl = "ws://127.0.0.1:44991/v1/ws" } = await chrome.storage.local.get({
    apiBaseUrl: "ws://127.0.0.1:44991/v1/ws"
  });
  apiBaseUrlInput.value = apiBaseUrl;

  await refreshState();
}

async function saveApiBaseUrl() {
  const response = await chrome.runtime.sendMessage({
    type: "save-api-base-url",
    value: apiBaseUrlInput.value
  });

  apiBaseUrlInput.value = response.state.apiBaseUrl;
  render(response.state);
}

async function refreshState() {
  const response = await chrome.runtime.sendMessage({ type: "refresh-state" });
  render(response.state);
}

function render(state) {
  connectionText.textContent = state.connected ? "Connected" : "Offline";
  focusText.textContent = state.focusActive ? "Blocking active" : "Not blocking";
  phaseText.textContent = state.phase || "-";
  countText.textContent = String((state.blockedHosts || []).length);

  if (!state.connected) {
    detailText.textContent = state.error
      ? `Bridge error: ${state.error}`
      : "The extension cannot reach the Notch app bridge.";
    return;
  }

  detailText.textContent = state.focusActive
    ? "A running focus phase is active in Notch. Matching tabs will be redirected immediately."
    : "Connected to Notch. Blocking starts only during the running focus phase.";
}
