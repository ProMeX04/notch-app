import { createHash, randomBytes } from 'node:crypto'

import type { AuthDeviceInput, NotchAuthPayload, SessionUser } from '@/lib/notch-auth'
import { createAuthPayloadInTransaction, refreshAuthSessionWithToken } from '@/lib/notch-auth'
import prisma from '@/lib/prisma'

const AUTHORIZATION_CODE_TTL_MS = 5 * 60 * 1000
const DEFAULT_NATIVE_CLIENT_ID = 'notch-desktop'
const DEFAULT_NATIVE_REDIRECT_URI = 'notch://oauth/callback'

type OAuthAuthorizeInput = {
  client_id?: string
  redirect_uri?: string
  response_type?: string
  code_challenge?: string
  code_challenge_method?: string
  state?: string
}

type OAuthTokenRequestBody = {
  grant_type?: string
  client_id?: string
  redirect_uri?: string
  code?: string
  code_verifier?: string
  refresh_token?: string
  device_id?: string
  device_name?: string
  platform?: string
  trust_device?: boolean | string
}

type ValidatedOAuthAuthorizeRequest = {
  clientId: string
  redirectURI: string
  codeChallenge: string
  codeChallengeMethod: 'S256'
  state: string | null
}

type ValidatedOAuthRefreshRequest = {
  clientId: string
  refreshToken: string
  device: AuthDeviceInput | null
}

type ValidatedOAuthCodeExchangeRequest = {
  clientId: string
  redirectURI: string
  codeChallengeMethod: 'S256'
  code: string
  codeVerifier: string
  device: AuthDeviceInput | null
}

function normalizeText(value: unknown, maxLength: number) {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (!trimmed) return null
  return trimmed.slice(0, maxLength)
}

function parseOAuthRedirectURIs() {
  const raw = process.env.NOTCH_OAUTH_NATIVE_REDIRECT_URIS?.trim()
  if (!raw) return [DEFAULT_NATIVE_REDIRECT_URI]

  const values = raw
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)

  return values.length > 0 ? values : [DEFAULT_NATIVE_REDIRECT_URI]
}

function oauthClientID() {
  return normalizeText(process.env.NOTCH_OAUTH_NATIVE_CLIENT_ID, 120) ?? DEFAULT_NATIVE_CLIENT_ID
}

function hashToken(token: string) {
  return createHash('sha256').update(token).digest('hex')
}

function sha256Base64URL(value: string) {
  return createHash('sha256').update(value).digest('base64url')
}

function validateOAuthClient(clientID: string, redirectURI: string) {
  if (clientID !== oauthClientID()) {
    throw new Error('Unsupported OAuth client.')
  }

  if (!parseOAuthRedirectURIs().includes(redirectURI)) {
    throw new Error('Unsupported OAuth redirect URI.')
  }
}

function validateOAuthClientID(clientID: string) {
  if (clientID !== oauthClientID()) {
    throw new Error('Unsupported OAuth client.')
  }
}

function validateClientAndRedirect(input: {
  client_id?: string
  redirect_uri?: string
}) {
  const clientId = normalizeText(input.client_id, 120)
  const redirectURI = normalizeText(input.redirect_uri, 2048)
  if (!clientId || !redirectURI) {
    throw new Error('Missing OAuth client configuration.')
  }

  validateOAuthClient(clientId, redirectURI)
  return { clientId, redirectURI }
}

function validateAuthorizeInput(input: OAuthAuthorizeInput): ValidatedOAuthAuthorizeRequest {
  const { clientId, redirectURI } = validateClientAndRedirect(input)
  const responseType = normalizeText(input.response_type, 32)
  const codeChallenge = normalizeText(input.code_challenge, 256)
  const codeChallengeMethod = normalizeText(input.code_challenge_method, 32)?.toUpperCase()
  const state = normalizeText(input.state, 512)

  if (responseType !== 'code') {
    throw new Error('Unsupported OAuth response type.')
  }

  if (!codeChallenge || codeChallenge.length < 43 || codeChallenge.length > 128) {
    throw new Error('Invalid PKCE code challenge.')
  }

  if (codeChallengeMethod !== 'S256') {
    throw new Error('Only PKCE S256 is supported.')
  }

  return {
    clientId,
    redirectURI,
    codeChallenge,
    codeChallengeMethod: 'S256',
    state,
  }
}

function validateCodeExchangeInput(body: OAuthTokenRequestBody): ValidatedOAuthCodeExchangeRequest {
  if (normalizeText(body.grant_type, 64) !== 'authorization_code') {
    throw new Error('Unsupported OAuth grant type.')
  }

  const { clientId, redirectURI } = validateClientAndRedirect(body)
  const code = normalizeText(body.code, 256)
  const codeVerifier = normalizeText(body.code_verifier, 256)

  if (!code || !codeVerifier) {
    throw new Error('Missing authorization code exchange parameters.')
  }

  if (codeVerifier.length < 43 || codeVerifier.length > 128) {
    throw new Error('Invalid PKCE code verifier.')
  }

  return {
    clientId,
    redirectURI,
    codeChallengeMethod: 'S256',
    code,
    codeVerifier,
    device: readAuthDeviceInput(body),
  }
}

