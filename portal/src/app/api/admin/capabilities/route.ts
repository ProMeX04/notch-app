import { NextResponse } from "next/server";
import prisma from "@/lib/prisma";
import { mergeDefaultFeatureConfigs, requireAdminUser } from "@/lib/notch-auth";

export async function GET(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const configs = await prisma.featureConfig.findMany({
      orderBy: { name: "asc" }
    });
    return NextResponse.json(mergeDefaultFeatureConfigs(configs));
  } catch (error) {
    return NextResponse.json({ error: "Failed to fetch capabilities" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const data = await req.json();
    const { key, name, description, isProOnly, isEnabled } = data;

    const config = await prisma.featureConfig.upsert({
      where: { key },
      update: { name, description, isProOnly, isEnabled },
      create: { key, name, description, isProOnly, isEnabled }
    });

    return NextResponse.json(config);
  } catch (error) {
    return NextResponse.json({ error: "Failed to update capability" }, { status: 500 });
  }
}
