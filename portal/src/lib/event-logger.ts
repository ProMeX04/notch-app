import { createHash } from 'node:crypto'
import type { Prisma } from '@prisma/client'

import prisma from '@/lib/prisma'

type EventOutcome = 'success' | 'failure' | 'rejected'
type EventSource = 'web' | 'desktop' | 'oauth' | 'payment_webhook' | 'system'
type EventMetadata = Record<string, unknown>

type LogAppEventInput = {
  req?: Request
  eventType: string
  outcome: EventOutcome
  source: EventSource
  actorUserId?: string | null
  sessionId?: string | null
  deviceId?: string | null
  statusCode?: number | null
  metadata?: EventMetadata | null
}

const sensitiveKeyPattern = /(?:password|token|secret|api[-_]?key|code|verifier|signature|prompt|transcript|message|content|system[-_]?instruction|raw|url|query)/i
const maxMetadataDepth = 4
const maxStringLength = 240

export async function logAppEvent(input: LogAppEventInput): Promise<void> {
  try {
    await prisma.appEvent.create({
      data: {
        eventType: input.eventType,
        outcome: input.outcome,
        source: input.source,
        actorUserId: input.actorUserId ?? null,
        sessionId: input.sessionId ?? null,
        deviceId: input.deviceId ?? null,
        requestPath: input.req ? safeRequestPath(input.req) : null,
        requestMethod: input.req?.method ?? null,
        statusCode: input.statusCode ?? null,
        ipHash: input.req ? hashIP(readRequestIP(input.req)) : null,
        userAgent: input.req ? truncate(input.req.headers.get('user-agent') ?? '', 180) : null,
        metadata: sanitizeMetadata(input.metadata ?? null) as Prisma.InputJsonValue,
      },
    })
  } catch (error) {
    console.error('Failed to persist app event', error)
  }
}

function safeRequestPath(req: Request): string | null {
  try {
    return new URL(req.url).pathname
  } catch {
    return null
  }
}

function readRequestIP(req: Request): string | null {
  const forwarded = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
  return forwarded || req.headers.get('x-real-ip')?.trim() || null
}

function hashIP(ip: string | null): string | null {
  if (!ip) return null
  const salt = process.env.EVENT_LOG_IP_SALT || process.env.AUTH_TOKEN_SECRET || 'notch-event-log'
  return createHash('sha256').update(`${salt}:${ip}`).digest('hex')
}

function sanitizeMetadata(value: unknown, depth = 0): unknown {
  if (value === null || value === undefined) return null
  if (depth > maxMetadataDepth) return '[truncated]'

  if (typeof value === 'string') return truncate(value, maxStringLength)
  if (typeof value === 'number' || typeof value === 'boolean') return value
  if (value instanceof Date) return value.toISOString()

  if (Array.isArray(value)) {
    return value.slice(0, 25).map((item) => sanitizeMetadata(item, depth + 1))
  }

  if (typeof value === 'object') {
    const output: EventMetadata = {}
    for (const [key, item] of Object.entries(value as EventMetadata)) {
      if (sensitiveKeyPattern.test(key)) continue
      output[key] = sanitizeMetadata(item, depth + 1)
    }
    return output
  }

  return String(value)
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength)}…` : value
}