function validateRefreshInput(body: OAuthTokenRequestBody): ValidatedOAuthRefreshRequest {
  if (normalizeText(body.grant_type, 64) !== 'refresh_token') {
    throw new Error('Unsupported OAuth grant type.')
  }

  const clientId = normalizeText(body.client_id, 120)
  const refreshToken = normalizeText(body.refresh_token, 256)
  if (!clientId || !refreshToken) {
    throw new Error('Missing refresh token parameters.')
  }

  validateOAuthClientID(clientId)

  return {
    clientId,
    refreshToken,
    device: readAuthDeviceInput(body),
  }
}

function readAuthDeviceInput(body: OAuthTokenRequestBody): AuthDeviceInput | null {
  const deviceID = normalizeText(body.device_id, 128)
  const deviceName = normalizeText(body.device_name, 120)
  const platform = normalizeText(body.platform, 64)
  const trustDevice =
    typeof body.trust_device === 'boolean'
      ? body.trust_device
      : typeof body.trust_device === 'string'
        ? ['1', 'true', 'yes'].includes(body.trust_device.trim().toLowerCase())
        : undefined

  if (!deviceID && !deviceName && !platform && typeof trustDevice === 'undefined') {
    return null
  }

  return {
    device_id: deviceID ?? undefined,
    device_name: deviceName ?? undefined,
    platform: platform ?? undefined,
    trust_device: trustDevice,
  }
}

function buildOAuthTokenResponse(payload: NotchAuthPayload) {
  const now = Date.now()
  const accessExpiresAt = Date.parse(payload.expires_at)
  const refreshExpiresAt = Date.parse(payload.refresh_expires_at)

  return {
    ...payload,
    expires_in: Number.isNaN(accessExpiresAt) ? 0 : Math.max(0, Math.floor((accessExpiresAt - now) / 1000)),
    refresh_token_expires_in: Number.isNaN(refreshExpiresAt) ? 0 : Math.max(0, Math.floor((refreshExpiresAt - now) / 1000)),
    scope: 'notch',
  }
}

export function buildOAuthAuthorizeSearchParams(input: OAuthAuthorizeInput) {
  const validated = validateAuthorizeInput(input)
  const params = new URLSearchParams({
    client_id: validated.clientId,
    redirect_uri: validated.redirectURI,
    response_type: 'code',
    code_challenge: validated.codeChallenge,
    code_challenge_method: validated.codeChallengeMethod,
  })

  if (validated.state) {
    params.set('state', validated.state)
  }

  return params
}

export async function createOAuthAuthorizationRedirect(user: SessionUser, input: OAuthAuthorizeInput) {
  const validated = validateAuthorizeInput(input)
  const code = randomBytes(32).toString('base64url')
  const expiresAt = new Date(Date.now() + AUTHORIZATION_CODE_TTL_MS)

  await prisma.oAuthAuthorizationCode.create({
    data: {
      codeHash: hashToken(code),
      clientId: validated.clientId,
      redirectUri: validated.redirectURI,
      codeChallenge: validated.codeChallenge,
      codeChallengeMethod: validated.codeChallengeMethod,
      expiresAt,
      userId: user.id,
    },
  })

  const redirectURL = new URL(validated.redirectURI)
  redirectURL.searchParams.set('code', code)
  if (validated.state) {
    redirectURL.searchParams.set('state', validated.state)
  }

  return {
    redirect_to: redirectURL.toString(),
    expires_at: expiresAt.toISOString(),
  }
}

export async function exchangeOAuthToken(req: Request, body: OAuthTokenRequestBody) {
  const grantType = normalizeText(body.grant_type, 64)

  if (grantType === 'authorization_code') {
    const input = validateCodeExchangeInput(body)

    return prisma.$transaction(async (tx) => {
      const now = new Date()
      const authorizationCode = await tx.oAuthAuthorizationCode.findUnique({
        where: { codeHash: hashToken(input.code) },
        include: { user: true },
      })

      if (!authorizationCode) return null

      if (
        authorizationCode.clientId !== input.clientId ||
        authorizationCode.redirectUri !== input.redirectURI ||
        authorizationCode.codeChallengeMethod !== input.codeChallengeMethod
      ) {
        return null
      }

      if (authorizationCode.consumedAt || authorizationCode.expiresAt <= now) {
        return null
      }

      if (sha256Base64URL(input.codeVerifier) !== authorizationCode.codeChallenge) {
        return null
      }

      const consumed = await tx.oAuthAuthorizationCode.updateMany({
        where: {
          id: authorizationCode.id,
          consumedAt: null,
          expiresAt: { gt: now },
        },
        data: {
          consumedAt: now,
        },
      })

      if (consumed.count !== 1) {
        return null
      }

      const payload = await createAuthPayloadInTransaction(tx, authorizationCode.user, {
        req,
        device: input.device,
      })

      return buildOAuthTokenResponse(payload)
    })
  }

  if (grantType === 'refresh_token') {
    const input = validateRefreshInput(body)
    void input.clientId

    const payload = await refreshAuthSessionWithToken(req, input.refreshToken, input.device)
    return payload ? buildOAuthTokenResponse(payload) : null
  }

  throw new Error('Unsupported OAuth grant type.')
}
