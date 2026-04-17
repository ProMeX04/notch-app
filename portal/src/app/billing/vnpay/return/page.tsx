import Link from 'next/link'
import { Check, Key, Sparkles } from 'lucide-react'

import { processVNPayResult, verifyVNPayPayload } from '@/lib/vnpay'
import prisma from '@/lib/prisma'
import { createAuthPayload } from '@/lib/notch-auth'
import { PortalLogo } from '@/components/portal/PortalLogo'

export default async function VNPayReturnPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const params = await searchParams
  const responseValue = params.vnp_ResponseCode
  const txnStatusValue = params.vnp_TransactionStatus
  const orderIdValue = params.vnp_TxnRef
  
  const responseCode = Array.isArray(responseValue) ? responseValue[0] ?? '' : responseValue ?? ''
  const transactionStatus = Array.isArray(txnStatusValue) ? txnStatusValue[0] ?? '' : txnStatusValue ?? ''
  const orderId = Array.isArray(orderIdValue) ? orderIdValue[0] ?? '' : orderIdValue ?? ''

  const normalizedParams = Object.fromEntries(
    Object.entries(params).map(([key, value]) => [key, Array.isArray(value) ? value[0] ?? '' : value ?? ''])
  )
  
  const hasSignature = Boolean(normalizedParams.vnp_SecureHash)
  const verified = hasSignature && verifyVNPayPayload(normalizedParams)
  const processed = verified ? await processVNPayResult(normalizedParams) : null
  const success = verified
    ? Boolean(processed?.success)
    : responseCode === '00' && transactionStatus === '00'

  let authPayload = null
  let userEmail = ''

  if (success && orderId) {
    const transaction = await prisma.paymentTransaction.findUnique({
      where: { orderId },
      include: { user: true }
    })
    
    if (transaction?.user) {
      userEmail = transaction.user.email ?? ''
      authPayload = await createAuthPayload(transaction.user)
    }
  }

  return (
    <main className="portal-auth-page-centered">
      <div className="portal-auth-topbar-minimal">
        <PortalLogo />
      </div>

      <section className="portal-auth-container" style={{ maxWidth: '480px' }}>
        <div className="portal-card portal-auth-card" style={{ textAlign: 'center', padding: '40px 32px' }}>
          <div
            style={{
              width: '64px',
              height: '64px',
              borderRadius: '20px',
              margin: '0 auto 24px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              background: success ? 'rgba(34, 197, 94, 0.1)' : 'rgba(239, 68, 68, 0.1)',
              color: success ? '#22c55e' : '#ef4444',
            }}
          >
            {success ? <Check size={32} strokeWidth={3} /> : <div style={{ fontSize: '32px', fontWeight: 'bold' }}>!</div>}
          </div>

          <h1 className="portal-auth-title-large" style={{ marginBottom: '12px' }}>
            {success ? 'Thanh toán thành công!' : 'Thanh toán thất bại'}
          </h1>
          
          <p className="portal-muted" style={{ marginBottom: '24px' }}>
            {success 
              ? `Tài khoản ${userEmail} đã được nâng cấp lên Notch Pro.` 
              : 'Giao dịch không thành công hoặc đã bị hủy. Vui lòng thử lại.'}
          </p>

          {success && authPayload && (
            <div style={{ textAlign: 'left', marginTop: '32px' }}>
              <div className="portal-divider" />
              <div style={{ marginTop: '24px' }}>
                <h3 style={{ fontSize: '14px', fontWeight: 600, marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <Key size={14} />
                  Mã kích hoạt trên Notch app
                </h3>
                <p className="portal-muted" style={{ fontSize: '13px', marginBottom: '16px' }}>
                  Sao chép mã này và dán vào phần Login trong app Notch trên Mac của bạn.
                </p>
                
                <div className="portal-token-box" style={{ background: 'var(--card-bg-subtle)', border: '1px solid var(--border-subtle)' }}>
                  <code style={{ fontSize: '12px', wordBreak: 'break-all' }}>{authPayload.session_token}</code>
                </div>
                
                <p style={{ fontSize: '12px', marginTop: '12px', opacity: 0.6 }}>
                  Gợi ý: Bạn có thể đăng nhập vào web portal sau này bằng email {userEmail}.
                  Nếu chưa đặt mật khẩu, hãy sử dụng tính năng &ldquo;Quên mật khẩu&rdquo;.
                </p>
              </div>
            </div>
          )}

          <div style={{ display: 'grid', gap: '12px', marginTop: '32px' }}>
            {success ? (
              <Link href="/pro" className="portal-button-primary-large">
                Vào trang quản lý tài khoản
                <Sparkles size={18} />
              </Link>
            ) : (
              <Link href="/pricing" className="portal-button">
                Thử lại
              </Link>
            )}
            <Link href="/" className="portal-button-ghost">
              Quay về trang chủ
            </Link>
          </div>
        </div>
      </section>
    </main>
  )
}
