import { NextResponse } from 'next/server'

import { processVNPayResult, verifyVNPayPayload } from '@/lib/vnpay'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const params = url.searchParams

  if (!verifyVNPayPayload(params)) {
    return NextResponse.json({ RspCode: '97', Message: 'Invalid signature' })
  }

  const result = await processVNPayResult(params)
  return NextResponse.json({ RspCode: result.code, Message: result.message })
}
