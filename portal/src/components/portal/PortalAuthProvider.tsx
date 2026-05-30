'use client'

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { onPortalAuthSessionChange, signOutImmediately } from '@/lib/portal-auth-client'
import { apiClient } from '@/lib/api-client'

export type PortalAccountUser = {
  id: string
  email: string
  name: string | null
  avatar_url: string | null
  created_at: string
  is_pro: boolean
  current_session_id: string | null
  max_active_devices: number
}

type PortalAuthStatus = 'booting' | 'authenticated' | 'guest'

type PortalAuthContextValue = {
  status: PortalAuthStatus
  user: PortalAccountUser | null
  isAuthenticated: boolean
  refreshAuthState: () => Promise<void>
  signOut: () => void
}

const PortalAuthContext = createContext<PortalAuthContextValue | null>(null)

async function fetchAuthenticatedUser() {
  const response = await apiClient.get<PortalAccountUser>('/api/auth/me')
  return response.data
}

export function PortalAuthProvider({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  const [authVersion, setAuthVersion] = useState(0)
  const [status, setStatus] = useState<PortalAuthStatus>('booting')
  const [user, setUser] = useState<PortalAccountUser | null>(null)

  useEffect(() => {
    let ignore = false

    const syncAuthState = async () => {
      if (!ignore) {
        setStatus((currentStatus) => (currentStatus === 'authenticated' ? currentStatus : 'booting'))
      }

      try {
        const nextUser = await fetchAuthenticatedUser()
        if (ignore) return
        setUser(nextUser)
        setStatus('authenticated')
      } catch {
        if (ignore) return
        setUser(null)
        setStatus('guest')
      }
    }

    void syncAuthState()

    return () => {
      ignore = true
    }
  }, [authVersion])

  useEffect(() => {
    const handlePageShow = (event: PageTransitionEvent) => {
      if (event.persisted) {
        window.location.reload()
      }
    }
    window.addEventListener('pageshow', handlePageShow)

    const unsubscribe = onPortalAuthSessionChange(() => {
      setAuthVersion((currentVersion) => currentVersion + 1)
    })

    return () => {
      window.removeEventListener('pageshow', handlePageShow)
      unsubscribe()
    }
  }, [])

  const value = useMemo<PortalAuthContextValue>(
    () => ({
      status,
      user,
      isAuthenticated: status === 'authenticated' && user !== null,
      refreshAuthState: async () => {
        setAuthVersion((currentVersion) => currentVersion + 1)
      },
      signOut: () => {
        void signOutImmediately()
        setUser(null)
        setStatus('guest')
      },
    }),
    [status, user],
  )

  return <PortalAuthContext.Provider value={value}>{children}</PortalAuthContext.Provider>
}

export function usePortalAuth() {
  const context = useContext(PortalAuthContext)
  if (!context) {
    throw new Error('usePortalAuth must be used within PortalAuthProvider.')
  }

  return context
}
