import { useEffect, useMemo, useRef, useState } from 'react'
import { Link } from '@tanstack/react-router'
import { AlertCircle, Loader2 } from 'lucide-react'
import { PageShell } from '@/components/ui/PageShell'
import { usePortalAuth } from '@/auth/usePortalAuth'
import { getGoogleLoginUrl } from '@/auth/portal-auth-client'
import { PortalSuccessEffect } from '@/components/portal/PortalSuccessEffect'
import {
  buildPortalOAuthSearch,
  completePortalOAuthAuthorization,
  launchPortalOAuthAppRedirect,
  readPortalOAuthAuthorizeRequest,
} from '@/auth/portal-oauth-client'

export function OAuthAuthorizePage() {
  const { status, isAuthenticated } = usePortalAuth()
  // Use standard browser search params to ensure maximum compatibility and bypass strict TanStack router search validation
  const searchParams = useMemo(() => new URLSearchParams(window.location.search), [])

  const [error, setError] = useState<string | null>(() => searchParams.get('error'))
  const [isRedirecting, setIsRedirecting] = useState(false)
  const [hasOpenedApp, setHasOpenedApp] = useState(false)
  const [lastRedirectTo, setLastRedirectTo] = useState<string | null>(null)
  const hasAttemptedOAuthRedirect = useRef(false)

  const oauthRequest = useMemo(() => readPortalOAuthAuthorizeRequest(searchParams), [searchParams])
  const oauthSearch = useMemo(() => buildPortalOAuthSearch(oauthRequest), [oauthRequest])
  const isHandoffState = Boolean(oauthRequest && isAuthenticated && (isRedirecting || hasOpenedApp))

  const googleLoginUrl = useMemo(() => {
    const base = getGoogleLoginUrl()
    return oauthSearch ? `${base}&${oauthSearch.slice(1)}` : base
  }, [oauthSearch])

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



  if (isHandoffState) {
    return (
      <PortalSuccessEffect 
        description={isRedirecting ? 'Đang chuyển hướng bạn quay lại ứng dụng Notch...' : 'Bạn có thể đóng tab này hoặc mở lại ứng dụng bên dưới.'}
        onPrimaryAction={
          lastRedirectTo 
            ? () => {
                setHasOpenedApp(false)
                setIsRedirecting(true)
                handoffToApp(lastRedirectTo)
              }
            : undefined
        }
      />
    )
  }

  return (
    <PageShell>
      <main className="portal-auth-page-centered" style={{ paddingTop: '40px', minHeight: 'auto' }}>
        <section className="portal-auth-container" style={{ paddingBottom: '40px' }}>
          <div className="portal-auth-header-centered">
            <h1 className="portal-auth-title-large">Tiếp tục trong Notch</h1>
            <p className="portal-muted">
              Mở ứng dụng để hoàn tất đăng nhập và tiếp tục.
            </p>
          </div>

          <div className="portal-card portal-auth-card" style={{ display: 'grid', gap: '18px' }}>
            {!oauthRequest ? (
              <div className="portal-error" style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '12px', borderRadius: '12px', background: 'rgba(239, 68, 68, 0.05)', border: '1px solid rgba(239, 68, 68, 0.2)', color: 'var(--red)', fontSize: '0.9rem' }}>
                <AlertCircle size={18} />
                <span>Yêu cầu đăng nhập từ app không hợp lệ hoặc đã thiếu tham số PKCE.</span>
              </div>
            ) : null}

            {error ? (
              <div className="portal-error" style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '12px', borderRadius: '12px', background: 'rgba(239, 68, 68, 0.05)', border: '1px solid rgba(239, 68, 68, 0.2)', color: 'var(--red)', fontSize: '0.9rem' }}>
                <AlertCircle size={18} />
                <span>{error}</span>
              </div>
            ) : null}

            {oauthRequest && !isAuthenticated && status !== 'booting' ? (
              <div style={{ display: 'grid', gap: '12px' }}>
                <a 
                  href={googleLoginUrl} 
                  className="portal-button" 
                  style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', background: 'white', color: 'black', height: '42px', fontWeight: 600 }}
                >
                  Tiếp tục với Google
                </a>
              </div>
            ) : null}

            {status === 'booting' && !isRedirecting ? (
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', minHeight: '120px', gap: '12px' }}>
                <Loader2 size={24} className="portal-spinner animate-spin" style={{ color: 'var(--accent)' }} />
                <p className="portal-muted" style={{ fontSize: '0.9rem' }}>Đang kiểm tra phiên hiện tại...</p>
              </div>
            ) : null}

            {status === 'authenticated' && isRedirecting ? (
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', minHeight: '120px', gap: '12px' }}>
                <Loader2 size={24} className="portal-spinner animate-spin" style={{ color: 'var(--accent)' }} />
                <p className="portal-muted" style={{ fontSize: '0.9rem' }}>Đang hoàn tất xác thực ứng dụng...</p>
              </div>
            ) : null}

            <Link to="/" className="portal-button-ghost" style={{ justifySelf: 'center', border: 'none', background: 'transparent', color: 'var(--muted)', marginTop: '8px' }}>
              Quay về trang chủ
            </Link>
          </div>
        </section>
      </main>
    </PageShell>
  )
}
