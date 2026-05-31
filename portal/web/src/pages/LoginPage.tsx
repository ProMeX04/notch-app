import { useEffect, useMemo, useRef, useState } from 'react'
import { AlertCircle, Loader2 } from 'lucide-react'
import { PageShell } from '@/components/ui/PageShell'
import { usePortalAuth } from '@/auth/usePortalAuth'
import { PortalAppHandoffCard } from '@/components/portal/PortalAppHandoffCard'
import {
  buildPortalOAuthSearch,
  completePortalOAuthAuthorization,
  launchPortalOAuthAppRedirect,
  readPortalOAuthAuthorizeRequest,
} from '@/auth/portal-oauth-client'

export function LoginPage() {
  const { isAuthenticated, status } = usePortalAuth()
  // Use standard browser search params to ensure maximum compatibility and bypass strict TanStack router search validation
  const searchParams = useMemo(() => new URLSearchParams(window.location.search), [])

  const [error, setError] = useState<string | null>(() => searchParams.get('error'))
  const [hasOpenedApp, setHasOpenedApp] = useState(false)
  const [lastRedirectTo, setLastRedirectTo] = useState<string | null>(null)
  const hasAttemptedOAuthRedirect = useRef(false)

  const oauthRequest = useMemo(() => readPortalOAuthAuthorizeRequest(searchParams), [searchParams])
  const isHandoffState = Boolean(oauthRequest && hasOpenedApp)

  const handoffToApp = (redirectTo: string) => {
    setLastRedirectTo(redirectTo)
    hasAttemptedOAuthRedirect.current = true
    launchPortalOAuthAppRedirect(redirectTo, {
      onAppSwitch: () => {
        setHasOpenedApp(true)
      },
      onFallback: () => {
        setHasOpenedApp(true)
      },
    })
  }

  useEffect(() => {
    if (!isAuthenticated || hasAttemptedOAuthRedirect.current) return

    let ignore = false

    const continueFlow = async () => {
      if (!oauthRequest) {
        // Redirect to homepage if logged in but no oauth request
        window.location.replace('/')
        return
      }

      setError(null)

      try {
        const redirectTo = await completePortalOAuthAuthorization(oauthRequest)
        if (!ignore) {
          handoffToApp(redirectTo)
        }
      } catch (nextError) {
        if (!ignore) {
          setError(nextError instanceof Error ? nextError.message : 'Không thể hoàn tất đăng nhập cho Notch app.')
        }
      }
    }

    void continueFlow()

    return () => {
      ignore = true
    }
  }, [isAuthenticated, oauthRequest])



  return (
    <PageShell>
      <main className="portal-auth-page-centered" style={{ paddingTop: '40px', minHeight: 'auto' }}>
        <section className="portal-auth-container" style={{ paddingBottom: '40px' }}>
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
                  handoffToApp(lastRedirectTo)
                }}
              />
            ) : (
              <div className="portal-auth-form">
                {error ? (
                  <div className="portal-error">
                    <AlertCircle size={18} />
                    <span>{error}</span>
                  </div>
                ) : null}

                {status === 'booting' ? (
                  <div style={{ display: 'grid', placeItems: 'center', minHeight: '60px', gap: '8px' }}>
                    <Loader2 size={20} className="portal-spinner" />
                    <p className="portal-muted">Đang kiểm tra phiên hiện tại...</p>
                  </div>
                ) : (
                  <a
                    href={`/api/auth/google${buildPortalOAuthSearch(oauthRequest)}`}
                    className="portal-button"
                    style={{ width: '100%', marginTop: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}
                  >
                    Tiếp tục với Google
                  </a>
                )}
              </div>
            )}
          </div>
        </section>
      </main>
    </PageShell>
  )
}
