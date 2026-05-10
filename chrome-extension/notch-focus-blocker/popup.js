function el(id) {
  return document.getElementById(id);
}

function setStatusVariant(variant) {
  const card = el("status-card");
  if (!card) return;
  const map = {
    offline: "status--offline",
    focus: "status--focus",
    break: "status--break",
    ok: "status--ok",
    idle: "status--idle"
  };
  card.className = "status " + (map[variant] || "status--idle");
}

el("options-button")?.addEventListener("click", () => {
  chrome.runtime.openOptionsPage();
});

bootstrap();

async function bootstrap() {
  const response = await chrome.runtime.sendMessage({ type: "get-state" });
  render(response?.state);
}

function render(state) {
  const textEl = el("status-text");
  if (!textEl) return;

  const { summary } = globalThis.notchBridgeStatus || {};
  if (!summary) {
    textEl.textContent = "Thiếu bridge-status.js.";
    setStatusVariant("idle");
    return;
  }

  const { variant, text } = summary(state);
  setStatusVariant(variant);
  textEl.textContent = text;
}
