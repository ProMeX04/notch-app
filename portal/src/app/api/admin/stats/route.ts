import { NextResponse } from "next/server";
import prisma from "@/lib/prisma";
import { requireAdminUser } from "@/lib/notch-auth";

const dayMs = 24 * 60 * 60 * 1000;

type DailyMetric = {
  date: string;
  users: number;
  paidTransactions: number;
  revenue: number;
  events: number;
};

function startOfDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function dateKey(date: Date) {
  return date.toISOString().slice(0, 10);
}

function buildDailyMetrics(start: Date, days: number): DailyMetric[] {
  return Array.from({ length: days }, (_, index) => {
    const date = new Date(start.getTime() + index * dayMs);
    return {
      date: dateKey(date),
      users: 0,
      paidTransactions: 0,
      revenue: 0,
      events: 0,
    };
  });
}

async function readEventStats(sevenDaysAgo: Date, trendStart: Date) {
  try {
    const [recentRejectedEvents, recentFailedEvents, recentEvents, trendEvents] = await Promise.all([
      prisma.appEvent.count({ where: { outcome: "rejected", createdAt: { gte: sevenDaysAgo } } }),
      prisma.appEvent.count({ where: { outcome: "failure", createdAt: { gte: sevenDaysAgo } } }),
      prisma.appEvent.findMany({
        select: {
          id: true,
          createdAt: true,
          eventType: true,
          outcome: true,
          source: true,
          requestPath: true,
          requestMethod: true,
          statusCode: true,
          actorUserId: true,
          actorUser: {
            select: {
              name: true,
              email: true,
            },
          },
        },
        orderBy: { createdAt: "desc" },
        take: 12,
      }),
      prisma.appEvent.findMany({
        select: { createdAt: true },
        where: { createdAt: { gte: trendStart } },
      }),
    ]);

    return { recentRejectedEvents, recentFailedEvents, recentEvents, trendEvents };
  } catch (error) {
    console.error("Failed to fetch admin event stats", error);
    return { recentRejectedEvents: 0, recentFailedEvents: 0, recentEvents: [], trendEvents: [] };
  }
}

export async function GET(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * dayMs);
    const thirtyDaysAgo = new Date(now.getTime() - 30 * dayMs);
    const trendDays = 14;
    const trendStart = startOfDay(new Date(now.getTime() - (trendDays - 1) * dayMs));
    const metrics = buildDailyMetrics(trendStart, trendDays);
    const metricsByDate = new Map(metrics.map((metric) => [metric.date, metric]));

    const [
      totalUsers,
      proUsers,
      adminUsers,
      newUsers7d,
      newUsers30d,
      activeSessions,
      paidTransactions,
      failedTransactions,
      pendingTransactions,
      paidRevenue,
      trendUsers,
      trendPayments,
      eventStats,
    ] = await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { isPro: true } }),
      prisma.user.count({ where: { isAdmin: true } }),
      prisma.user.count({ where: { createdAt: { gte: sevenDaysAgo } } }),
      prisma.user.count({ where: { createdAt: { gte: thirtyDaysAgo } } }),
      prisma.authSession.count({ where: { revokedAt: null, expiresAt: { gt: now } } }),
      prisma.paymentTransaction.count({ where: { status: "paid" } }),
      prisma.paymentTransaction.count({ where: { status: "failed" } }),
      prisma.paymentTransaction.count({ where: { status: "pending" } }),
      prisma.paymentTransaction.aggregate({ where: { status: "paid" }, _sum: { amount: true } }),
      prisma.user.findMany({
        select: { createdAt: true },
        where: { createdAt: { gte: trendStart } },
      }),
      prisma.paymentTransaction.findMany({
        select: { createdAt: true, amount: true, status: true },
        where: { createdAt: { gte: trendStart } },
      }),
      readEventStats(sevenDaysAgo, trendStart),
    ]);
    const { recentRejectedEvents, recentFailedEvents, recentEvents, trendEvents } = eventStats;

    for (const user of trendUsers) {
      const metric = metricsByDate.get(dateKey(user.createdAt));
      if (metric) metric.users += 1;
    }

    for (const payment of trendPayments) {
      const metric = metricsByDate.get(dateKey(payment.createdAt));
      if (!metric || payment.status !== "paid") continue;
      metric.paidTransactions += 1;
      metric.revenue += payment.amount;
    }

    for (const event of trendEvents) {
      const metric = metricsByDate.get(dateKey(event.createdAt));
      if (metric) metric.events += 1;
    }

    return NextResponse.json({
      overview: {
        totalUsers,
        proUsers,
        freeUsers: Math.max(totalUsers - proUsers, 0),
        adminUsers,
        newUsers7d,
        newUsers30d,
        activeSessions,
        paidTransactions,
        failedTransactions,
        pendingTransactions,
        totalRevenue: paidRevenue._sum.amount || 0,
        recentRejectedEvents,
        recentFailedEvents,
      },
      trends: metrics,
      recentEvents,
      systemHealth: recentFailedEvents > 0 ? "Degraded" : "Healthy",
      generatedAt: now.toISOString(),
    });
  } catch (error) {
    console.error("Failed to fetch admin stats", error);
    return NextResponse.json({ error: "Failed to fetch stats" }, { status: 500 });
  }
}
