import type {
  NotchAuthPayload,
  SessionUser,
} from '@/lib/auth/auth-types'
import { MAX_ACTIVE_DEVICES } from '@/lib/auth/device-service'
import {
  authPayloadUserResponse as buildAuthPayloadUserResponse,
  authUserResponse as buildAuthUserResponse,
} from '@/lib/auth/user-service'

export {
  requireAdminForServerComponent,
  requireAdminUser,
} from '@/lib/auth/admin-service'
export {
  createAppLoginBridgePayload,
  createWebBridgePayload,
  completeAppLoginBridgeToken,
  exchangeAppLoginBridgeToken,
  exchangePortableSessionToken,
  exchangeWebBridgeToken,
} from '@/lib/auth/bridge-service'
export {
  AuthDeviceLimitError,
  type AppLoginBridgeExchangeResult,
  type AuthDeviceInput,
  type AuthDeviceSummary,
  type DatabaseClient,
  type NotchAppLoginBridgePayload,
  type NotchAuthPayload,
  type NotchWebBridgePayload,
  type SessionUser,
} from '@/lib/auth/auth-types'
export {
  listUserDevices,
  MAX_ACTIVE_DEVICES,
  revokeDeviceSessions,
  setTrustedDevice,
} from '@/lib/auth/device-service'
export {
  getAuthenticatedUser,
} from '@/lib/auth/session-query-service'
export {
  createAuthPayload,
  createAuthPayloadInTransaction,
  refreshAuthSession,
  refreshAuthSessionWithToken,
  revokeAuthSessions,
} from '@/lib/auth/session-service'
export {
  hashToken,
  readBearerToken,
  readCookie,
  type NotchPortableSession,
} from '@/lib/auth/token-service'
export {
  DEFAULT_FEATURE_CONFIGS,
  canUseFeature,
  getFeatureRequirement,
  getRemotePermissionPolicy,
  mergeDefaultFeatureConfigs,
} from '@/lib/capabilities/policy-service'

export async function authUserResponse(user: SessionUser, sessionId?: string | null) {
  return buildAuthUserResponse(user, sessionId, MAX_ACTIVE_DEVICES)
}

export function authPayloadUserResponse(
  user: NotchAuthPayload['user'],
  sessionId?: string | null,
) {
  return buildAuthPayloadUserResponse(user, sessionId, MAX_ACTIVE_DEVICES)
}
