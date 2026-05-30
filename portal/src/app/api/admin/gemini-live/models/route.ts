import { NextResponse } from "next/server";
import { z } from "zod";
import {
  deleteGeminiLiveModelAdminConfig,
  listGeminiLiveModelAdminConfigs,
  restoreDefaultGeminiLiveModelAdminConfigs,
  syncGeminiLiveModelsFromGoogle,
  upsertGeminiLiveModelAdminConfig,
} from "@/lib/gemini-live-model-policy";
import { requireAdminUser } from "@/lib/notch-auth";

const actionSchema = z.object({
  action: z.enum(["restore_defaults", "sync_google"]),
});

const upsertModelSchema = z.object({
  modelId: z.string().trim().min(1, "Model ID is required"),
  displayName: z.string().trim().optional(),
  isEnabled: z.boolean().optional().default(false),
  sortOrder: z.number().finite().int().optional().default(0),
});

const deleteModelSchema = z.object({
  modelId: z.string().trim().min(1, "Model ID is required"),
});

export async function GET(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    return NextResponse.json(await listGeminiLiveModelAdminConfigs());
  } catch {
    return NextResponse.json({ error: "Failed to fetch Gemini Live models" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const rawBody = await req.json();

    // Check if it's an action (restore defaults or sync from google)
    const actionResult = actionSchema.safeParse(rawBody);
    if (actionResult.success) {
      const { action } = actionResult.data;
      if (action === "restore_defaults") {
        return NextResponse.json(await restoreDefaultGeminiLiveModelAdminConfigs());
      }
      if (action === "sync_google") {
        return NextResponse.json(await syncGeminiLiveModelsFromGoogle());
      }
    }

    // Otherwise, parse as model configuration upsert
    const upsertResult = upsertModelSchema.safeParse(rawBody);
    if (!upsertResult.success) {
      return NextResponse.json(
        { error: "Invalid request payload", details: upsertResult.error.format() },
        { status: 400 }
      );
    }

    const { modelId, displayName, isEnabled, sortOrder } = upsertResult.data;

    return NextResponse.json(
      await upsertGeminiLiveModelAdminConfig({
        modelId,
        displayName: displayName || modelId,
        isEnabled,
        sortOrder,
      }),
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to update Gemini Live model";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function DELETE(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const { searchParams } = new URL(req.url);
    const paramsResult = deleteModelSchema.safeParse({
      modelId: searchParams.get("modelId"),
    });

    if (!paramsResult.success) {
      return NextResponse.json(
        { error: "Invalid parameters", details: paramsResult.error.format() },
        { status: 400 }
      );
    }

    const { modelId } = paramsResult.data;

    await deleteGeminiLiveModelAdminConfig(modelId);
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ error: "Failed to delete Gemini Live model" }, { status: 500 });
  }
}
