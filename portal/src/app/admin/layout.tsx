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
    <div className="min-h-screen bg-black text-white">
      <div className="fixed left-0 right-0 top-0 z-50 flex h-16 items-center border-b border-slate-200 bg-black/80 px-4 backdrop-blur-md sm:px-6">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-slate-200 bg-white/70 text-sm font-black text-sky-500">N</div>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">Notch Admin Console</p>
            <p className="truncate text-xs text-slate-400">Quản lý người dùng và doanh thu</p>
          </div>
        </div>
      </div>
      <div className="flex flex-col pt-16 lg:flex-row">
        <AdminSidebar />
        <main className="min-h-[calc(100vh-4rem)] min-w-0 flex-1 lg:pl-64">
          <div className="mx-auto max-w-[1440px] px-4 py-4 sm:px-6 sm:py-6 lg:px-8 lg:py-8">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
