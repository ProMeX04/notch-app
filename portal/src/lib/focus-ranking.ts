import { Prisma } from '@prisma/client'

export type FocusSyncInput = {
  date: string
  focus_seconds: number
  session_count: number
}

export type FocusWindow = 'week' | 'all'

const maxBatchSize = 120
const maxSecondsPerDay = 24 * 60 * 60
const maxSessionCountPerDay = 500
const publicLeaderboardLimit = 50

export function startOfUTCDay(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()))
}

export function startOfUTCWeek(referenceDate: Date) {
  const dayStart = startOfUTCDay(referenceDate)
  const day = dayStart.getUTCDay()
  const mondayOffset = day === 0 ? -6 : 1 - day
  return new Date(dayStart.getTime() + mondayOffset * 24 * 60 * 60 * 1000)
}

export function parseFocusWindow(rawValue: string | null): FocusWindow {
  return rawValue === 'all' ? 'all' : 'week'
}

export function normalizeDisplayName(value: unknown) {
  if (typeof value !== 'string') return null
  const normalized = value.trim().replace(/\s+/g, ' ')
  if (!normalized) return null
  return normalized.slice(0, 80)
}

export function maskedEmail(email: string | null | undefined) {
  if (!email) return 'Notch user'
  const [localPart, domain] = email.split('@')
  if (!localPart || !domain) return 'Notch user'
  const visible = localPart.slice(0, Math.min(localPart.length, 2))
  return `${visible}${localPart.length > 2 ? '***' : '*'}@${domain}`
}

export function publicLeaderboardName(user: { displayName: string | null; email: string | null }) {
  return user.displayName?.trim() || maskedEmail(user.email)
}

export function validateFocusSyncEntries(value: unknown): FocusSyncInput[] {
  if (!value || typeof value !== 'object' || (value as { schema_version?: unknown }).schema_version !== 2) {
    throw new Error('Unsupported focus sync schema version.')
  }
  const entries = Array.isArray((value as { entries?: unknown }).entries)
    ? (value as { entries: unknown[] }).entries
    : null

  if (!entries) {
    throw new Error('Expected an entries array.')
  }
  if (entries.length > maxBatchSize) {
    throw new Error(`A sync batch may contain at most ${maxBatchSize} entries.`)
  }

  return entries.map((entry, index) => {
    if (!entry || typeof entry !== 'object') {
      throw new Error(`Entry ${index + 1} is invalid.`)
    }

    const raw = entry as Record<string, unknown>
    const date = typeof raw.date === 'string' ? raw.date.trim() : ''
    if (!isValidUTCDateKey(date)) {
      throw new Error(`Entry ${index + 1} has an invalid date.`)
    }
    if (Object.prototype.hasOwnProperty.call(raw, 'device_id')) {
      throw new Error(`Entry ${index + 1} must not provide device_id.`)
    }

    const focusSeconds = Number(raw.focus_seconds)
    const sessionCount = Number(raw.session_count)
    if (!Number.isInteger(focusSeconds) || focusSeconds < 0 || focusSeconds > maxSecondsPerDay) {
      throw new Error(`Entry ${index + 1} has invalid focus_seconds.`)
    }
    if (!Number.isInteger(sessionCount) || sessionCount < 0 || sessionCount > maxSessionCountPerDay) {
      throw new Error(`Entry ${index + 1} has invalid session_count.`)
    }

    return {
      date,
      focus_seconds: focusSeconds,
      session_count: sessionCount,
    }
  })
}

export function focusDateFromKey(dateKey: string) {
  return new Date(`${dateKey}T00:00:00.000Z`)
}

export async function syncFocusDailyStats(userId: string, entries: FocusSyncInput[], deviceId: string) {
  if (entries.length === 0) {
    return { synced: 0 }
  }

  const prisma = await getPrisma()
  const values = entries.map((entry) => Prisma.sql`(
    ${crypto.randomUUID()},
    ${userId},
    ${focusDateFromKey(entry.date)},
    ${deviceId},
    ${entry.focus_seconds},
    ${entry.session_count},
    NOW(),
    NOW()
  )`)

  await prisma.$executeRaw(Prisma.sql`
    INSERT INTO "FocusDailyStat" (
      "id",
      "userId",
      "date",
      "deviceId",
      "focusSeconds",
      "sessionCount",
      "createdAt",
      "updatedAt"
    )
    VALUES ${Prisma.join(values)}
    ON CONFLICT ("userId", "date", "deviceId")
    DO UPDATE SET
      "focusSeconds" = GREATEST("FocusDailyStat"."focusSeconds", EXCLUDED."focusSeconds"),
      "sessionCount" = GREATEST("FocusDailyStat"."sessionCount", EXCLUDED."sessionCount"),
      "updatedAt" = NOW()
  `)

  return { synced: entries.length }
}

function isValidUTCDateKey(dateKey: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return false
  const parsed = focusDateFromKey(dateKey)
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === dateKey
}

export async function readFocusSummary(userId: string, now = new Date()) {
  const prisma = await getPrisma()
  const weekStart = startOfUTCWeek(now)
  const [allTime, week] = await Promise.all([
    prisma.focusDailyStat.aggregate({
      where: { userId },
      _sum: { focusSeconds: true, sessionCount: true },
    }),
    prisma.focusDailyStat.aggregate({
      where: { userId, date: { gte: weekStart } },
      _sum: { focusSeconds: true, sessionCount: true },
    }),
  ])

  return {
    week: {
      focus_seconds: allOrZero(week._sum.focusSeconds),
      session_count: allOrZero(week._sum.sessionCount),
      starts_at: weekStart.toISOString().slice(0, 10),
    },
    all_time: {
      focus_seconds: allOrZero(allTime._sum.focusSeconds),
      session_count: allOrZero(allTime._sum.sessionCount),
    },
  }
}

export async function readFocusLeaderboard(window: FocusWindow, now = new Date()) {
  const prisma = await getPrisma()
  const where: Prisma.FocusDailyStatWhereInput = window === 'week'
    ? { date: { gte: startOfUTCWeek(now) } }
    : {}

  const rows = await prisma.focusDailyStat.groupBy({
    by: ['userId'],
    where: {
      ...where,
      user: { leaderboardOptIn: true },
    },
    _sum: { focusSeconds: true, sessionCount: true },
    orderBy: { _sum: { focusSeconds: 'desc' } },
    take: publicLeaderboardLimit,
  })

  const users = await prisma.user.findMany({
    where: { id: { in: rows.map((row) => row.userId) }, leaderboardOptIn: true },
    select: { id: true, displayName: true, email: true },
  })
  const usersById = new Map(users.map((user) => [user.id, user]))

  return rows.map((row, index) => {
    const user = usersById.get(row.userId)
    return {
      rank: index + 1,
      user_id: row.userId,
      display_name: user ? publicLeaderboardName(user) : 'Notch user',
      focus_seconds: allOrZero(row._sum.focusSeconds),
      session_count: allOrZero(row._sum.sessionCount),
    }
  })
}

function allOrZero(value: number | null | undefined) {
  return value ?? 0
}

async function getPrisma() {
  const prismaModule = await import('@/lib/prisma')
  return prismaModule.default
}
