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
    <div className="min-h-screen relative overflow-hidden bg-slate-50">
      {/* Decorative background elements */}
      <div className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] bg-indigo-500 rounded-full mix-blend-multiply filter blur-[120px] opacity-20 pointer-events-none"></div>
      <div className="absolute bottom-[-10%] right-[-10%] w-[40%] h-[40%] bg-emerald-500 rounded-full mix-blend-multiply filter blur-[120px] opacity-20 pointer-events-none"></div>

      <div className="relative z-10 flex h-screen">
        <AdminSidebar />
        <main className="flex-1 pl-64 h-full overflow-y-auto">
          <div className="m-4 min-h-[calc(100vh-2rem)] rounded-3xl glass-card p-8">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
