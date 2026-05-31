import { createContext, useContext } from 'react'

import type { PortalAuthContextValue } from '@/auth/types'

export const PortalAuthContext = createContext<PortalAuthContextValue | null>(null)

export function usePortalAuth() {
  const context = useContext(PortalAuthContext)
  if (!context) {
    throw new Error('usePortalAuth must be used within PortalAuthProvider.')
  }
  return context
}
