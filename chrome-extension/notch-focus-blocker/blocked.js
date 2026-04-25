const params = new URLSearchParams(window.location.search);
const originalUrl = params.get("url") || "";
const host = params.get("host") || "-";

const hostNode = document.getElementById("host");
const urlNode = document.getElementById("url");
const statusNode = document.getElementById("status");
const retryButton = document.getElementById("retry-button");
const refreshButton = document.getElementById("refresh-button");

hostNode.textContent = host;
urlNode.textContent = originalUrl || "-";

retryButton.addEventListener("click", () => {
  if (originalUrl) {
    window.location.href = originalUrl;
  }
});

refreshButton.addEventListener("click", refreshState);

refreshState();
setInterval(refreshState, 1000);

async function refreshState() {
  const response = await chrome.runtime.sendMessage({ type: "refresh-state" });
  const state = response.state;

  if (!state.connected) {
    statusNode.textContent = state.error
      ? `Notch app is offline: ${state.error}`
      : "Notch app is offline.";
    document.getElementById("timer-container").style.display = "none";
    return;
  }

  if (state.focusActive) {
    const minutes = Math.floor(state.remainingSeconds / 60);
    const seconds = state.remainingSeconds % 60;
    const timeString = `${minutes}:${seconds.toString().padStart(2, "0")}`;
    
    document.getElementById("timer").textContent = timeString;
    document.getElementById("timer-container").style.display = "flex";
    document.getElementById("phase").textContent = state.phase;
    
    statusNode.textContent = `Focus is active. This page will unlock automatically once your session ends.`;
    return;
  }

  document.getElementById("timer-container").style.display = "none";
  statusNode.textContent = "Focus blocking is no longer active. You can retry this page now.";
}
