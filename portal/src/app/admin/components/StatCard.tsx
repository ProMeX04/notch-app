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
    <div className="p-4 rounded border border-[#dadce0] bg-white shadow-sm hover:shadow transition-shadow">
      <div className="flex items-center justify-between mb-4">
        <div className={`p-2 rounded bg-[#f8f9fa] border border-[#dadce0]`}>
          <Icon size={20} className={color} />
        </div>
        {change && (
          <span className={`text-xs font-medium px-2 py-0.5 rounded border ${isPositive ? 'bg-[#e6f4ea] text-[#137333] border-[#ceead6]' : 'bg-[#fce8e6] text-[#c5221f] border-[#fad2cf]'}`}>
            {isPositive ? '+' : ''}{change}
          </span>
        )}
      </div>
      <div>
        <p className="text-xs font-medium text-[#5f6368] mb-1">{title}</p>
        <h3 className="text-xl font-normal text-[#202124]">{value}</h3>
      </div>
    </div>
  );
}
