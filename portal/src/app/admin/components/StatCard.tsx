import React from "react";
import { LucideIcon } from "lucide-react";

interface StatCardProps {
  title: string;
  value: string | number;
  change?: string;
  isPositive?: boolean;
  icon: LucideIcon;
  color: string;
}

export function StatCard({ title, value, change, isPositive, icon: Icon, color }: StatCardProps) {
  return (
    <div className="p-6 rounded-[24px] border border-[var(--border)] bg-[var(--surface-soft)] hover:shadow-md transition-all">
      <div className="flex items-center justify-between mb-4">
        <div className={`p-3 rounded-2xl ${color} bg-opacity-10 text-opacity-100`}>
          <Icon size={24} className={color.replace('bg-', 'text-')} />
        </div>
        {change && (
          <span className={`text-xs font-bold px-2 py-1 rounded-full ${isPositive ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
            {isPositive ? '+' : ''}{change}
          </span>
        )}
      </div>
      <div>
        <p className="text-sm font-medium text-[var(--muted)] mb-1">{title}</p>
        <h3 className="text-2xl font-bold text-[var(--foreground)]">{value}</h3>
      </div>
    </div>
  );
}
