import { NextResponse } from "next/server";
import type { Prisma } from "@prisma/client";

import prisma from "@/lib/prisma";
import { requireAdminUser } from "@/lib/notch-auth";

const maxLimit = 100;

function parsePositiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function buildOrderBy(sort: string | null): Prisma.UserOrderByWithRelationInput {
  switch (sort) {
    case "oldest":
      return { createdAt: "asc" };
    case "updated":
      return { updatedAt: "desc" };
    case "name":
      return { name: "asc" };
    case "email":
      return { email: "asc" };
    default:
      return { createdAt: "desc" };
  }
}

export async function GET(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const url = new URL(req.url);
    const q = url.searchParams.get("q")?.trim();
    const plan = url.searchParams.get("plan");
    const role = url.searchParams.get("role");
    const sort = url.searchParams.get("sort");
    const page = parsePositiveInteger(url.searchParams.get("page"), 1);
    const requestedLimit = parsePositiveInteger(url.searchParams.get("limit"), 25);
    const limit = Math.min(requestedLimit, maxLimit);
    const skip = (page - 1) * limit;

    const where: Prisma.UserWhereInput = {};

    if (q) {
      where.OR = [
        { email: { contains: q, mode: "insensitive" } },
        { name: { contains: q, mode: "insensitive" } },
        { id: { contains: q } },
      ];
    }

    if (plan === "pro") where.isPro = true;
    if (plan === "free") where.isPro = false;
    if (role === "admin") where.isAdmin = true;
    if (role === "user") where.isAdmin = false;

    const [total, users] = await Promise.all([
      prisma.user.count({ where }),
      prisma.user.findMany({
        where,
        orderBy: buildOrderBy(sort),
        skip,
        take: limit,
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
              deviceId: true,
              lastSeenAt: true,
              trustedAt: true,
              revokedAt: true,
              expiresAt: true,
            },
            orderBy: { lastSeenAt: "desc" },
          },
          payments: {
            select: {
              status: true,
              amount: true,
              paidAt: true,
              createdAt: true,
            },
          },
        },
      }),
    ]);

    const now = new Date();
    const rows = users.map((user) => {
      const paidPayments = user.payments.filter((payment) => payment.status === "paid");
      const activeSessions = user.sessions.filter((session) => !session.revokedAt && session.expiresAt > now);
      const trustedDeviceCount = new Set(
        user.sessions
          .filter((session) => Boolean(session.trustedAt))
          .map((s) => s.deviceId)
          .filter(Boolean)
      ).size;
      const lastSeenAt = user.sessions[0]?.lastSeenAt ?? null;
      const latestPaymentAt = user.payments
        .map((payment) => payment.paidAt ?? payment.createdAt)
        .sort((a, b) => b.getTime() - a.getTime())[0] ?? null;

      return {
        id: user.id,
        name: user.name,
        email: user.email,
        isPro: user.isPro,
        isAdmin: user.isAdmin,
        createdAt: user.createdAt,
        updatedAt: user.updatedAt,
        lastSeenAt,
        latestEventAt: null,
        latestPaymentAt,
        activeSessionCount: activeSessions.length,
        totalSessionCount: user.sessions.length,
        trustedDeviceCount,
        paidPaymentCount: paidPayments.length,
        totalPaidRevenue: paidPayments.reduce((sum, payment) => sum + payment.amount, 0),
      };
    });

    return NextResponse.json({
      users: rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.max(Math.ceil(total / limit), 1),
      },
    });
  } catch (error) {
    console.error("Failed to fetch admin users", error);
    return NextResponse.json({ error: "Failed to fetch users" }, { status: 500 });
  }
}
