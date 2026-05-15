import { NextResponse } from "next/server";

import prisma from "@/lib/prisma";
import { requireAdminUser } from "@/lib/notch-auth";

type RouteContext = {
  params: Promise<{ id: string }>;
};

function sessionStatus(session: { revokedAt: Date | null; expiresAt: Date }) {
  if (session.revokedAt) return "revoked";
  if (session.expiresAt <= new Date()) return "expired";
  return "active";
}

function accountAgeDays(createdAt: Date) {
  return Math.max(Math.floor((Date.now() - createdAt.getTime()) / (24 * 60 * 60 * 1000)), 0);
}

async function readUserEvents(userId: string) {
  try {
    return await prisma.appEvent.findMany({
      where: { actorUserId: userId },
      select: {
        id: true,
        createdAt: true,
        eventType: true,
        outcome: true,
        source: true,
        sessionId: true,
        deviceId: true,
        requestPath: true,
        requestMethod: true,
        statusCode: true,
        userAgent: true,
        metadata: true,
      },
      orderBy: { createdAt: "desc" },
      take: 50,
    });
  } catch (error) {
    console.error("Failed to fetch admin user events", error);
    return [];
  }
}

export async function GET(req: Request, context: RouteContext) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const { id } = await context.params;
    const user = await prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        name: true,
        email: true,
        isPro: true,
        isAdmin: true,
        createdAt: true,
        updatedAt: true,
        sessions: {
          select: {
            id: true,
            deviceId: true,
            deviceName: true,
            platform: true,
            expiresAt: true,
            accessExpiresAt: true,
            createdAt: true,
            lastSeenAt: true,
            trustedAt: true,
            updatedAt: true,
            revokedAt: true,
            revokedReason: true,
          },
          orderBy: { lastSeenAt: "desc" },
          take: 50,
        },
        payments: {
          select: {
            id: true,
            provider: true,
            status: true,
            amount: true,
            currency: true,
            orderId: true,
            requestId: true,
            providerRef: true,
            orderInfo: true,
            createdAt: true,
            updatedAt: true,
            paidAt: true,
            guestEmail: true,
          },
          orderBy: { createdAt: "desc" },
          take: 50,
        },
      },
    });

    if (!user) {
      return NextResponse.json({ error: "User not found" }, { status: 404 });
    }

    const events = await readUserEvents(user.id);
    const paidPayments = user.payments.filter((payment) => payment.status === "paid");
    const activeSessions = user.sessions.filter((session) => sessionStatus(session) === "active");
    const revokedSessions = user.sessions.filter((session) => sessionStatus(session) === "revoked");
    const expiredSessions = user.sessions.filter((session) => sessionStatus(session) === "expired");
    const trustedDeviceCount = new Set(
      user.sessions
        .filter((session) => Boolean(session.trustedAt))
        .map((s) => s.deviceId)
        .filter(Boolean)
    ).size;
    const failureEvents = events.filter((event) => event.outcome === "failure" || event.outcome === "rejected");
    const eventTypeCounts = new Map<string, number>();

    for (const event of events) {
      eventTypeCounts.set(event.eventType, (eventTypeCounts.get(event.eventType) ?? 0) + 1);
    }

    return NextResponse.json({
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        isPro: user.isPro,
        isAdmin: user.isAdmin,
        createdAt: user.createdAt,
        updatedAt: user.updatedAt,
      },
      summary: {
        accountAgeDays: accountAgeDays(user.createdAt),
        lastSeenAt: user.sessions[0]?.lastSeenAt ?? null,
        activeSessionCount: activeSessions.length,
        revokedSessionCount: revokedSessions.length,
        expiredSessionCount: expiredSessions.length,
        trustedDeviceCount,
        paidPaymentCount: paidPayments.length,
        totalPaidRevenue: paidPayments.reduce((sum, payment) => sum + payment.amount, 0),
        latestPaymentAt: user.payments[0]?.createdAt ?? null,
        recentFailureEventCount: failureEvents.length,
        topEventTypes: Array.from(eventTypeCounts.entries())
          .sort((a, b) => b[1] - a[1])
          .slice(0, 6)
          .map(([eventType, count]) => ({ eventType, count })),
      },
      sessions: user.sessions.map((session) => ({
        id: session.id,
        deviceId: session.deviceId,
        deviceName: session.deviceName,
        platform: session.platform,
        status: sessionStatus(session),
        expiresAt: session.expiresAt,
        accessExpiresAt: session.accessExpiresAt,
        createdAt: session.createdAt,
        lastSeenAt: session.lastSeenAt,
        trustedAt: session.trustedAt,
        updatedAt: session.updatedAt,
        revokedAt: session.revokedAt,
        revokedReason: session.revokedReason,
      })),
      payments: user.payments,
      events,
    });
  } catch (error) {
    console.error("Failed to fetch admin user detail", error);
    return NextResponse.json({ error: "Failed to fetch user" }, { status: 500 });
  }
}
