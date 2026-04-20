import Link from 'next/link'
import { Check, Sparkles } from 'lucide-react'

import { processVNPayResult, verifyVNPayPayload } from '@/lib/vnpay'
import prisma from '@/lib/prisma'
import { PortalLogo } from '@/components/portal/PortalLogo'

export default async function VNPayReturnPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const params = await searchParams
  const orderIdValue = params.vnp_TxnRef
  const orderId = Array.isArray(orderIdValue) ? orderIdValue[0] ?? '' : orderIdValue ?? ''

  const normalizedParams = Object.fromEntries(
    Object.entries(params).map(([key, value]) => [key, Array.isArray(value) ? value[0] ?? '' : value ?? ''])
  )
  
  const verified = Boolean(normalizedParams.vnp_SecureHash) && verifyVNPayPayload(normalizedParams)
  const processed = verified ? await processVNPayResult(normalizedParams) : null
  const success = Boolean(processed?.success)

  let needsSignup = false
  let hasLinkedAccount = false

  if (success && orderId) {
    const transaction = await prisma.paymentTransaction.findUnique({
      where: { orderId },
      select: {
        status: true,
        userId: true,
        guestEmail: true,
      },
    })

    if (transaction?.status === 'paid') {
      hasLinkedAccount = Boolean(transaction.userId)
      needsSignup = !transaction.userId && Boolean(transaction.guestEmail)
    }
  }

  return (
    <main className="portal-success-overlay">
      <div className="portal-success-bg">
        <div className={`bg-blob blob-1`} style={{ background: success ? '#dcfce7' : '#fee2e2' }}></div>
        <div className="bg-blob blob-2" style={{ background: success ? '#f0fdf4' : '#fff1f2' }}></div>
        <div className="bg-blob blob-3"></div>
      </div>

      <div className="portal-success-content">
        <div className="portal-success-glass-card">
          <div className="success-icon-container">
            <div className="success-ring-outer" style={{ borderColor: success ? '#22c55e' : '#ef4444' }}></div>
            <div className="success-ring-inner" style={{ background: success ? '#22c55e' : '#ef4444' }}></div>
            <div className="success-check-box" style={{ background: success ? '#22c55e' : '#ef4444' }}>
              {success ? (
                <Check size={40} className="success-check-icon" strokeWidth={3} />
              ) : (
                <span style={{ fontSize: '32px', fontWeight: 800 }}>!</span>
              )}
            </div>
          </div>

          <div className="success-text-container">
            <h1 className="success-title">
              {success ? 'Thanh toán thành công!' : 'Thanh toán thất bại'}
            </h1>
            <p className="success-description">
              {success 
                ? needsSignup
                  ? 'Thanh toán đã được ghi nhận. Hãy tạo tài khoản bằng đúng email đã thanh toán để kích hoạt Notch Pro.'
                  : 'Thanh toán đã được xác nhận. Hãy đăng nhập vào tài khoản của bạn để sử dụng Notch Pro.'
                : 'Giao dịch không thành công hoặc đã bị hủy. Vui lòng thử lại.'}
            </p>
          </div>

          <div className="success-footer">
            <div style={{ display: 'grid', gap: '12px' }}>
              <Link href="/pro" className="portal-button-primary-large" style={{ background: '#000', color: '#fff' }}>
                Quay về Dashboard
                <Sparkles size={18} />
              </Link>
              
              <Link href="/" className="portal-button-ghost" style={{ height: '52px', borderRadius: '999px' }}>
                Trang chủ
              </Link>
            </div>
          </div>
        </div>
      </div>
    </main>
  )
}
