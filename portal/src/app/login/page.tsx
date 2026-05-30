'use client'

import { Suspense, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { AlertCircle, Loader2 } from 'lucide-react'

import { PortalAppHandoffCard } from '@/components/portal/PortalAppHandoffCard'
import { usePortalAuth } from '@/components/portal/PortalAuthProvider'
import { PortalLogo } from '@/components/portal/PortalLogo'
import { Navbar } from '@/components/portal/Navbar'
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
  const [error, setError] = useState<string | null>(null)
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
        router.replace('/')
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
  }, [isAuthenticated, oauthRequest, router])



  return (
    <main className="portal-auth-page-centered" style={{ paddingTop: '100px' }}>
      <Navbar />

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

              <a href={`/api/auth/google${buildPortalOAuthSearch(oauthRequest)}`} className="portal-button" style={{ width: '100%', marginTop: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}>
                Tiếp tục với Google
              </a>
            </div>
          )}
        </div>


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
