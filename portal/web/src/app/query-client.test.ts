import { describe, expect, it } from 'vitest'

import { createQueryClient } from '@/app/query-client'

describe('createQueryClient', () => {
  it('creates a query client with stable defaults for the SPA shell', () => {
    const client = createQueryClient()
    const defaults = client.getDefaultOptions()

    expect(defaults.queries?.refetchOnWindowFocus).toBe(false)
    expect(defaults.queries?.retry).toBe(1)
  })
})
