export type PortalAccountUser = {
  id: string
  email: string | null
  name: string | null
  avatar_url: string | null
  created_at: string
  is_pro: boolean
  is_admin: boolean
  current_session_id: string | null
  max_active_devices: number
}

export type PortalAuthStatus = 'booting' | 'authenticated' | 'guest'

export type PortalAuthContextValue = {
  status: PortalAuthStatus
  user: PortalAccountUser | null
  isAuthenticated: boolean
  refreshAuthState: () => Promise<void>
  signOut: () => Promise<void>
}
