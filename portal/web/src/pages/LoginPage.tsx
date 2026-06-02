import { useEffect, useMemo, useRef, useState } from 'react'
import { AlertCircle, Loader2, Sparkles } from 'lucide-react'
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
    <PageShell noShell={true}>
      <main className="portal-auth-page-centered" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '100vh', padding: '20px' }}>
        
        {/* Glow backdrop behind the login card */}
        <div style={{
          position: 'absolute',
          width: '320px',
          height: '320px',
          background: 'radial-gradient(circle, rgba(99, 102, 241, 0.2) 0%, transparent 70%)',
          filter: 'blur(40px)',
          pointerEvents: 'none',
          zIndex: 0
        }} />

        <section className="portal-auth-container" style={{ paddingBottom: '0px', position: 'relative', zIndex: 1 }}>
          <div className="portal-auth-header-centered" style={{ marginBottom: '24px' }}>
            <h1 className="portal-auth-title-large" style={{ margin: 0, fontSize: '2.25rem', fontWeight: 900 }}>
              {isHandoffState ? 'Mở ứng dụng Notch' : 'Chào mừng bạn'}
            </h1>
            <p style={{ color: 'var(--muted)', fontSize: '0.95rem', marginTop: '8px', lineHeight: 1.5 }}>
              {isHandoffState
                ? 'Đang chuyển tiếp về ứng dụng của bạn...'
                : oauthRequest
                ? 'Đăng nhập một bước để liên kết tài khoản với Notch.'
                : 'Truy cập Notch Portal để thiết lập đồng bộ hóa.'}
            </p>
          </div>

          <div className="portal-auth-card">
            <style>{`
              @keyframes spin { to { transform: rotate(360deg) } }
              @keyframes portalFloat {
                0%, 100% { transform: translateY(0); }
                50% { transform: translateY(-8px); }
              }
            `}</style>

            {/* Custom Welcome Animated Sphere */}
            {!isHandoffState && (
              <div style={{ display: 'flex', justifyContent: 'center', marginBottom: '28px' }}>
                <div style={{
                  position: 'relative',
                  width: 80,
                  height: 80,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  background: 'linear-gradient(135deg, rgba(99, 102, 241, 0.12) 0%, rgba(56, 189, 248, 0.12) 100%)',
                  border: '1px solid rgba(99, 102, 241, 0.2)',
                  borderRadius: '50%',
                  boxShadow: '0 8px 24px rgba(99, 102, 241, 0.15)',
                  animation: 'portalFloat 4s infinite ease-in-out'
                }}>
                  <div style={{
                    position: 'absolute',
                    inset: -5,
                    borderRadius: '50%',
                    border: '1px dashed rgba(56, 189, 248, 0.3)',
                    animation: 'spin 12s linear infinite'
                  }} />
                  <Sparkles size={28} style={{ color: '#38bdf8', filter: 'drop-shadow(0 0 6px rgba(56, 189, 248, 0.5))' }} />
                </div>
              </div>
            )}

            {hasOpenedApp && oauthRequest ? (
              <PortalAppHandoffCard
                mode="ready"
                title="Đang tiếp tục trong Notch"
                description="Bạn đã có thể đóng cửa sổ trình duyệt này một cách an toàn."
                primaryLabel="Thử mở lại Notch"
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
                  <div style={{ display: 'grid', placeItems: 'center', minHeight: '80px', gap: '12px', textAlign: 'center' }}>
                    <Loader2 size={24} className="animate-spin" style={{ color: 'var(--accent)' }} />
                    <p style={{ color: 'var(--muted)', fontSize: '0.9rem', margin: 0 }}>Đang xác thực phiên hiện tại...</p>
                  </div>
                ) : (
                  <a
                    href={`/api/auth/google${buildPortalOAuthSearch(oauthRequest)}`}
                    className="portal-button"
                    style={{ 
                      width: '100%', 
                      marginTop: '8px', 
                      display: 'inline-flex', 
                      alignItems: 'center', 
                      justifyContent: 'center', 
                      gap: '12px',
                      height: '52px',
                      background: '#ffffff',
                      color: '#030712',
                      borderRadius: '999px',
                      fontWeight: 800,
                      fontSize: '1rem',
                      boxShadow: '0 8px 24px rgba(255, 255, 255, 0.1)',
                      border: 'none',
                      transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)'
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.transform = 'translateY(-2px)'
                      e.currentTarget.style.boxShadow = '0 12px 28px rgba(255, 255, 255, 0.18)'
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.transform = 'translateY(0)'
                      e.currentTarget.style.boxShadow = '0 8px 24px rgba(255, 255, 255, 0.1)'
                    }}
                  >
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                      <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
                      <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
                      <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z" fill="#FBBC05"/>
                      <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z" fill="#EA4335"/>
                    </svg>
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
