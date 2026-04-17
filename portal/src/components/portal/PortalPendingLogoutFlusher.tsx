'use client'

import { useEffect } from 'react'

import { flushPendingLogoutTokens } from '@/lib/portal-auth-client'

export function PortalPendingLogoutFlusher() {
  useEffect(() => {
    void flushPendingLogoutTokens()
  }, [])

  return null
}
