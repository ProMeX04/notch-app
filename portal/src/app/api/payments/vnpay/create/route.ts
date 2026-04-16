import { randomUUID } from 'node:crypto'

import { NextResponse } from 'next/server'
import type { Prisma } from '@prisma/client'

import { getAuthenticatedUser } from '@/lib/notch-auth'
import prisma from '@/lib/prisma'
import { createVNPayPayment, getVNPayProAmount } from '@/lib/vnpay'

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  try {
    const url = new URL(req.url)
    const origin = url.origin
    const ipAddress = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || '127.0.0.1'
    const orderId = `notchpro_${Date.now()}_${randomUUID().slice(0, 8)}`
    const orderInfo = 'Notch Pro upgrade via VNPAY'
    const payment = createVNPayPayment({
      txnRef: orderId,
      orderInfo,
      returnUrl: `${origin}/billing/vnpay/return`,
      ipAddr: ipAddress,
    })

    await prisma.paymentTransaction.create({
      data: {
        provider: 'vnpay',
        status: 'pending',
        amount: getVNPayProAmount(),
        currency: 'VND',
        orderId: payment.orderId,
        requestId: payment.orderId,
        orderInfo,
        payUrl: payment.paymentUrl,
        rawResponse: { paymentUrl: payment.paymentUrl } as Prisma.InputJsonValue,
        userId: auth.user.id,
      },
    })

    return NextResponse.json({
      pay_url: payment.paymentUrl,
      order_id: payment.orderId,
    })
  } catch (error) {
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Unable to create VNPAY payment.' },
      { status: 500 }
    )
  }
}
