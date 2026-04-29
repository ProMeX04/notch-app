import type { Prisma } from '@prisma/client'

export type DatabaseClient = Prisma.TransactionClient

export type SessionUser = {
  id: string
  email: string | null
  name: string | null
  createdAt: Date
  isPro: boolean
}

export type AuthDeviceInput = {
  device_id?: string
  device_name?: string
  platform?: string
  trust_device?: boolean
}

export type NormalizedDevice = {
  deviceId: string
  deviceName: string
  platform: string
  trustDevice: boolean
}

export type LogoutRequestBody = AuthDeviceInput & {
  token?: string
  tokens?: string[]
  refresh_token?: string
  session_id?: string
  device_id?: string
}

export type RefreshRequestBody = AuthDeviceInput & {
  refresh_token?: string
}

export type NotchAuthPayload = {
  access_token: string
  token_type: 'Bearer'
  expires_at: string
  refresh_token: string
  refresh_expires_at: string
  session_token?: string
  user: {
    id: string
    email: string
    name: string | null
    created_at: string
    is_pro: boolean
  }
  session: {
    id: string
    device_id: string
    device_name: string
    platform: string
    trusted_at: string | null
  }
  max_active_devices: number
}

export type NotchWebBridgePayload = {
  bridge_token: string
  expires_at: string
}

export type NotchAppLoginBridgePayload = {
  bridge_token: string
  expires_at: string
}

export type AppLoginBridgeExchangeResult =
  | {
      status: 'ready'
      payload: NotchAuthPayload
    }
  | {
      status: 'pending'
      expires_at: string
    }
  | {
      status: 'expired' | 'invalid'
    }

export type AuthDeviceSummary = {
  device_id: string
  device_name: string
  platform: string
  trusted_at: string | null
  created_at: string
  last_seen_at: string
  revoked_at: string | null
  revoked_reason: string | null
  active: boolean
  current: boolean
  active_session_count: number
}

export class AuthDeviceLimitError extends Error {
  readonly statusCode = 409

  constructor(readonly maxActiveDevices: number) {
    super(`Too many active devices. You can use up to ${maxActiveDevices} devices at the same time.`)
    this.name = 'AuthDeviceLimitError'
  }
}
