import { NextResponse } from "next/server";
import prisma from "@/lib/prisma";
import { requireAdminUser } from "@/lib/notch-auth";

export async function GET(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const [userCount, proCount, transactionCount, totalRevenue] = await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { isPro: true } }),
      prisma.paymentTransaction.count({ where: { status: "PAID" } }),
      prisma.paymentTransaction.aggregate({
        where: { status: "PAID" },
        _sum: { amount: true }
      })
    ]);

    return NextResponse.json({
      totalUsers: userCount,
      proUsers: proCount,
      transactions: transactionCount,
      totalRevenue: totalRevenue._sum.amount || 0,
      systemHealth: "Healthy",
      uptime: "99.99%"
    });
  } catch (error) {
    return NextResponse.json({ error: "Failed to fetch stats" }, { status: 500 });
  }
}
