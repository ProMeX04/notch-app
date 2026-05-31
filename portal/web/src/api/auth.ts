import { apiClient } from '@/api/client'
import type { PortalAccountUser } from '@/auth/types'

export async function fetchAuthenticatedUser() {
  const response = await apiClient.get<PortalAccountUser>('/api/auth/me')
  return response.data
}

export async function logout() {
  await apiClient.post('/api/auth/logout')
}
