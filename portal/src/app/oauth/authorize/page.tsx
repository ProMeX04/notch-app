'use client'

import { Suspense, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { AlertCircle, Loader2 } from 'lucide-react'

import { PortalAppHandoffCard } from '@/components/portal/PortalAppHandoffCard'
import { PortalLogo } from '@/components/portal/PortalLogo'
import { usePortalAuth } from '@/components/portal/PortalAuthProvider'
import {
  buildPortalOAuthSearch,
  completePortalOAuthAuthorization,
  launchPortalOAuthAppRedirect,
  readPortalOAuthAuthorizeRequest,
} from '@/lib/portal-oauth-client'
import { PortalSuccessEffect } from '@/components/portal/PortalSuccessEffect'

function OAuthAuthorizeFallback() {
  return (
    <main className="portal-auth-page-centered">
      <div className="portal-auth-topbar-minimal">
        <PortalLogo />
      </div>

      <section className="portal-auth-container">
        <div className="portal-card portal-auth-card" style={{ display: 'grid', placeItems: 'center', minHeight: '280px', gap: '12px' }}>
          <Loader2 size={20} className="portal-spinner" />
          <p className="portal-muted">Đang chuẩn bị xác thực OAuth...</p>
        </div>
      </section>
    </main>
  )
}

function OAuthAuthorizeContent() {
  const searchParams = useSearchParams()
  const { status, isAuthenticated } = usePortalAuth()
  const [error, setError] = useState<string | null>(null)
  const [isRedirecting, setIsRedirecting] = useState(false)
  const [hasOpenedApp, setHasOpenedApp] = useState(false)
  const [lastRedirectTo, setLastRedirectTo] = useState<string | null>(null)
  const hasAttemptedOAuthRedirect = useRef(false)

  const oauthRequest = useMemo(() => readPortalOAuthAuthorizeRequest(searchParams), [searchParams])
  const oauthSearch = useMemo(() => buildPortalOAuthSearch(oauthRequest), [oauthRequest])
  const isHandoffState = Boolean(oauthRequest && isAuthenticated && (isRedirecting || hasOpenedApp))

  const handoffToApp = (redirectTo: string) => {
    setLastRedirectTo(redirectTo)
    hasAttemptedOAuthRedirect.current = true
    launchPortalOAuthAppRedirect(redirectTo, {
      onAppSwitch: () => {
        setHasOpenedApp(true)
        setIsRedirecting(false)
      },
      onFallback: () => {
        setHasOpenedApp(true)
        setIsRedirecting(false)
      },
    })
  }

  useEffect(() => {
    if (!oauthRequest || !isAuthenticated || hasAttemptedOAuthRedirect.current) return

    let ignore = false

    const redirectToApp = async () => {
      setIsRedirecting(true)
      setError(null)

      try {
        const redirectTo = await completePortalOAuthAuthorization(oauthRequest)
        if (!ignore) {
          handoffToApp(redirectTo)
        }
      } catch (nextError) {
        if (!ignore) {
          setError(nextError instanceof Error ? nextError.message : 'Không thể hoàn tất đăng nhập cho Notch app.')
          setIsRedirecting(false)
        }
      }
    }

    void redirectToApp()

    return () => {
      ignore = true
    }
  }, [isAuthenticated, oauthRequest])

  return (
    <main className="portal-auth-page-centered">
      {isHandoffState ? (
        <PortalSuccessEffect 
          onPrimaryAction={() => {
            if (!lastRedirectTo) {
              setHasOpenedApp(false)
              hasAttemptedOAuthRedirect.current = false
              return
            }
            handoffToApp(lastRedirectTo)
          }}
          description={isRedirecting ? 'Đang chuyển hướng bạn quay lại ứng dụng Notch...' : 'Bạn có thể đóng tab này hoặc mở lại ứng dụng bên dưới.'}
        />
      ) : (
        <>
          <div className="portal-auth-topbar-minimal">
            <PortalLogo />
          </div>

          <section className="portal-auth-container">
            <div className="portal-card portal-auth-card" style={{ display: 'grid', gap: '18px' }}>
              <div className="portal-auth-header-centered">
                <h1 className="portal-auth-title-large">Tiếp tục trong Notch</h1>
                <p className="portal-muted">
                  Mở ứng dụng để hoàn tất đăng nhập và tiếp tục.
                </p>
              </div>

              {!oauthRequest ? (
                <div className="portal-error">
                  <AlertCircle size={18} />
                  <span>Yêu cầu đăng nhập từ app không hợp lệ hoặc đã thiếu tham số PKCE.</span>
                </div>
              ) : null}

              {error ? (
                <div className="portal-error">
                  <AlertCircle size={18} />
                  <span>{error}</span>
                </div>
              ) : null}

              {oauthRequest && !isAuthenticated && status !== 'booting' ? (
                <div style={{ display: 'grid', gap: '12px' }}>
                  <Link href={`/api/auth/google${oauthSearch}`} className="portal-button" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}>
                    Tiếp tục với Google
                  </Link>
                </div>
              ) : null}

              {status === 'booting' && !isRedirecting ? (
                <div className="portal-success-view" style={{ minHeight: '140px' }}>
                  <Loader2 size={22} className="portal-spinner" />
                  <p className="portal-muted">Đang kiểm tra phiên hiện tại...</p>
                </div>
              ) : null}

              <Link href="/" className="portal-button-ghost" style={{ justifySelf: 'center' }}>
                Quay về trang chủ
              </Link>
            </div>
          </section>
        </>
      )}
    </main>
  )
}

export default function OAuthAuthorizePage() {
  return (
    <Suspense fallback={<OAuthAuthorizeFallback />}>
      <OAuthAuthorizeContent />
    </Suspense>
  )
}
