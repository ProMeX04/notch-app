import { apiClient } from '@/api/client'

export type PortalOAuthAuthorizeRequest = {
  client_id: string
  redirect_uri: string
  response_type: 'code'
  code_challenge: string
  code_challenge_method: 'S256'
  state?: string
}

type SearchParamsLike = {
  get(name: string): string | null
}

function normalizeText(value: string | null | undefined) {
  const trimmed = value?.trim()
  return trimmed ? trimmed : null
}

export function readPortalOAuthAuthorizeRequest(searchParams: SearchParamsLike): PortalOAuthAuthorizeRequest | null {
  const clientID = normalizeText(searchParams.get('client_id'))
  const redirectURI = normalizeText(searchParams.get('redirect_uri'))
  const responseType = normalizeText(searchParams.get('response_type'))
  const codeChallenge = normalizeText(searchParams.get('code_challenge'))
  const codeChallengeMethod = normalizeText(searchParams.get('code_challenge_method'))?.toUpperCase()
  const state = normalizeText(searchParams.get('state'))

  if (!clientID || !redirectURI || !responseType || !codeChallenge || !codeChallengeMethod) {
    return null
  }

  if (responseType !== 'code' || codeChallengeMethod !== 'S256') {
    return null
  }

  return {
    client_id: clientID,
    redirect_uri: redirectURI,
    response_type: 'code',
    code_challenge: codeChallenge,
    code_challenge_method: 'S256',
    ...(state ? { state } : {}),
  }
}

export function buildPortalOAuthSearch(request: PortalOAuthAuthorizeRequest | null) {
  if (!request) return ''

  const params = new URLSearchParams({
    client_id: request.client_id,
    redirect_uri: request.redirect_uri,
    response_type: request.response_type,
    code_challenge: request.code_challenge,
    code_challenge_method: request.code_challenge_method,
  })

  if (request.state) {
    params.set('state', request.state)
  }

  const search = params.toString()
  return search ? `?${search}` : ''
}

export async function completePortalOAuthAuthorization(request: PortalOAuthAuthorizeRequest) {
  try {
    const response = await apiClient.post<{ redirect_to?: string; detail?: string }>('/api/oauth/authorize', request)
    if (!response.data || !response.data.redirect_to) {
      throw new Error(response.data?.detail || 'Không thể hoàn tất đăng nhập cho Notch app.')
    }
    return response.data.redirect_to
  } catch (error: unknown) {
    const errorWithResponse = error as { response?: { data?: { detail?: string } }; message?: string }
    const detail = errorWithResponse.response?.data?.detail || errorWithResponse.message
    throw new Error(detail || 'Không thể hoàn tất đăng nhập cho Notch app.')
  }
}

export function launchPortalOAuthAppRedirect(
  redirectTo: string,
  options: {
    onAppSwitch?: () => void
    onFallback?: () => void
    fallbackDelayMs?: number
  } = {},
) {
  const target = normalizeText(redirectTo)
  if (!target) {
    throw new Error('Missing OAuth redirect target.')
  }

  let completed = false
  const fallbackDelayMs = options.fallbackDelayMs ?? 1200

  const cleanup = () => {
    window.clearTimeout(fallbackTimer)
    window.removeEventListener('blur', handleAppSwitch)
    document.removeEventListener('visibilitychange', handleVisibilityChange)
    window.removeEventListener('pagehide', handleAppSwitch)
  }

  const finish = (didSwitchToApp: boolean) => {
    if (completed) return
    completed = true
    cleanup()
    if (didSwitchToApp) {
      options.onAppSwitch?.()
      return
    }
    options.onFallback?.()
  }

  const handleAppSwitch = () => {
    finish(true)
  }

  const handleVisibilityChange = () => {
    if (document.visibilityState === 'hidden') {
      finish(true)
    }
  }

  const fallbackTimer = window.setTimeout(() => {
    finish(false)
  }, fallbackDelayMs)

  window.addEventListener('blur', handleAppSwitch, { once: true })
  document.addEventListener('visibilitychange', handleVisibilityChange)
  window.addEventListener('pagehide', handleAppSwitch, { once: true })

  window.location.assign(target)
}
