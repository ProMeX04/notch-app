import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from '@tanstack/react-router'
import { useState } from 'react'

import { PortalAuthProvider } from '@/auth/PortalAuthProvider'
import { createQueryClient } from '@/app/query-client'
import { router } from '@/app/router'

export function AppProviders() {
  const [queryClient] = useState(() => createQueryClient())

  return (
    <QueryClientProvider client={queryClient}>
      <PortalAuthProvider>
        <RouterProvider router={router} />
      </PortalAuthProvider>
    </QueryClientProvider>
  )
}
