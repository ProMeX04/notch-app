'use client'

const DEVICE_ID_STORAGE_KEY = 'notch:deviceId'
const AUTH_SESSION_CHANGED_EVENT = 'notch:auth-session-changed'

export type BrowserDevicePayload = {
  device_id: string
  device_name: string
  platform: string
  trust_device: boolean
}

type AuthSessionChangeHandler = () => void

function notifyAuthSessionChanged() {
  window.dispatchEvent(new Event(AUTH_SESSION_CHANGED_EVENT))
}

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
  const handleStorage = (event: StorageEvent) => {
    if (event.key === DEVICE_ID_STORAGE_KEY) return
    handler()
  }

  window.addEventListener(AUTH_SESSION_CHANGED_EVENT, handler)
  window.addEventListener('storage', handleStorage)

  return () => {
    window.removeEventListener(AUTH_SESSION_CHANGED_EVENT, handler)
    window.removeEventListener('storage', handleStorage)
  }
}

export function notifyPortalAuthSessionChange() {
  notifyAuthSessionChanged()
}

export async function authenticatedFetch(
  input: RequestInfo | URL,
  init: RequestInit = {},
): Promise<Response> {
  const { apiClient } = await import('./api-client')
  const url = typeof input === 'string' ? input : input.toString()
  try {
    const response = await apiClient({
      url,
      method: (init.method || 'GET').toUpperCase(),
      data: init.body ? JSON.parse(init.body as string) : undefined,
      headers: init.headers ? Object.fromEntries(new Headers(init.headers).entries()) : undefined,
    })

    return {
      ok: true,
      status: response.status,
      statusText: response.statusText,
      json: async () => response.data,
      text: async () => typeof response.data === 'string' ? response.data : JSON.stringify(response.data),
    } as unknown as Response
  } catch (error: unknown) {
    const errorWithResponse = error as { response?: { status?: number; statusText?: string; data?: unknown }; message?: string }
    const status = errorWithResponse.response?.status || 500
    const statusText = errorWithResponse.response?.statusText || 'Internal Server Error'
    const data = errorWithResponse.response?.data || { error: errorWithResponse.message }
    return {
      ok: false,
      status,
      statusText,
      json: async () => data,
      text: async () => typeof data === 'string' ? data : JSON.stringify(data),
    } as unknown as Response
  }
}

export async function signOutImmediately() {
  try {
    const { apiClient } = await import('./api-client')
    await apiClient.post('/api/auth/logout')
  } catch {
    // Ignore logout error
  } finally {
    notifyAuthSessionChanged()
  }
}
