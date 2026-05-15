import { NextResponse } from 'next/server'

import { logAppEvent } from '@/lib/event-logger'
import { processVNPayResult, verifyVNPayPayload } from '@/lib/vnpay'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const params = url.searchParams

  if (!verifyVNPayPayload(params)) {
    await logAppEvent({
      req,
      eventType: 'payment.vnpay_ipn_rejected',
      outcome: 'rejected',
      source: 'payment_webhook',
      statusCode: 200,
      metadata: { reason: 'invalid_signature' },
    })
    return NextResponse.json({ RspCode: '97', Message: 'Invalid signature' })
  }

  const result = await processVNPayResult(params)
  await logAppEvent({
    req,
    eventType: result.success ? 'payment.vnpay_ipn_paid' : 'payment.vnpay_ipn_processed',
    outcome: result.ok ? 'success' : 'failure',
    source: 'payment_webhook',
    statusCode: 200,
    metadata: {
      rspCode: result.code,
      success: result.success === true,
      orderId: params.get('vnp_TxnRef'),
      responseCode: params.get('vnp_ResponseCode'),
      transactionStatus: params.get('vnp_TransactionStatus'),
    },
  })
  return NextResponse.json({ RspCode: result.code, Message: result.message })
}
