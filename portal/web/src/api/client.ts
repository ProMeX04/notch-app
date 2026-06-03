import axios, { AxiosError, type InternalAxiosRequestConfig } from 'axios'

import { buildBrowserAuthDevicePayload, notifyPortalAuthSessionChange } from '@/auth/portal-auth-client'

export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || '/',
  withCredentials: true,
  headers: {
    'Content-Type': 'application/json',
  },
})

apiClient.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  try {
    const { device_id } = buildBrowserAuthDevicePayload()
    if (device_id) {
      config.headers.set('X-Notch-Device-Id', device_id)
    }
  } catch (error) {
    console.error('Failed to attach device ID in request interceptor', error)
  }
  return config
})

type FailedRequest = {
  resolve: (value: unknown) => void
  reject: (reason: unknown) => void
}

let isRefreshing = false
let failedQueue: FailedRequest[] = []

function processQueue(error: Error | null) {
  for (const request of failedQueue) {
    if (error) {
      request.reject(error)
    } else {
      request.resolve(null)
    }
  }
  failedQueue = []
}

apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as (InternalAxiosRequestConfig & { _retry?: boolean }) | undefined
    if (!originalRequest) {
      return Promise.reject(error)
    }

    const status = error.response?.status ?? null
    const isUnauthorized = status === 401 || status === 403
    const url = originalRequest.url ?? ''
    const isAuthLifecycleRequest =
      url === '/api/auth/refresh' ||
      url === '/api/auth/logout'

    if (isUnauthorized && !originalRequest._retry && !isAuthLifecycleRequest) {
      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject })
        }).then(() => apiClient(originalRequest))
      }

      originalRequest._retry = true
      isRefreshing = true

      const refreshTimeout = window.setTimeout(() => {
        if (isRefreshing) {
          isRefreshing = false
          processQueue(new Error('Token refresh operation timed out.'))
        }
      }, 8000)

      try {
        await apiClient.post('/api/auth/refresh')
        window.clearTimeout(refreshTimeout)
        isRefreshing = false
        processQueue(null)
        notifyPortalAuthSessionChange()
        return apiClient(originalRequest)
      } catch (refreshError) {
        window.clearTimeout(refreshTimeout)
        isRefreshing = false
        processQueue(refreshError as Error)
        notifyPortalAuthSessionChange({ expired: true })
        return Promise.reject(refreshError)
      }
    }

    return Promise.reject(error)
  },
)

export function clearRefreshLock() {
  isRefreshing = false
  failedQueue = []
}
