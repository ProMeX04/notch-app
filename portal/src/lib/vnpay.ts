import { createHmac, timingSafeEqual } from 'node:crypto'
import type { Prisma } from '@prisma/client'

import prisma from '@/lib/prisma'

export type VNPayCreatePaymentResult = {
  paymentUrl: string
  orderId: string
}

type VNPayConfig = {
  tmnCode: string
  hashSecret: string
  paymentUrl: string
  amount: number
}

const DEFAULT_PRO_AMOUNT = 99000

function env(name: string, fallback = ''): string {
  return process.env[name]?.trim() || fallback
}

export function getVNPayConfig(): VNPayConfig | null {
  const tmnCode = env('VNPAY_TMN_CODE')
  const hashSecret = env('VNPAY_HASH_SECRET')
  const paymentUrl = env('VNPAY_PAYMENT_URL')
  if (!tmnCode || !hashSecret || !paymentUrl) {
    return null
  }

  const amount = Number.parseInt(env('VNPAY_PRO_AMOUNT', String(DEFAULT_PRO_AMOUNT)), 10)

  return {
    tmnCode,
    hashSecret,
    paymentUrl,
    amount: Number.isFinite(amount) && amount > 0 ? amount : DEFAULT_PRO_AMOUNT,
  }
}

function hmacSha512(data: string, secret: string): string {
  return createHmac('sha512', secret).update(Buffer.from(data, 'utf-8')).digest('hex')
}

function formatDate(date: Date) {
  const pad = (n: number) => String(n).padStart(2, '0')
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join('')
}

function sortObject(input: Record<string, string>) {
  return Object.keys(input)
    .sort()
    .reduce<Record<string, string>>((acc, key) => {
      acc[key] = input[key]
      return acc
    }, {})
}

function buildQuery(data: Record<string, string>) {
  return new URLSearchParams(data).toString()
}

export function getVNPayProAmount(): number {
  return getVNPayConfig()?.amount ?? DEFAULT_PRO_AMOUNT
}

export function createVNPayPayment(args: {
  txnRef: string
  orderInfo: string
  returnUrl: string
  ipAddr: string
}) {
  const config = getVNPayConfig()
  if (!config) {
    throw new Error('VNPAY is not configured on the server.')
  }

  const requestData = sortObject({
    vnp_Version: '2.1.0',
    vnp_Command: 'pay',
    vnp_TmnCode: config.tmnCode,
    vnp_Amount: String(config.amount * 100),
    vnp_CurrCode: 'VND',
    vnp_TxnRef: args.txnRef,
    vnp_OrderInfo: args.orderInfo,
    vnp_OrderType: 'other',
    vnp_Locale: 'vn',
    vnp_ReturnUrl: args.returnUrl,
    vnp_IpAddr: args.ipAddr,
    vnp_CreateDate: formatDate(new Date()),
  })

  const signData = buildQuery(requestData)
  const secureHash = hmacSha512(signData, config.hashSecret)
  const paymentParams = new URLSearchParams({
    ...requestData,
    vnp_SecureHash: secureHash,
  })

  return {
    paymentUrl: `${config.paymentUrl}?${paymentParams.toString()}`,
    orderId: args.txnRef,
  } satisfies VNPayCreatePaymentResult
}

export function verifyVNPayPayload(rawPayload: URLSearchParams | Record<string, string>) {
  const config = getVNPayConfig()
  if (!config) return false

  const entries = rawPayload instanceof URLSearchParams ? Object.fromEntries(rawPayload.entries()) : rawPayload
  const provided = entries.vnp_SecureHash?.trim()
  if (!provided) return false

  const filtered: Record<string, string> = {}
  for (const [key, value] of Object.entries(entries)) {
    if (!key.startsWith('vnp_')) continue
    if (key === 'vnp_SecureHash' || key === 'vnp_SecureHashType') continue
    filtered[key] = value
  }

  const sorted = sortObject(filtered)
  const signData = buildQuery(sorted)
  const expected = hmacSha512(signData, config.hashSecret)
  const a = Buffer.from(provided)
  const b = Buffer.from(expected)
  if (a.length != b.length) return false
  return timingSafeEqual(a, b)
}

export async function processVNPayResult(rawPayload: URLSearchParams | Record<string, string>) {
  const entries = rawPayload instanceof URLSearchParams ? Object.fromEntries(rawPayload.entries()) : rawPayload
  const orderId = entries.vnp_TxnRef ?? ''
  const responseCode = entries.vnp_ResponseCode ?? ''
  const transactionStatus = entries.vnp_TransactionStatus ?? ''
  const amount = Number(entries.vnp_Amount ?? '0') / 100

  const transaction = await prisma.paymentTransaction.findUnique({
    where: { orderId },
  })

  if (!transaction) {
    return { ok: false as const, code: '01', message: 'Order not found' }
  }

  if (transaction.amount !== amount) {
    return { ok: false as const, code: '04', message: 'Invalid amount' }
  }

  if (transaction.status === 'paid') {
    return { ok: true as const, code: '02', message: 'Order already confirmed', success: true }
  }

  const isSuccess = responseCode === '00' && transactionStatus === '00'

  await prisma.paymentTransaction.update({
    where: { id: transaction.id },
    data: {
      status: isSuccess ? 'paid' : 'failed',
      providerRef: entries.vnp_TransactionNo ?? null,
      paidAt: isSuccess ? new Date() : null,
      rawNotification: entries as unknown as Prisma.InputJsonValue,
    },
  })

  if (isSuccess) {
    await prisma.user.update({
      where: { id: transaction.userId },
      data: { isPro: true },
    })
  }

  return {
    ok: true as const,
    code: '00',
    message: isSuccess ? 'Confirm Success' : 'Payment Failed',
    success: isSuccess,
  }
}
