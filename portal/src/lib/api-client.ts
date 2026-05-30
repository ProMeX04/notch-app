import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios'
import { buildBrowserAuthDevicePayload, notifyPortalAuthSessionChange } from '@/lib/portal-auth-client'

export const apiClient = axios.create({
  baseURL: '/',
  withCredentials: true,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request Interceptor: Attach X-Notch-Device-Id
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    if (typeof window !== 'undefined') {
      try {
        const { device_id } = buildBrowserAuthDevicePayload()
        if (device_id) {
          config.headers.set('X-Notch-Device-Id', device_id)
        }
      } catch (err) {
        console.error('Failed to attach device ID in request interceptor', err)
      }
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

interface FailedRequest {
  resolve: (value: unknown) => void
  reject: (reason: unknown) => void
}

let isRefreshing = false
let failedQueue: FailedRequest[] = []

const processQueue = (error: Error | null, token: string | null = null) => {
  failedQueue.forEach((prom) => {
    if (error) {
      prom.reject(error)
    } else {
      prom.resolve(token)
    }
  })
  failedQueue = []
}

// Response Interceptor: Catch 401/403 and perform refresh token rotation
apiClient.interceptors.response.use(
  (response) => {
    return response
  },
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean }

    if (!originalRequest) {
      return Promise.reject(error)
    }

    const status = error.response ? error.response.status : null

    // Determine if we should attempt token refresh (status is 401 or 403 on client-side)
    const isUnauthorized = status === 401 || status === 403
    const isRefreshOrLogoutRequest =
      originalRequest.url === '/api/auth/refresh' || originalRequest.url === '/api/auth/logout'

    if (
      typeof window !== 'undefined' &&
      isUnauthorized &&
      !originalRequest._retry &&
      !isRefreshOrLogoutRequest
    ) {
      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject })
        })
          .then(() => {
            return apiClient(originalRequest)
          })
          .catch((err) => {
            return Promise.reject(err)
          })
      }

      originalRequest._retry = true
      isRefreshing = true

      // Timeout safety: if refresh takes longer than 8 seconds, clear the lock and reject the queue
      const refreshTimeout = setTimeout(() => {
        if (isRefreshing) {
          isRefreshing = false
          processQueue(new Error('Token refresh operation timed out.'))
        }
      }, 8000)

      try {
        // Request token refresh
        await apiClient.post('/api/auth/refresh')
        clearTimeout(refreshTimeout)
        isRefreshing = false
        processQueue(null)

        // Notify app context of auth state change unless this was already checking /api/auth/me
        if (!originalRequest.url?.includes('/api/auth/me')) {
          notifyPortalAuthSessionChange()
        }

        // Retry the original request
        return apiClient(originalRequest)
      } catch (refreshError) {
        clearTimeout(refreshTimeout)
        isRefreshing = false
        processQueue(refreshError as Error)

        // Refresh failed, clean up local auth state
        try {
          await apiClient.post('/api/auth/logout')
        } catch {
          // Ignore logout error if session is already revoked
        }

        // Notify app context of auth state change unless this was already checking /api/auth/me
        if (!originalRequest.url?.includes('/api/auth/me')) {
          notifyPortalAuthSessionChange()
        }

        // Redirect user if in protected routes
        const pathname = window.location.pathname
        if (pathname.startsWith('/admin') || pathname.startsWith('/pro')) {
          window.location.href = '/login'
        }

        return Promise.reject(refreshError)
      }
    }

    return Promise.reject(error)
  }
)
