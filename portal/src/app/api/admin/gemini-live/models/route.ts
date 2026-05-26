import { NextResponse } from "next/server";

import {
  deleteGeminiLiveModelAdminConfig,
  listGeminiLiveModelAdminConfigs,
  restoreDefaultGeminiLiveModelAdminConfigs,
  upsertGeminiLiveModelAdminConfig,
} from "@/lib/gemini-live-model-policy";
import { requireAdminUser } from "@/lib/notch-auth";

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

    const data = await req.json();
    if (data?.action === "restore_defaults") {
      return NextResponse.json(await restoreDefaultGeminiLiveModelAdminConfigs());
    }

    const modelId = typeof data?.modelId === "string" ? data.modelId.trim() : "";
    if (!modelId) {
      return NextResponse.json({ error: "Model ID is required" }, { status: 400 });
    }

    const displayName = typeof data?.displayName === "string" ? data.displayName : modelId;
    const sortOrder = typeof data?.sortOrder === "number" && Number.isFinite(data.sortOrder)
      ? Math.trunc(data.sortOrder)
      : 0;

    return NextResponse.json(
      await upsertGeminiLiveModelAdminConfig({
        modelId,
        displayName,
        isEnabled: Boolean(data?.isEnabled),
        sortOrder,
      }),
    );
  } catch {
    return NextResponse.json({ error: "Failed to update Gemini Live model" }, { status: 500 });
  }
}

export async function DELETE(req: Request) {
  try {
    const adminCheck = await requireAdminUser(req);
    if (adminCheck) return adminCheck;

    const { searchParams } = new URL(req.url);
    const modelId = searchParams.get("modelId")?.trim() ?? "";
    if (!modelId) {
      return NextResponse.json({ error: "Model ID is required" }, { status: 400 });
    }

    await deleteGeminiLiveModelAdminConfig(modelId);
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ error: "Failed to delete Gemini Live model" }, { status: 500 });
  }
}
