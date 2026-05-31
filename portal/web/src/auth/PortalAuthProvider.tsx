import { useEffect, useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import { fetchAuthenticatedUser, logout } from '@/api/auth'
import { clearRefreshLock } from '@/api/client'
import { onPortalAuthSessionChange } from '@/auth/portal-auth-client'
import { AUTH_ME_QUERY_KEY } from '@/auth/auth-query'
import { PortalAuthContext } from '@/auth/auth-context'
import type { PortalAccountUser, PortalAuthContextValue, PortalAuthStatus } from '@/auth/types'

export function PortalAuthProvider({ children }: Readonly<{ children: React.ReactNode }>) {
  const queryClient = useQueryClient()
  const authQuery = useQuery({
    queryKey: AUTH_ME_QUERY_KEY,
    queryFn: fetchAuthenticatedUser,
    retry: false,
    staleTime: 60_000,
    refetchOnWindowFocus: false,
  })

  const logoutMutation = useMutation({
    mutationFn: logout,
    onSettled: async () => {
      clearRefreshLock()
      queryClient.setQueryData<PortalAccountUser | null>(AUTH_ME_QUERY_KEY, null)
      await queryClient.invalidateQueries({ queryKey: AUTH_ME_QUERY_KEY })
    },
  })

  const status: PortalAuthStatus = authQuery.isPending
    ? 'booting'
    : authQuery.isSuccess && authQuery.data
      ? 'authenticated'
      : 'guest'

  const value = useMemo<PortalAuthContextValue>(
    () => ({
      status,
      user: status === 'authenticated' ? (authQuery.data ?? null) : null,
      isAuthenticated: status === 'authenticated',
      refreshAuthState: async () => {
        await queryClient.invalidateQueries({ queryKey: AUTH_ME_QUERY_KEY })
      },
      signOut: async () => {
        await logoutMutation.mutateAsync().catch(() => undefined)
      },
    }),
    [authQuery.data, logoutMutation, queryClient, status],
  )

  return (
    <PortalAuthContext.Provider value={value}>
      <AuthSessionChangeSubscription />
      {children}
    </PortalAuthContext.Provider>
  )
}

function AuthSessionChangeSubscription() {
  const queryClient = useQueryClient()

  useEffect(() => {
    return onPortalAuthSessionChange(() => {
      void queryClient.invalidateQueries({ queryKey: AUTH_ME_QUERY_KEY })
    })
  }, [queryClient])

  return null
}
