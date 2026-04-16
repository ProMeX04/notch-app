import Link from 'next/link'

import { processVNPayResult, verifyVNPayPayload } from '@/lib/vnpay'

export default async function VNPayReturnPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const params = await searchParams
  const responseValue = params.vnp_ResponseCode
  const txnStatusValue = params.vnp_TransactionStatus
  const responseCode = Array.isArray(responseValue) ? responseValue[0] ?? '' : responseValue ?? ''
  const transactionStatus = Array.isArray(txnStatusValue) ? txnStatusValue[0] ?? '' : txnStatusValue ?? ''
  const normalizedParams = Object.fromEntries(
    Object.entries(params).map(([key, value]) => [key, Array.isArray(value) ? value[0] ?? '' : value ?? ''])
  )
  const hasSignature = Boolean(normalizedParams.vnp_SecureHash)
  const verified = hasSignature && verifyVNPayPayload(normalizedParams)
  const processed = verified ? await processVNPayResult(normalizedParams) : null
  const success = verified
    ? Boolean(processed?.success)
    : responseCode === '00' && transactionStatus === '00'

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '24px' }}>
      <div className="glass" style={{ width: '100%', maxWidth: '460px', padding: '32px', borderRadius: '24px', textAlign: 'center' }}>
        <div
          style={{
            width: '14px',
            height: '14px',
            borderRadius: '999px',
            margin: '0 auto 18px',
            background: success ? '#22c55e' : '#ef4444',
            boxShadow: success ? '0 0 24px rgba(34, 197, 94, 0.4)' : '0 0 24px rgba(239, 68, 68, 0.35)',
          }}
        />
        <h1 style={{ fontSize: '28px', marginBottom: '10px' }}>
          {success ? 'VNPAY payment received' : 'VNPAY payment not completed'}
        </h1>
        <p style={{ color: 'var(--muted)', lineHeight: 1.6, marginBottom: '18px' }}>
          {verified
            ? success
              ? 'VNPAY returned a successful payment result and your account has been updated.'
              : 'VNPAY returned a failed or cancelled payment result.'
            : success
              ? 'VNPAY returned a successful payment result. Go back to your account page and refresh Pro status.'
              : 'The payment was cancelled, failed, or could not be verified. You can try again from the account page.'}
        </p>
        <Link
          href="/pro"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            minWidth: '180px',
            height: '46px',
            borderRadius: '12px',
            background: 'white',
            color: 'black',
            fontWeight: 600,
          }}
        >
          Back to account
        </Link>
      </div>
    </div>
  )
}
