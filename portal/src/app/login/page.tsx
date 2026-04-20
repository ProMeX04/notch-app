'use client'

import { Suspense, type FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { AlertCircle, Loader2 } from 'lucide-react'

import { PortalAppHandoffCard } from '@/components/portal/PortalAppHandoffCard'
import { usePortalAuth } from '@/components/portal/PortalAuthProvider'
import { PortalLogo } from '@/components/portal/PortalLogo'
import { buildBrowserAuthDevicePayload, notifyPortalAuthSessionChange } from '@/lib/portal-auth-client'
import {
  buildPortalOAuthSearch,
  completePortalOAuthAuthorization,
  launchPortalOAuthAppRedirect,
  readPortalOAuthAuthorizeRequest,
} from '@/lib/portal-oauth-client'

function LoginPageFallback() {
  return (
    <main className="portal-auth-page-centered">
      <div className="portal-auth-topbar-minimal">
        <PortalLogo />
      </div>

      <section className="portal-auth-container">
        <div className="portal-card portal-auth-card" style={{ display: 'grid', placeItems: 'center', minHeight: '280px', gap: '12px' }}>
          <Loader2 size={20} className="portal-spinner" />
          <p className="portal-muted">Đang chuẩn bị đăng nhập...</p>
        </div>
      </section>
    </main>
  )
}

function LoginPageContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { isAuthenticated } = usePortalAuth()
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [hasOpenedApp, setHasOpenedApp] = useState(false)
  const [lastRedirectTo, setLastRedirectTo] = useState<string | null>(null)
  const hasAttemptedOAuthRedirect = useRef(false)

  const oauthRequest = useMemo(() => readPortalOAuthAuthorizeRequest(searchParams), [searchParams])
  const signupHref = useMemo(() => `/signup${buildPortalOAuthSearch(oauthRequest)}`, [oauthRequest])
  const isHandoffState = Boolean(oauthRequest && hasOpenedApp)

  const handoffToApp = (redirectTo: string) => {
    setLastRedirectTo(redirectTo)
    hasAttemptedOAuthRedirect.current = true
    launchPortalOAuthAppRedirect(redirectTo, {
      onAppSwitch: () => {
        setHasOpenedApp(true)
        setIsLoading(false)
      },
      onFallback: () => {
        setHasOpenedApp(true)
        setIsLoading(false)
      },
    })
  }

  useEffect(() => {
    if (!isAuthenticated || hasAttemptedOAuthRedirect.current) return

    let ignore = false

    const continueFlow = async () => {
      if (!oauthRequest) {
        router.replace('/pro')
        return
      }

      setIsLoading(true)
      setError(null)

      try {
        const redirectTo = await completePortalOAuthAuthorization(oauthRequest)
        if (!ignore) {
          handoffToApp(redirectTo)
        }
      } catch (nextError) {
        if (!ignore) {
          setError(nextError instanceof Error ? nextError.message : 'Không thể hoàn tất đăng nhập cho Notch app.')
          setIsLoading(false)
        }
      }
    }

    void continueFlow()

    return () => {
      ignore = true
    }
  }, [isAuthenticated, oauthRequest, router])

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setIsLoading(true)
    setError(null)

    const formData = new FormData(event.currentTarget)
    const email = formData.get('email') as string
    const password = formData.get('password') as string

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email,
          password,
          ...buildBrowserAuthDevicePayload(),
        }),
      })

      const data = await response.json()
      if (!response.ok) {
        throw new Error(data.error || data.detail || 'Không thể đăng nhập. Vui lòng thử lại.')
      }

      notifyPortalAuthSessionChange()

      if (oauthRequest) {
        const redirectTo = await completePortalOAuthAuthorization(oauthRequest)
        handoffToApp(redirectTo)
        return
      }

      router.replace('/pro')
    } catch (nextError) {
      setError(nextError instanceof Error ? nextError.message : 'Không thể đăng nhập. Vui lòng thử lại.')
      setIsLoading(false)
    }
  }

  return (
    <main className="portal-auth-page-centered">
      {!isHandoffState ? (
        <div className="portal-auth-topbar-minimal">
          <PortalLogo />
          <Link href={signupHref} className="portal-button-ghost">
            Tạo tài khoản
          </Link>
        </div>
      ) : null}

      <section className="portal-auth-container">
        <div className="portal-auth-header-centered">
          <h1 className="portal-auth-title-large">{isHandoffState ? 'Notch' : 'Chào bạn quay lại'}</h1>
          <p className="portal-muted">
            {isHandoffState
              ? 'Mở ứng dụng để tiếp tục.'
              : oauthRequest
              ? 'Đăng nhập để tiếp tục ngay trong ứng dụng Notch.'
              : 'Đăng nhập để quản lý tài khoản và đồng bộ với Notch app.'}
          </p>
        </div>

        <div className="portal-card portal-auth-card">
          {hasOpenedApp && oauthRequest ? (
            <PortalAppHandoffCard
              mode="ready"
              title="Tiếp tục trong Notch"
              description="Bạn có thể đóng tab này."
              primaryLabel="Mở lại Notch"
              onPrimaryAction={() => {
                if (!lastRedirectTo) {
                  setHasOpenedApp(false)
                  hasAttemptedOAuthRedirect.current = false
                  return
                }
                setHasOpenedApp(false)
                setIsLoading(true)
                handoffToApp(lastRedirectTo)
              }}
            />
          ) : (
            <form className="portal-auth-form" onSubmit={handleSubmit}>
              {error ? (
                <div className="portal-error">
                  <AlertCircle size={18} />
                  <span>{error}</span>
                </div>
              ) : null}

              <div className="portal-field">
                <label htmlFor="email">Email</label>
                <input className="portal-input" type="email" id="email" name="email" placeholder="email@example.com" required />
              </div>

              <div className="portal-field">
                <label htmlFor="password">Mật khẩu</label>
                <input className="portal-input" type="password" id="password" name="password" placeholder="••••••••" required />
              </div>

              <button type="submit" className="portal-button" disabled={isLoading} style={{ width: '100%', marginTop: '8px' }}>
                {isLoading ? <Loader2 size={18} className="portal-spinner" /> : 'Đăng nhập'}
              </button>
            </form>
          )}
        </div>

        {!isHandoffState ? (
          <p className="portal-auth-footer-simple">
            Chưa có tài khoản? <Link href={signupHref}>Tạo tài khoản mới</Link>
          </p>
        ) : null}
      </section>
    </main>
  )
}

export default function LoginPage() {
  return (
    <Suspense fallback={<LoginPageFallback />}>
      <LoginPageContent />
    </Suspense>
  )
}
