const DEVICE_ID_STORAGE_KEY = 'notch:deviceId'
const AUTH_SESSION_CHANGED_EVENT = 'notch:auth-session-changed'

export type BrowserDevicePayload = {
  device_id: string
  device_name: string
  platform: string
  trust_device: boolean
}

type AuthSessionChangeHandler = (detail?: { expired?: boolean }) => void

function readOrCreateDeviceId() {
  const existing = window.localStorage.getItem(DEVICE_ID_STORAGE_KEY)?.trim()
  if (existing) return existing

  const generated =
    typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `web_${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`

  window.localStorage.setItem(DEVICE_ID_STORAGE_KEY, generated)
  return generated
}

function inferBrowserPlatform() {
  const userAgent = window.navigator.userAgent
  if (/Mac OS X|Macintosh/i.test(userAgent)) return 'macOS'
  if (/Windows/i.test(userAgent)) return 'Windows'
  if (/Android/i.test(userAgent)) return 'Android'
  if (/iPhone|iPad|iPod/i.test(userAgent)) return 'iOS'
  if (/Linux/i.test(userAgent)) return 'Linux'
  return 'Browser'
}

export function buildBrowserAuthDevicePayload(trustDevice = false): BrowserDevicePayload {
  const platform = inferBrowserPlatform()
  return {
    device_id: readOrCreateDeviceId(),
    device_name: `${platform} Browser`,
    platform,
    trust_device: trustDevice,
  }
}

export function onPortalAuthSessionChange(handler: AuthSessionChangeHandler) {
  const listener = (e: Event) => {
    const customEvent = e as CustomEvent<{ expired?: boolean }>
    handler(customEvent.detail)
  }
  window.addEventListener(AUTH_SESSION_CHANGED_EVENT, listener)

  return () => {
    window.removeEventListener(AUTH_SESSION_CHANGED_EVENT, listener)
  }
}

export function notifyPortalAuthSessionChange(options?: { expired?: boolean }) {
  window.dispatchEvent(new CustomEvent(AUTH_SESSION_CHANGED_EVENT, { detail: options }))
}

export function getGoogleLoginUrl(): string {
  const { device_id, device_name, platform } = buildBrowserAuthDevicePayload()
  return `/api/auth/google?device_id=${encodeURIComponent(device_id)}&device_name=${encodeURIComponent(device_name)}&platform=${encodeURIComponent(platform)}`
}
