import { useState } from 'react'
import { Sparkles, ArrowRight, Check, Loader2 } from 'lucide-react'

import { PageShell } from '@/components/ui/PageShell'
import { apiClient } from '@/api/client'
import { usePortalAuth } from '@/auth/usePortalAuth'

export function UpgradePage() {
  const { isAuthenticated } = usePortalAuth()
  const [isCheckoutLoading, setIsCheckoutLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const startCheckout = async () => {
    setIsCheckoutLoading(true)
    setError(null)
    try {
      const response = await apiClient.post<{ pay_url: string }>('/api/payments/vnpay/create')
      window.location.href = response.data.pay_url
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không thể tạo phiên thanh toán VNPAY.')
      setIsCheckoutLoading(false)
    }
  }

  return (
    <PageShell>
      <main style={{ minHeight: '80vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <section className="portal-card" style={{ maxWidth: '480px', width: '100%', padding: '40px' }}>
          <div style={{ textAlign: 'center', marginBottom: '24px' }}>
            <span className="portal-badge" style={{ 
              marginBottom: '16px', 
              background: 'rgba(56, 189, 248, 0.1)', 
              color: 'var(--accent)', 
              border: '1px solid rgba(56, 189, 248, 0.2)',
              borderRadius: '999px',
              padding: '6px 14px',
              fontSize: '0.85rem',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '6px'
            }}>
              <Sparkles size={14} />
              Notch Pro Upgrade
            </span>
            <h1 style={{ fontSize: '2.5rem', fontWeight: 900, letterSpacing: '-0.05em', margin: '0 0 12px 0' }}>
              {isAuthenticated ? 'Nâng cấp Notch Pro' : 'Cần tài khoản để nâng cấp'}
            </h1>
            <p style={{ color: 'var(--muted)', fontSize: '1rem', lineHeight: '1.5', margin: 0 }}>
              {isAuthenticated 
                ? 'Thanh toán một lần duy nhất qua VNPAY để mở khóa vĩnh viễn toàn bộ tính năng cao cấp.' 
                : 'Luồng thanh toán guest đã được tắt. Hãy đăng ký hoặc đăng nhập tài khoản trước khi thanh toán.'
              }
            </p>
          </div>

          {error && (
            <div style={{ 
              background: 'rgba(239, 68, 68, 0.1)', 
              border: '1px solid rgba(239, 68, 68, 0.2)', 
              color: '#ef4444', 
              padding: '12px', 
              borderRadius: '12px', 
              fontSize: '0.9rem', 
              marginBottom: '20px' 
            }}>
              {error}
            </div>
          )}

          <div style={{ display: 'grid', gap: '14px', marginBottom: '32px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <Check size={14} />
              </div>
              <span>Giá chỉ 99,000 VND</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <Check size={14} />
              </div>
              <span>Dùng vĩnh viễn không gia hạn</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <Check size={14} />
              </div>
              <span>Mở khóa toàn bộ tính năng Pro & AI</span>
            </div>
          </div>

          <div style={{ display: 'grid' }}>
            {isAuthenticated ? (
              <button 
                type="button" 
                className="portal-button" 
                onClick={() => void startCheckout()}
                disabled={isCheckoutLoading}
                style={{ 
                  width: '100%', 
                  height: '60px', 
                  borderRadius: '18px', 
                  fontSize: '1.1rem', 
                  fontWeight: 600,
                  display: 'flex', 
                  alignItems: 'center', 
                  justifyContent: 'center', 
                  gap: '8px',
                  background: 'white',
                  color: 'black',
                  border: 'none',
                  cursor: 'pointer'
                }}
              >
                {isCheckoutLoading ? (
                  <>
                    <Loader2 size={20} className="animate-spin" />
                    Đang chuyển hướng...
                  </>
                ) : (
                  <>
                    Thanh toán qua VNPAY
                    <ArrowRight size={20} />
                  </>
                )}
              </button>
            ) : (
              <a 
                href="/api/auth/google" 
                className="portal-button" 
                style={{ 
                  width: '100%', 
                  height: '60px', 
                  borderRadius: '18px', 
                  fontSize: '1.1rem', 
                  fontWeight: 600,
                  display: 'flex', 
                  alignItems: 'center', 
                  justifyContent: 'center', 
                  gap: '8px',
                  textDecoration: 'none',
                  background: 'white',
                  color: 'black'
                }}
              >
                Đăng nhập với Google để nâng cấp
                <ArrowRight size={20} />
              </a>
            )}
          </div>
        </section>
      </main>
    </PageShell>
  )
}

