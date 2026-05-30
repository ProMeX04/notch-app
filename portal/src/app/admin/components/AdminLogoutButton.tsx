"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, LogOut } from "lucide-react";
import { apiClient } from "@/lib/api-client";

export function AdminLogoutButton() {
  const router = useRouter();
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogout = async () => {
    setIsLoggingOut(true);
    setError(null);

    try {
      await apiClient.post("/api/auth/logout");
      router.replace("/login");
      router.refresh();
    } catch (logoutError) {
      setError(logoutError instanceof Error ? logoutError.message : "Không thể đăng xuất. Vui lòng thử lại.");
      setIsLoggingOut(false);
    }
  };

  return (
    <div className="space-y-3">
      <button
        type="button"
        onClick={handleLogout}
        disabled={isLoggingOut}
        className="inline-flex w-full items-center justify-center gap-2 rounded border border-[#fad2cf] bg-white px-4 py-2 text-sm font-medium text-[#c5221f] transition-colors hover:bg-[#fce8e6] disabled:opacity-60"
      >
        {isLoggingOut ? <Loader2 className="animate-spin" size={16} /> : <LogOut size={16} />}
        {isLoggingOut ? "Đang đăng xuất..." : "Đăng xuất khỏi admin"}
      </button>
      {error && <p className="text-sm font-medium text-[#c5221f]">{error}</p>}
    </div>
  );
}
