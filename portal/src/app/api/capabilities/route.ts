import { NextResponse } from "next/server";
import { getRemotePermissionPolicy } from "@/lib/notch-auth";

export async function GET() {
  try {
    const policy = await getRemotePermissionPolicy();
    return NextResponse.json(policy);
  } catch (error) {
    return NextResponse.json({ error: "Failed to fetch capabilities" }, { status: 500 });
  }
}
