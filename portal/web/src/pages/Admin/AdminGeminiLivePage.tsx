import { useEffect, useMemo, useState } from 'react'
import { Bot, CloudDownload, Loader2, Plus, RefreshCw, Save, Sparkles, Trash2 } from 'lucide-react'

import { apiClient } from '@/api/client'

type GeminiLiveModelConfig = {
  id: string
  displayName: string
  supportedGenerationMethods: string[]
  configId: string | null
  isEnabled: boolean
  sortOrder: number
  source: 'database' | 'default'
  updatedAt: string | null
}

const emptyDraft = {
  modelId: '',
  displayName: '',
  sortOrder: 0,
}

function Toggle({ checked, onChange, disabled }: { checked: boolean; onChange: (checked: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-5 w-9 items-center rounded-full border transition-colors disabled:opacity-40 cursor-pointer focus:outline-none ${checked ? 'border-[#1a73e8] bg-[#1a73e8]' : 'border-neutral-700 bg-neutral-800'}`}
      style={{ borderStyle: 'solid', borderWidth: '1px' }}
    >
      <span className={`h-4 w-4 rounded-full bg-white shadow-sm transition-transform ${checked ? 'translate-x-[16px]' : 'translate-x-0.5'}`} />
    </button>
  )
}

export function AdminGeminiLivePage() {
  const [models, setModels] = useState<GeminiLiveModelConfig[]>([])
  const [draft, setDraft] = useState(emptyDraft)
  const [loading, setLoading] = useState(true)
  const [savingKey, setSavingKey] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const enabledCount = useMemo(() => models.filter(model => model.isEnabled).length, [models])
  const usesDefaults = models.some(model => model.source === 'default')

  const fetchModels = async () => {
    setLoading(true)
    setError(null)
    setNotice(null)
    try {
      const response = await apiClient.get<GeminiLiveModelConfig[]>('/api/admin/gemini-live/models')
      setModels(Array.isArray(response.data) ? response.data : [])
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Không tải được danh sách model')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void fetchModels()
  }, [])

  const saveModel = async (model: Pick<GeminiLiveModelConfig, 'id' | 'displayName' | 'isEnabled' | 'sortOrder'>) => {
    setSavingKey(model.id)
    setError(null)
    setNotice(null)
    try {
      const response = await apiClient.post<GeminiLiveModelConfig>('/api/admin/gemini-live/models', {
        modelId: model.id,
        displayName: model.displayName,
        isEnabled: model.isEnabled,
        sortOrder: model.sortOrder,
      })
      const data = response.data
      setModels(current => {
        const existing = current.some(item => item.id === data.id)
        const next = existing ? current.map(item => item.id === data.id ? data : item) : [...current, data]
        return next.sort((left, right) => left.sortOrder - right.sortOrder || left.displayName.localeCompare(right.displayName))
      })
      setDraft(emptyDraft)
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Không lưu được model')
    } finally {
      setSavingKey(null)
    }
  }

  const addModel = async () => {
    const modelId = draft.modelId.trim()
    if (!modelId) {
      setError('Model ID là bắt buộc.')
      return
    }
    await saveModel({
      id: modelId,
      displayName: draft.displayName.trim() || modelId,
      isEnabled: true,
      sortOrder: draft.sortOrder,
    })
  }

  const deleteModel = async (modelId: string) => {
    setSavingKey(modelId)
    setError(null)
    setNotice(null)
    try {
      await apiClient.delete(`/api/admin/gemini-live/models?modelId=${encodeURIComponent(modelId)}`)
      setModels(current => current.filter(model => model.id !== modelId))
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Không xóa được model')
    } finally {
      setSavingKey(null)
    }
  }

  const restoreDefaults = async () => {
    setSavingKey('restore_defaults')
    setError(null)
    setNotice(null)
    try {
      const response = await apiClient.post<GeminiLiveModelConfig[]>('/api/admin/gemini-live/models', { action: 'restore_defaults' })
      setModels(Array.isArray(response.data) ? response.data : [])
    } catch (restoreError) {
      setError(restoreError instanceof Error ? restoreError.message : 'Không khôi phục được model mặc định')
    } finally {
      setSavingKey(null)
    }
  }

  const syncFromGoogle = async () => {
    setSavingKey('sync_google')
    setError(null)
    setNotice(null)
    try {
      const response = await apiClient.post<{ models: GeminiLiveModelConfig[]; discoveredCount: number; addedCount: number }>('/api/admin/gemini-live/models', { action: 'sync_google' })
      const data = response.data
      setModels(Array.isArray(data.models) ? data.models : [])
      setNotice(`Đã tìm thấy ${data.discoveredCount} Live models từ Google; thêm mới ${data.addedCount} model ở trạng thái tắt.`)
    } catch (syncError) {
      setError(syncError instanceof Error ? syncError.message : 'Không đồng bộ được model từ Google')
    } finally {
      setSavingKey(null)
    }
  }

  if (loading && models.length === 0) {
    return (
      <div style={{ display: 'flex', height: '300px', alignItems: 'center', justifyContent: 'center' }}>
        <Loader2 className="animate-spin text-[#1a73e8]" size={36} />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: '16px', borderBottom: '1px solid var(--border)', paddingBottom: '16px' }}>
        <div>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 700, margin: 0 }}>Cấu hình Gemini Live</h1>
          <p style={{ color: 'var(--muted)', fontSize: '0.9rem', margin: '4px 0 0 0' }}>Quản lý model desktop app được phép dùng qua managed server.</p>
        </div>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
          <button 
            type="button"
            onClick={() => void syncFromGoogle()} 
            disabled={savingKey === 'sync_google'} 
            className="portal-button"
            style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px',
              padding: '10px 16px',
              borderRadius: '12px',
              fontWeight: 600,
              fontSize: '0.9rem',
              cursor: 'pointer'
            }}
          >
            <CloudDownload size={16} />
            Đồng bộ từ Google
          </button>
          <button 
            type="button"
            onClick={() => void restoreDefaults()} 
            disabled={savingKey === 'restore_defaults'} 
            className="portal-button"
            style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px',
              padding: '10px 16px',
              borderRadius: '12px',
              fontWeight: 600,
              fontSize: '0.9rem',
              cursor: 'pointer'
            }}
          >
            <Sparkles size={16} />
            Khôi phục mặc định
          </button>
          <button 
            type="button"
            onClick={() => void fetchModels()} 
            disabled={loading} 
            className="portal-button-ghost"
            style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px',
              padding: '10px 16px',
              borderRadius: '12px',
              border: '1px solid var(--border)',
              fontWeight: 600,
              fontSize: '0.9rem',
              cursor: 'pointer'
            }}
          >
            <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
            Làm mới
          </button>
        </div>
      </div>

      {error && (
        <div style={{ background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.2)', color: '#ef4444', padding: '12px 16px', borderRadius: '12px', fontSize: '0.9rem' }}>
          {error}
        </div>
      )}
      {notice && (
        <div style={{ border: '1px solid rgba(16, 185, 129, 0.2)', background: 'rgba(16, 185, 129, 0.05)', color: '#10b981', padding: '12px 16px', borderRadius: '12px', fontSize: '0.9rem' }}>
          {notice}
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px' }}>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)', fontWeight: 600, textTransform: 'uppercase' }}>Tổng model</p>
          <p style={{ margin: '8px 0 0 0', fontSize: '2rem', fontWeight: 800 }}>{models.length}</p>
        </div>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)', fontWeight: 600, textTransform: 'uppercase' }}>Đang cho phép</p>
          <p style={{ margin: '8px 0 0 0', fontSize: '2rem', fontWeight: 800, color: '#10b981' }}>{enabledCount}</p>
        </div>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)', fontWeight: 600, textTransform: 'uppercase' }}>Nguồn cấu hình</p>
          <p style={{ margin: '8px 0 0 0', fontSize: '2rem', fontWeight: 800, color: 'var(--accent)' }}>{usesDefaults ? 'Default' : 'DB'}</p>
        </div>
      </div>

      <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', padding: '20px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
          <Bot style={{ color: 'var(--accent)' }} size={20} />
          <div>
            <h2 style={{ fontSize: '1rem', fontWeight: 600, margin: 0 }}>Thêm model</h2>
            <p style={{ fontSize: '0.75rem', color: 'var(--muted)', margin: '2px 0 0 0' }}>Model ID nên khớp tên Gemini API, ví dụ gemini-2.5-flash-live-preview.</p>
          </div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '12px' }}>
          <input 
            value={draft.modelId} 
            onChange={event => setDraft(current => ({ ...current, modelId: event.target.value }))} 
            placeholder="model id" 
            style={{ border: '1px solid var(--border)', background: 'rgba(0,0,0,0.2)', padding: '10px 12px', borderRadius: '12px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none' }}
          />
          <input 
            value={draft.displayName} 
            onChange={event => setDraft(current => ({ ...current, displayName: event.target.value }))} 
            placeholder="display name" 
            style={{ border: '1px solid var(--border)', background: 'rgba(0,0,0,0.2)', padding: '10px 12px', borderRadius: '12px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none' }}
          />
          <input 
            type="number" 
            value={draft.sortOrder} 
            onChange={event => setDraft(current => ({ ...current, sortOrder: Number(event.target.value) || 0 }))} 
            placeholder="thứ tự" 
            style={{ border: '1px solid var(--border)', background: 'rgba(0,0,0,0.2)', padding: '10px 12px', borderRadius: '12px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none' }}
          />
          <button 
            type="button"
            onClick={() => void addModel()} 
            disabled={Boolean(savingKey)} 
            className="portal-button"
            style={{ 
              height: '42px',
              borderRadius: '12px',
              fontWeight: 600,
              fontSize: '0.9rem',
              cursor: 'pointer',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '6px'
            }}
          >
            <Plus size={16} />
            Thêm
          </button>
        </div>
      </div>

      <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', overflow: 'hidden' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 24px', borderBottom: '1px solid var(--border)' }}>
          <div>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 700, margin: 0 }}>Model được quản lý</h2>
            <p style={{ fontSize: '0.75rem', color: 'var(--muted)', margin: '2px 0 0 0' }}>Chỉ model đang bật mới được trả về cho app và được cấp session token.</p>
          </div>
          {savingKey && <Loader2 className="animate-spin text-indigo-500" size={18} />}
        </div>

        <div className="overflow-x-auto">
          <table className="admin-console-table min-w-[980px]">
            <thead>
              <tr>
                <th>Model</th>
                <th>Display name</th>
                <th>Thứ tự</th>
                <th>Trạng thái</th>
                <th style={{ textAlign: 'right' }}>Thao tác</th>
              </tr>
            </thead>
            <tbody>
              {models.map(model => (
                <tr key={model.id}>
                  <td>
                    <p style={{ margin: 0, fontWeight: 600 }}>{model.id}</p>
                    <p style={{ margin: '4px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>{model.supportedGenerationMethods.join(', ')}</p>
                  </td>
                  <td>
                    <input 
                      value={model.displayName} 
                      onChange={event => setModels(current => current.map(item => item.id === model.id ? { ...item, displayName: event.target.value } : item))} 
                      style={{ border: '1px solid var(--border)', background: 'rgba(0,0,0,0.1)', padding: '8px 12px', borderRadius: '10px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none', width: '100%' }}
                    />
                  </td>
                  <td>
                    <input 
                      type="number" 
                      value={model.sortOrder} 
                      onChange={event => setModels(current => current.map(item => item.id === model.id ? { ...item, sortOrder: Number(event.target.value) || 0 } : item))} 
                      style={{ border: '1px solid var(--border)', background: 'rgba(0,0,0,0.1)', padding: '8px 12px', borderRadius: '10px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none', width: '90px' }}
                    />
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Toggle 
                        checked={model.isEnabled} 
                        disabled={savingKey === model.id} 
                        onChange={checked => void saveModel({ ...model, isEnabled: checked })} 
                      />
                      <span className={`admin-pill ${model.isEnabled ? 'admin-pill-green' : 'admin-pill-gray'}`}>
                        {model.isEnabled ? 'Đang bật' : 'Đang tắt'}
                      </span>
                    </div>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <div style={{ display: 'inline-flex', gap: '8px' }}>
                      <button 
                        type="button"
                        onClick={() => void saveModel(model)} 
                        disabled={savingKey === model.id} 
                        className="portal-button-ghost"
                        style={{ 
                          display: 'inline-flex', 
                          alignItems: 'center', 
                          gap: '6px',
                          padding: '8px 12px',
                          borderRadius: '10px',
                          border: '1px solid var(--border)',
                          fontSize: '0.85rem',
                          fontWeight: 600,
                          cursor: 'pointer'
                        }}
                      >
                        <Save size={14} />
                        Lưu
                      </button>
                      <button 
                        type="button"
                        onClick={() => void deleteModel(model.id)} 
                        disabled={savingKey === model.id} 
                        className="portal-button-ghost"
                        style={{ 
                          display: 'inline-flex', 
                          alignItems: 'center', 
                          gap: '6px',
                          padding: '8px 12px',
                          borderRadius: '10px',
                          border: '1px solid var(--border)',
                          fontSize: '0.85rem',
                          fontWeight: 600,
                          cursor: 'pointer',
                          color: '#ef4444',
                          background: 'rgba(239, 68, 68, 0.05)'
                        }}
                      >
                        <Trash2 size={14} />
                        Xóa
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {models.length === 0 && (
                <tr>
                  <td colSpan={5} style={{ textAlign: 'center', padding: '40px', color: 'var(--muted)' }}>Chưa có model nào.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
