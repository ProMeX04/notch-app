import { NextResponse } from "next/server";
import prisma from "@/lib/prisma";
import { requireAdminUser } from "@/lib/notch-auth";

export async function GET(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const users = await prisma.user.findMany({
      select: {
        id: true,
        name: true,
        email: true,
        isPro: true,
        isAdmin: true,
        createdAt: true,
      },
      orderBy: { createdAt: "desc" },
      take: 50
    });

    return NextResponse.json(users);
  } catch (error) {
    return NextResponse.json({ error: "Failed to fetch users" }, { status: 500 });
  }
}
