"use client";

import React, { useEffect, useMemo, useState } from "react";
import { Bot, CloudDownload, Loader2, Plus, RefreshCw, Save, Sparkles, Trash2 } from "lucide-react";

type GeminiLiveModelConfig = {
  id: string
  displayName: string
  supportedGenerationMethods: string[]
  configId: string | null
  isEnabled: boolean
  sortOrder: number
  source: "database" | "default"
  updatedAt: string | null
}

const emptyDraft = {
  modelId: "",
  displayName: "",
  sortOrder: 0,
};

function Toggle({ checked, onChange, disabled }: { checked: boolean; onChange: (checked: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-4 w-7 items-center rounded-full border transition-colors disabled:opacity-40 cursor-pointer focus:outline-none focus-visible:ring-2 focus-visible:ring-[#1a73e8] focus-visible:ring-offset-1 ${checked ? "border-[#1a73e8] bg-[#1a73e8]" : "border-[#dadce0] bg-[#e8eaed]"}`}
    >
      <span className={`h-3 w-3 rounded-full bg-white shadow-sm transition-transform ${checked ? "translate-x-[13px]" : "translate-x-0.5"}`} />
    </button>
  );
}

export default function GeminiLiveModelsAdminPage() {
  const [models, setModels] = useState<GeminiLiveModelConfig[]>([]);
  const [draft, setDraft] = useState(emptyDraft);
  const [loading, setLoading] = useState(true);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const enabledCount = useMemo(() => models.filter((model) => model.isEnabled).length, [models]);
  const usesDefaults = models.some((model) => model.source === "default");

  const fetchModels = async () => {
    setLoading(true);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch("/api/admin/gemini-live/models");
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không tải được danh sách model");
      setModels(data);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Không tải được danh sách model");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void fetchModels();
  }, []);

  const saveModel = async (model: Pick<GeminiLiveModelConfig, "id" | "displayName" | "isEnabled" | "sortOrder">) => {
    setSavingKey(model.id);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch("/api/admin/gemini-live/models", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          modelId: model.id,
          displayName: model.displayName,
          isEnabled: model.isEnabled,
          sortOrder: model.sortOrder,
        }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không lưu được model");
      setModels((current) => {
        const existing = current.some((item) => item.id === data.id);
        const next = existing ? current.map((item) => (item.id === data.id ? data : item)) : [...current, data];
        return next.sort((left, right) => left.sortOrder - right.sortOrder || left.displayName.localeCompare(right.displayName));
      });
      setDraft(emptyDraft);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "Không lưu được model");
    } finally {
      setSavingKey(null);
    }
  };

  const addModel = async () => {
    const modelId = draft.modelId.trim();
    if (!modelId) {
      setError("Model ID là bắt buộc.");
      return;
    }
    await saveModel({
      id: modelId,
      displayName: draft.displayName.trim() || modelId,
      isEnabled: true,
      sortOrder: draft.sortOrder,
    });
  };

  const deleteModel = async (modelId: string) => {
    setSavingKey(modelId);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch(`/api/admin/gemini-live/models?modelId=${encodeURIComponent(modelId)}`, {
        method: "DELETE",
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không xóa được model");
      setModels((current) => current.filter((model) => model.id !== modelId));
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : "Không xóa được model");
    } finally {
      setSavingKey(null);
    }
  };

  const restoreDefaults = async () => {
    setSavingKey("restore_defaults");
    setError(null);
    setNotice(null);
    try {
      const response = await fetch("/api/admin/gemini-live/models", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "restore_defaults" }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không khôi phục được model mặc định");
      setModels(data);
    } catch (restoreError) {
      setError(restoreError instanceof Error ? restoreError.message : "Không khôi phục được model mặc định");
    } finally {
      setSavingKey(null);
    }
  };

  const syncFromGoogle = async () => {
    setSavingKey("sync_google");
    setError(null);
    setNotice(null);
    try {
      const response = await fetch("/api/admin/gemini-live/models", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "sync_google" }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không đồng bộ được model từ Google");
      setModels(data.models);
      setNotice(`Đã tìm thấy ${data.discoveredCount} Live models từ Google; thêm mới ${data.addedCount} model ở trạng thái tắt.`);
    } catch (syncError) {
      setError(syncError instanceof Error ? syncError.message : "Không đồng bộ được model từ Google");
    } finally {
      setSavingKey(null);
    }
  };

  if (loading && models.length === 0) {
    return (
      <div className="h-full w-full flex items-center justify-center bg-[#f8f9fa]">
        <Loader2 className="animate-spin text-[#1a73e8]" size={48} />
      </div>
    );
  }

  return (
    <div className="space-y-6 bg-[#f8f9fa] font-sans text-[#202124]">
      <div className="flex flex-col items-start justify-between gap-4 border-b border-[#dadce0] pb-4 sm:flex-row sm:items-center">
        <div className="min-w-0">
          <h1 className="text-2xl font-normal tracking-tight text-[#202124]">Gemini Live models</h1>
          <p className="mt-1 text-sm text-[#5f6368]">Quản lý model desktop app được phép dùng qua managed server.</p>
        </div>
        <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
          <button onClick={syncFromGoogle} disabled={savingKey === "sync_google"} className="inline-flex items-center justify-center gap-2 rounded border border-[#1a73e8] bg-[#1a73e8] px-4 py-2 text-sm font-medium text-white hover:bg-[#1557b0] disabled:opacity-60">
            <CloudDownload size={16} />
            Đồng bộ từ Google
          </button>
          <button onClick={restoreDefaults} disabled={savingKey === "restore_defaults"} className="inline-flex items-center justify-center gap-2 rounded border border-[#1a73e8] bg-[#1a73e8] px-4 py-2 text-sm font-medium text-white hover:bg-[#1557b0] disabled:opacity-60">
            <Sparkles size={16} />
            Khôi phục mặc định
          </button>
          <button onClick={fetchModels} disabled={loading} className="inline-flex items-center justify-center gap-2 rounded border border-[#dadce0] bg-white px-4 py-2 text-sm font-medium text-[#1a73e8] hover:bg-[#f8f9fa] disabled:opacity-60">
            <RefreshCw size={16} className={loading ? "animate-spin" : ""} />
            Làm mới
          </button>
        </div>
      </div>

      {error && <div className="rounded border border-[#fad2cf] bg-[#fce8e6] p-4 text-sm font-medium text-[#c5221f]">{error}</div>}
      {notice && <div className="rounded border border-[#ceead6] bg-[#e6f4ea] p-4 text-sm font-medium text-[#137333]">{notice}</div>}

      <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <p className="text-xs font-medium text-[#5f6368]">Tổng model</p>
          <p className="mt-2 text-2xl font-normal text-[#202124]">{models.length}</p>
        </div>
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <p className="text-xs font-medium text-[#5f6368]">Đang cho phép</p>
          <p className="mt-2 text-2xl font-normal text-[#137333]">{enabledCount}</p>
        </div>
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <p className="text-xs font-medium text-[#5f6368]">Nguồn cấu hình</p>
          <p className="mt-2 text-2xl font-normal text-[#1967d2]">{usesDefaults ? "Default" : "DB"}</p>
        </div>
      </div>

      <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
        <div className="mb-4 flex items-start gap-3">
          <Bot className="text-[#1a73e8]" size={20} />
          <div>
            <h2 className="text-base font-medium text-[#202124]">Thêm model</h2>
            <p className="text-xs text-[#5f6368]">Model ID nên khớp tên Gemini API, ví dụ gemini-3.1-flash-live-preview.</p>
          </div>
        </div>
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)_120px_auto]">
          <input value={draft.modelId} onChange={(event) => setDraft((current) => ({ ...current, modelId: event.target.value }))} className="rounded border border-[#dadce0] bg-white px-3 py-2 text-sm outline-none focus:border-[#1a73e8]" placeholder="model id" />
          <input value={draft.displayName} onChange={(event) => setDraft((current) => ({ ...current, displayName: event.target.value }))} className="rounded border border-[#dadce0] bg-white px-3 py-2 text-sm outline-none focus:border-[#1a73e8]" placeholder="display name" />
          <input type="number" value={draft.sortOrder} onChange={(event) => setDraft((current) => ({ ...current, sortOrder: Number(event.target.value) || 0 }))} className="rounded border border-[#dadce0] bg-white px-3 py-2 text-sm outline-none focus:border-[#1a73e8]" placeholder="thứ tự" />
          <button onClick={addModel} disabled={Boolean(savingKey)} className="inline-flex items-center justify-center gap-2 rounded border border-[#1a73e8] bg-[#1a73e8] px-4 py-2 text-sm font-medium text-white hover:bg-[#1557b0] disabled:opacity-60">
            <Plus size={16} />
            Thêm
          </button>
        </div>
      </div>

      <div className="rounded border border-[#dadce0] bg-white shadow-sm">
        <div className="flex items-start justify-between gap-3 border-b border-[#dadce0] px-4 py-3 sm:items-center">
          <div>
            <h2 className="text-base font-medium text-[#202124]">Model được quản lý</h2>
            <p className="text-xs text-[#5f6368]">Chỉ model đang bật mới được trả về cho app và được cấp session token.</p>
          </div>
          {savingKey && <Loader2 className="animate-spin text-[#1a73e8]" size={18} />}
        </div>

        <div className="overflow-x-auto">
          <table className="admin-console-table min-w-[980px]">
            <thead>
              <tr>
                <th>Model</th>
                <th>Display name</th>
                <th>Thứ tự</th>
                <th>Trạng thái</th>
                <th className="text-right">Thao tác</th>
              </tr>
            </thead>
            <tbody>
              {models.map((model) => (
                <tr key={model.id}>
                  <td>
                    <p className="font-medium text-[#202124]">{model.id}</p>
                    <p className="mt-1 text-xs text-[#5f6368]">{model.supportedGenerationMethods.join(", ")}</p>
                  </td>
                  <td>
                    <input value={model.displayName} onChange={(event) => setModels((current) => current.map((item) => item.id === model.id ? { ...item, displayName: event.target.value } : item))} className="w-full rounded border border-[#dadce0] bg-white px-3 py-2 text-sm outline-none focus:border-[#1a73e8]" />
                  </td>
                  <td>
                    <input type="number" value={model.sortOrder} onChange={(event) => setModels((current) => current.map((item) => item.id === model.id ? { ...item, sortOrder: Number(event.target.value) || 0 } : item))} className="w-24 rounded border border-[#dadce0] bg-white px-3 py-2 text-sm outline-none focus:border-[#1a73e8]" />
                  </td>
                  <td>
                    <div className="flex items-center gap-3">
                      <Toggle checked={model.isEnabled} disabled={savingKey === model.id} onChange={(checked) => saveModel({ ...model, isEnabled: checked })} />
                      <span className={`admin-pill ${model.isEnabled ? "admin-pill-green" : "admin-pill-gray"}`}>{model.isEnabled ? "Đang bật" : "Đang tắt"}</span>
                    </div>
                  </td>
                  <td className="text-right">
                    <div className="inline-flex items-center gap-2">
                      <button onClick={() => saveModel(model)} disabled={savingKey === model.id} className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-3 py-2 text-sm font-medium text-[#1a73e8] hover:bg-[#f8f9fa] disabled:opacity-60">
                        <Save size={15} />
                        Lưu
                      </button>
                      <button onClick={() => deleteModel(model.id)} disabled={savingKey === model.id} className="inline-flex items-center gap-2 rounded border border-[#fad2cf] bg-white px-3 py-2 text-sm font-medium text-[#c5221f] hover:bg-[#fce8e6] disabled:opacity-60">
                        <Trash2 size={15} />
                        Xóa
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {models.length === 0 && (
                <tr>
                  <td colSpan={5} className="py-10 text-center text-sm text-[#5f6368]">Chưa có model nào.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
