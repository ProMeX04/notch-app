import { NextResponse } from "next/server";
import { capabilityDefaults } from "@/lib/capability-manifest";
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
  } catch {
    return NextResponse.json({ error: "Failed to fetch capabilities" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const data = await req.json();

    if (data?.action === "restore_defaults") {
      const defaults = capabilityDefaults();
      const defaultKeys = defaults.map((config) => config.key);
      await prisma.$transaction([
        prisma.featureConfig.deleteMany({ where: { key: { notIn: defaultKeys } } }),
        ...defaults.map((config) =>
          prisma.featureConfig.upsert({
            where: { key: config.key },
            update: config,
            create: config,
          })
        ),
      ]);
      return NextResponse.json(mergeDefaultFeatureConfigs(defaults));
    }

    const { key, name, description, isProOnly, isEnabled } = data;

    const config = await prisma.featureConfig.upsert({
      where: { key },
      update: { name, description, isProOnly, isEnabled },
      create: { key, name, description, isProOnly, isEnabled }
    });

    return NextResponse.json(config);
  } catch {
    return NextResponse.json({ error: "Failed to update capability" }, { status: 500 });
  }
}
