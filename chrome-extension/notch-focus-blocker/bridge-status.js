/**
 * Trạng thái một dòng + variant (màu) dùng chung cho popup và trang cài đặt.
 * Không dùng ES module để load được qua <script src>.
 */
(function () {
  function formatDuration(sec) {
    const s = Math.max(0, Math.floor(Number(sec) || 0));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${r.toString().padStart(2, "0")}`;
  }

  /**
   * @returns {{ variant: string, text: string }}
   * variant: idle | offline | focus | break | ok
   */
  function summary(state) {
    if (!state) {
      return { variant: "idle", text: "Không có dữ liệu." };
    }

    const connected = Boolean(state.connected);
    const focusActive = Boolean(state.focusActive);
    const hasSession = Boolean(state.hasActiveSession);
    const running = Boolean(state.isRunning);
    const phase = state.phase || "Focus";
    const remaining = Number(state.remainingSeconds) || 0;
    const timeStr = formatDuration(remaining);

    if (!connected) {
      return {
        variant: "offline",
        text: state.error
          ? `Chưa kết nối · ${state.error}`
          : "Chưa kết nối app Notch trên máy."
      };
    }

    if (focusActive) {
      return {
        variant: "focus",
        text: running
          ? `Đang chặn site · ${phase} còn ${timeStr}`
          : `Đang chặn site · ${phase}`
      };
    }

    if (hasSession) {
      const isBreak = phase !== "Focus";
      if (isBreak) {
        return {
          variant: "break",
          text: running
            ? `Nghỉ · ${phase} ${timeStr}`
            : `Nghỉ · ${phase} (tạm dừng)`
        };
      }
      return {
        variant: "ok",
        text: `Focus tạm dừng · ${timeStr}`
      };
    }

    return { variant: "ok", text: "Đã kết nối Notch." };
  }

  globalThis.notchBridgeStatus = { summary, formatDuration };
})();
