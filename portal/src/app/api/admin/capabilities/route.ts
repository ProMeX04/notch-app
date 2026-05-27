import { NextResponse } from "next/server";
import { capabilityDefaults } from "@/lib/capability-manifest";
import { logAppEvent } from "@/lib/event-logger";
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
  let action: string | null = null;
  let capabilityKey: string | null = null;

  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) {
      await logAppEvent({
        req,
        eventType: "admin.capabilities_rejected",
        outcome: "rejected",
        source: "web",
        statusCode: adminCheck.status,
        metadata: { reason: adminCheck.status === 401 ? "unauthorized" : "forbidden" },
      });
      return adminCheck;
    }

    const data = await req.json();
    action = typeof data?.action === "string" ? data.action : "upsert";

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
      await logAppEvent({
        req,
        eventType: "admin.capabilities_restore_defaults_succeeded",
        outcome: "success",
        source: "web",
        statusCode: 200,
        metadata: { defaultCount: defaults.length },
      });
      return NextResponse.json(mergeDefaultFeatureConfigs(defaults));
    }

    const { key, name, description, isProOnly, isEnabled } = data;
    capabilityKey = typeof key === "string" ? key : null;

    const config = await prisma.featureConfig.upsert({
      where: { key },
      update: { name, description, isProOnly, isEnabled },
      create: { key, name, description, isProOnly, isEnabled }
    });

    await logAppEvent({
      req,
      eventType: "admin.capability_upsert_succeeded",
      outcome: "success",
      source: "web",
      statusCode: 200,
      metadata: {
        key: config.key,
        enabled: config.isEnabled,
        proOnly: config.isProOnly,
      },
    });

    return NextResponse.json(config);
  } catch (error) {
    await logAppEvent({
      req,
      eventType: "admin.capabilities_failed",
      outcome: "failure",
      source: "web",
      statusCode: 500,
      metadata: {
        action,
        key: capabilityKey,
        errorType: error instanceof Error ? error.name : "unknown",
      },
    });
    return NextResponse.json({ error: "Failed to update capability" }, { status: 500 });
  }
}
