import React from "react";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { AdminSidebar } from "./components/AdminSidebar";
import { requireAdminForServerComponent } from "@/lib/notch-auth";
import "./admin.css";

export const dynamic = 'force-dynamic';

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const cookieStore = await cookies();
  const token = cookieStore.get("notch_access_token")?.value ?? null;

  const isAdmin = await requireAdminForServerComponent(token);
  if (!isAdmin) {
    redirect("/");
  }

  return (
    <div className="min-h-screen bg-[#f8faff]">
      <AdminSidebar />
      <main className="pl-72 pt-4 pr-4 pb-4">
        <div className="min-h-[calc(100vh-2rem)] rounded-[32px] bg-white border border-[var(--border)] shadow-sm overflow-hidden p-8">
          {children}
        </div>
      </main>
    </div>
  );
}
