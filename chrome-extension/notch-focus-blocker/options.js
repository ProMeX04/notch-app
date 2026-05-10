const apiBaseUrlInput = document.getElementById("api-base-url");
const saveButton = document.getElementById("save-button");
const testButton = document.getElementById("test-button");
const statusCard = document.getElementById("status-card");
const statusText = document.getElementById("status-text");

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

function setStatusVariant(variant) {
  const map = {
    offline: "status--offline",
    focus: "status--focus",
    break: "status--break",
    ok: "status--ok",
    idle: "status--idle"
  };
  statusCard.className =
    "status " + (map[variant] || "status--idle");
}

function render(state) {
  const { summary } = globalThis.notchBridgeStatus || {};
  if (!summary) {
    statusText.textContent = "Thiếu bridge-status.js.";
    return;
  }

  const { variant, text } = summary(state);
  setStatusVariant(variant);
  statusText.textContent = text;
}
