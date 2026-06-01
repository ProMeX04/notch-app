import { useEffect, useMemo, useState } from 'react'
import { Link } from '@tanstack/react-router'
import { Check, Loader2, AlertTriangle, Sparkles } from 'lucide-react'
import { useQueryClient } from '@tanstack/react-query'
import { apiClient } from '@/api/client'
import { launchPortalOAuthAppRedirect } from '@/auth/portal-oauth-client'
import { AUTH_ME_QUERY_KEY } from '@/auth/auth-query'

type VerificationResponse = {
  verified: boolean
  success: boolean
  needs_signup: boolean
}

export function VNPayReturnPage() {
  const queryClient = useQueryClient()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<VerificationResponse | null>(null)

  // Use standard browser search params to ensure maximum compatibility and bypass strict TanStack router search validation
  const searchParams = useMemo(() => new URLSearchParams(window.location.search), [])

  const launchRedirect = () => {
    try {
      launchPortalOAuthAppRedirect('notch://visibility/show', {
        onAppSwitch: () => {
          console.log('Successfully switched back to Notch desktop app')
        },
        onFallback: () => {
          console.log('App redirect fallback triggered')
        },
      })
    } catch (e) {
      console.error('Failed to trigger native deep link', e)
    }
  }

  useEffect(() => {
    let ignore = false

    const verifyPayment = async () => {
      try {
        const response = await apiClient.get<VerificationResponse>('/api/payments/vnpay/return', {
          params: Object.fromEntries(searchParams.entries()),
        })

        if (!ignore) {
          setResult(response.data)
          setLoading(false)

          // If the payment is successful, trigger automatic deep link redirect back to the desktop application
          if (response.data.success) {
            // Invalidate auth query to ensure the client updates its Pro/Pro-badge status immediately
            void queryClient.invalidateQueries({ queryKey: AUTH_ME_QUERY_KEY })

            // Delay slightly to let the UI render first and show the success state
            setTimeout(() => {
              if (!ignore) {
                launchRedirect()
              }
            }, 600)
          }
        }
      } catch (err) {
        if (!ignore) {
          setError(err instanceof Error ? err.message : 'Đã xảy ra lỗi khi xác minh thanh toán.')
          setLoading(false)
        }
      }
    }

    void verifyPayment()

    return () => {
      ignore = true
    }
  }, [searchParams])

  if (loading) {
    return (
      <main className="portal-success-overlay">
        <div className="portal-success-bg">
          <div className="bg-blob blob-1"></div>
          <div className="bg-blob blob-2"></div>
          <div className="bg-blob blob-3"></div>
        </div>

        <div className="portal-success-content">
          <div className="portal-success-glass-card" style={{ padding: '60px 48px' }}>
            <Loader2 size={48} className="portal-spinner animate-spin" style={{ color: 'var(--accent)', marginBottom: '24px' }} />
            <h1 className="success-title" style={{ fontSize: '1.8rem', fontWeight: 700 }}>Xác thực thanh toán...</h1>
            <p className="success-description">Vui lòng chờ trong giây lát khi chúng tôi xác minh giao dịch của bạn.</p>
          </div>
        </div>
      </main>
    )
  }

  const isSuccess = Boolean(result?.success)
  const needsSignup = Boolean(result?.needs_signup)

  return (
    <main className={`portal-success-overlay ${isSuccess ? 'is-success' : 'is-error'}`}>
      <div className="portal-success-bg">
        <div className="bg-blob blob-1"></div>
        <div className="bg-blob blob-2"></div>
        <div className="bg-blob blob-3"></div>
      </div>

      <div className="portal-success-content">
        <div className="portal-success-glass-card">
          <div className="success-icon-container">
            <div className="success-ring-outer"></div>
            <div className="success-ring-inner"></div>
            <div className="success-check-box">
              {isSuccess ? (
                <Check size={40} className="success-check-icon" strokeWidth={3} />
              ) : (
                <AlertTriangle size={40} className="success-check-icon" strokeWidth={2} style={{ color: 'white' }} />
              )}
            </div>
          </div>

          <div className="success-text-container">
            <h1 className="success-title">
              {isSuccess ? 'Thanh toán thành công!' : 'Thanh toán thất bại'}
            </h1>
            <p className="success-description">
              {error ? (
                `Lỗi: ${error}`
              ) : isSuccess ? (
                needsSignup ? (
                  'Thanh toán đã được ghi nhận. Hãy tạo tài khoản bằng đúng email đã thanh toán để kích hoạt Notch Pro.'
                ) : (
                  'Thanh toán đã được xác nhận. Hãy quay lại tài khoản của bạn để sử dụng Notch Pro.'
                )
              ) : (
                'Giao dịch không thành công hoặc đã bị hủy. Vui lòng thử lại.'
              )}
            </p>
          </div>

          <div className="success-footer">
            <div style={{ display: 'grid', gap: '12px', width: '100%' }}>
              {isSuccess ? (
                <>
                  <button
                    onClick={launchRedirect}
                    className="portal-button-primary-large"
                  >
                    Mở lại ứng dụng Notch
                    <Sparkles size={18} />
                  </button>
                  <Link
                    to="/account"
                    className="portal-button-ghost"
                  >
                    Về Trang cá nhân
                  </Link>
                </>
              ) : (
                <>
                  <Link
                    to="/upgrade"
                    className="portal-button-primary-large"
                  >
                    Thử thanh toán lại
                  </Link>
                  <Link
                    to="/"
                    className="portal-button-ghost"
                  >
                    Trang chủ
                  </Link>
                </>
              )}
            </div>
          </div>
        </div>

        {isSuccess && (
          <div className="portal-success-hints">
            <p>Trình duyệt đã gửi lệnh mở lại ứng dụng Notch để đồng bộ nâng cấp Pro của bạn.</p>
          </div>
        )}
      </div>
    </main>
  )
}
