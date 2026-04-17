import { randomUUID } from 'node:crypto'
import { NextResponse } from 'next/server'
import prisma from '@/lib/prisma'
import { createVNPayPayment, getVNPayProAmount } from '@/lib/vnpay'

export async function POST(req: Request) {
  try {
    const { email } = await req.json()

    if (!email) {
      return NextResponse.json({ detail: 'Email is required.' }, { status: 400 })
    }

    // Find or create user
    let user = await prisma.user.findUnique({
      where: { email },
    })

    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          name: email.split('@')[0], // Default name from email
        },
      })
    }

    const url = new URL(req.url)
    const origin = url.origin
    const ipAddress = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || '127.0.0.1'
    const orderId = `notchpro_guest_${Date.now()}_${randomUUID().slice(0, 8)}`
    const orderInfo = `Notch Pro upgrade for ${email}`
    
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
        rawResponse: { paymentUrl: payment.paymentUrl, guest_email: email },
        userId: user.id,
      },
    })

    return NextResponse.json({
      pay_url: payment.paymentUrl,
      order_id: payment.orderId,
    })
  } catch (error) {
    console.error('Guest payment error:', error)
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Unable to create guest payment session.' },
      { status: 500 }
    )
  }
}
