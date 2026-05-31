import { useEffect, useMemo, useState } from 'react'
import { CheckCircle2, Loader2, RefreshCw, ShieldCheck, SlidersHorizontal, Sparkles } from 'lucide-react'

import { apiClient } from '@/api/client'

type Capability = {
  key: string
  name: string
  description: string
  isProOnly: boolean
  isEnabled: boolean
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

function accessLabel(capability: Capability) {
  return capability.isProOnly ? 'Chỉ gói Pro' : 'Mọi người dùng'
}

export function AdminCapabilitiesPage() {
  const [capabilities, setCapabilities] = useState<Capability[]>([])
  const [loading, setLoading] = useState(true)
  const [savingKey, setSavingKey] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const enabledCount = useMemo(() => capabilities.filter(c => c.isEnabled).length, [capabilities])
  const proCount = useMemo(() => capabilities.filter(c => c.isProOnly).length, [capabilities])

  const fetchCapabilities = async () => {
    setLoading(true)
    setError(null)
    try {
      const response = await apiClient.get<Capability[]>('/api/admin/capabilities')
      setCapabilities(Array.isArray(response.data) ? response.data : [])
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Không tải được quyền truy cập')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void fetchCapabilities()
  }, [])

  const updateCapability = async (capability: Capability) => {
    setSavingKey(capability.key)
    setError(null)
    try {
      const response = await apiClient.post<Capability>('/api/admin/capabilities', capability)
      setCapabilities(current => current.map(item => item.key === capability.key ? response.data : item))
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Không lưu được thay đổi')
    } finally {
      setSavingKey(null)
    }
  }

  const initDefaultCapabilities = async () => {
    setSavingKey('restore_defaults')
    setError(null)
    try {
      const response = await apiClient.post<Capability[]>('/api/admin/capabilities', { action: 'restore_defaults' })
      setCapabilities(Array.isArray(response.data) ? response.data : [])
    } catch (restoreError) {
      setError(restoreError instanceof Error ? restoreError.message : 'Không khôi phục được cấu hình mặc định')
    } finally {
      setSavingKey(null)
    }
  }

  if (loading && capabilities.length === 0) {
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
          <h1 style={{ fontSize: '1.75rem', fontWeight: 700, margin: 0 }}>Quyền truy cập (Capabilities)</h1>
          <p style={{ color: 'var(--muted)', fontSize: '0.9rem', margin: '4px 0 0 0' }}>Bật tắt tính năng và chọn nhóm người dùng được phép sử dụng.</p>
        </div>
        <div style={{ display: 'flex', gap: '12px' }}>
          <button 
            type="button"
            onClick={() => void initDefaultCapabilities()} 
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
            onClick={() => void fetchCapabilities()} 
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

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px' }}>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)', fontWeight: 600, textTransform: 'uppercase' }}>Tổng tính năng</p>
          <p style={{ margin: '8px 0 0 0', fontSize: '2rem', fontWeight: 800 }}>{capabilities.length}</p>
        </div>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)', fontWeight: 600, textTransform: 'uppercase' }}>Đang bật</p>
          <p style={{ margin: '8px 0 0 0', fontSize: '2rem', fontWeight: 800, color: '#10b981' }}>{enabledCount}</p>
        </div>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)', fontWeight: 600, textTransform: 'uppercase' }}>Dành cho Pro</p>
          <p style={{ margin: '8px 0 0 0', fontSize: '2rem', fontWeight: 800, color: 'var(--accent)' }}>{proCount}</p>
        </div>
      </div>

      <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', overflow: 'hidden' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 24px', borderBottom: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <ShieldCheck className="text-indigo-500" size={20} />
            <div>
              <h2 style={{ fontSize: '1rem', fontWeight: 600, margin: 0 }}>Danh sách tính năng</h2>
              <p style={{ fontSize: '0.75rem', color: 'var(--muted)', margin: '2px 0 0 0' }}>Thay đổi có hiệu lực ngay trên ứng dụng và portal.</p>
            </div>
          </div>
          {savingKey && <Loader2 className="animate-spin text-indigo-500" size={18} />}
        </div>

        {capabilities.length === 0 ? (
          <div style={{ padding: '60px 20px', textAlign: 'center' }}>
            <SlidersHorizontal style={{ margin: '0 auto 12px', color: 'var(--muted)' }} size={32} />
            <p style={{ margin: 0, fontWeight: 600 }}>Chưa có tính năng nào được cấu hình.</p>
            <p style={{ margin: '4px 0 0 0', fontSize: '0.9rem', color: 'var(--muted)' }}>Tạo cấu hình mặc định để bắt đầu quản lý quyền truy cập.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="admin-console-table">
              <thead>
                <tr>
                  <th>Tính năng</th>
                  <th>Người được dùng</th>
                  <th>Trạng thái</th>
                  <th style={{ textAlign: 'right' }}>Bật/Tắt</th>
                </tr>
              </thead>
              <tbody>
                {capabilities.map(capability => (
                  <tr key={capability.key}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
                        <div style={{ 
                          padding: '8px', 
                          borderRadius: '8px', 
                          background: capability.isProOnly ? 'rgba(168, 85, 247, 0.1)' : 'rgba(56, 189, 248, 0.1)', 
                          color: capability.isProOnly ? '#a855f7' : 'var(--accent)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          flexShrink: 0
                        }}>
                          {capability.isProOnly ? <Sparkles size={16} /> : <CheckCircle2 size={16} />}
                        </div>
                        <div>
                          <p style={{ margin: 0, fontWeight: 600, color: 'var(--foreground)' }}>{capability.name}</p>
                          <p style={{ margin: '4px 0 0 0', fontSize: '0.85rem', color: 'var(--muted)' }}>{capability.description}</p>
                        </div>
                      </div>
                    </td>
                    <td>
                      <div style={{ display: 'inline-flex', border: '1px solid var(--border)', borderRadius: '10px', background: 'rgba(255,255,255,0.02)', padding: '2px' }}>
                        <button 
                          type="button"
                          onClick={() => void updateCapability({ ...capability, isProOnly: false })} 
                          disabled={savingKey === capability.key} 
                          style={{
                            border: 'none',
                            borderRadius: '8px',
                            padding: '6px 12px',
                            fontSize: '0.75rem',
                            fontWeight: 600,
                            cursor: 'pointer',
                            background: !capability.isProOnly ? 'rgba(255,255,255,0.08)' : 'transparent',
                            color: !capability.isProOnly ? 'var(--foreground)' : 'var(--muted)'
                          }}
                        >
                          Mọi người dùng
                        </button>
                        <button 
                          type="button"
                          onClick={() => void updateCapability({ ...capability, isProOnly: true })} 
                          disabled={savingKey === capability.key} 
                          style={{
                            border: 'none',
                            borderRadius: '8px',
                            padding: '6px 12px',
                            fontSize: '0.75rem',
                            fontWeight: 600,
                            cursor: 'pointer',
                            background: capability.isProOnly ? 'rgba(255,255,255,0.08)' : 'transparent',
                            color: capability.isProOnly ? 'var(--foreground)' : 'var(--muted)'
                          }}
                        >
                          Chỉ Pro
                        </button>
                      </div>
                    </td>
                    <td>
                      <span className={`admin-pill ${capability.isEnabled ? 'admin-pill-green' : 'admin-pill-gray'}`}>
                        {capability.isEnabled ? 'Đang bật' : 'Đang tắt'}
                      </span>
                      <p style={{ margin: '4px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>{accessLabel(capability)}</p>
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <Toggle 
                        checked={capability.isEnabled} 
                        disabled={savingKey === capability.key} 
                        onChange={checked => void updateCapability({ ...capability, isEnabled: checked })} 
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}

