import { NextResponse } from "next/server";
import { z } from "zod";
import { logAppEvent } from "@/lib/event-logger";
import { requireAdminUser } from "@/lib/notch-auth";
import {
  listCapabilities,
  restoreDefaultCapabilities,
  upsertCapability,
} from "@/lib/capabilities/capability-service";

const upsertCapabilitySchema = z.object({
  key: z.string().min(1, "Key is required"),
  name: z.string().min(1, "Name is required"),
  description: z.string().nullable().optional(),
  isProOnly: z.boolean(),
  isEnabled: z.boolean(),
});

const actionSchema = z.object({
  action: z.literal("restore_defaults"),
});

export async function GET(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    return NextResponse.json(await listCapabilities());
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

    const rawBody = await req.json();

    // Check if it's a restore defaults action
    const actionResult = actionSchema.safeParse(rawBody);
    if (actionResult.success) {
      action = actionResult.data.action;
      const defaults = await restoreDefaultCapabilities();
      
      await logAppEvent({
        req,
        eventType: "admin.capabilities_restore_defaults_succeeded",
        outcome: "success",
        source: "web",
        statusCode: 200,
        metadata: { defaultCount: defaults.length },
      });
      
      return NextResponse.json(defaults);
    }

    // Otherwise, parse as capability upsert
    const capabilityResult = upsertCapabilitySchema.safeParse(rawBody);
    if (!capabilityResult.success) {
      return NextResponse.json(
        { error: "Invalid request payload", details: capabilityResult.error.format() },
        { status: 400 }
      );
    }

    const input = capabilityResult.data;
    action = "upsert";
    capabilityKey = input.key;

    const config = await upsertCapability(input);

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
