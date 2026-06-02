import { useEffect, useMemo, useState } from 'react'
import { Link } from '@tanstack/react-router'
import { LogOut, Loader2, Save, User, ShieldCheck, Apple, Globe, Laptop, Terminal, MonitorSmartphone } from 'lucide-react'
import { apiClient } from '@/api/client'
import { usePortalAuth } from '@/auth/usePortalAuth'

type AccountDevice = {
  device_id: string
  device_name: string
  platform: string
  trusted_at: string | null
  created_at: string
  last_seen_at: string
  revoked_at: string | null
  revoked_reason: string | null
  active: boolean
  current: boolean
  active_session_count: number
}

type AccountDevicesResponse = {
  max_active_devices: number
  devices: AccountDevice[]
}

function formatDate(value: string | null, options?: Intl.DateTimeFormatOptions) {
  if (!value) return 'Chưa có'

  const parsed = Date.parse(value)
  if (Number.isNaN(parsed)) return 'Chưa có'

  return new Intl.DateTimeFormat(
    'vi-VN',
    options ?? {
      dateStyle: 'medium',
      timeStyle: 'short',
    },
  ).format(new Date(parsed))
}

const getDeviceIcon = (platform: string, deviceName: string) => {
  const p = platform.toLowerCase()
  const n = deviceName.toLowerCase()

  if (
    p.includes('mac') ||
    p.includes('apple') ||
    p.includes('darwin') ||
    n.includes('mac') ||
    n.includes('imac') ||
    n.includes('macbook')
  ) {
    return <Apple size={18} />
  }
  if (
    p.includes('web') ||
    p.includes('browser') ||
    p.includes('chrome') ||
    p.includes('safari') ||
    p.includes('firefox') ||
    n.includes('browser') ||
    n.includes('chrome')
  ) {
    return <Globe size={18} />
  }
  if (p.includes('win') || n.includes('windows') || n.includes('win')) {
    return <Laptop size={18} />
  }
  if (p.includes('linux') || n.includes('linux') || n.includes('ubuntu')) {
    return <Terminal size={18} />
  }
  return <MonitorSmartphone size={18} />
}

export function ProfileView() {
  const { status, user, signOut, refreshAuthState } = usePortalAuth()
  
  const [name, setName] = useState(user?.name || '')
  const [avatarUrl, setAvatarUrl] = useState(user?.avatar_url || '')
  const [isSaving, setIsSaving] = useState(false)
  const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null)

  const [deviceLimit, setDeviceLimit] = useState(0)
  const [devices, setDevices] = useState<AccountDevice[]>([])
  const [isDevicesLoading, setIsDevicesLoading] = useState(true)
  const [activeDeviceAction, setActiveDeviceAction] = useState<string | null>(null)

  useEffect(() => {
    if (status !== 'authenticated') return

    let ignore = false

    const hydrateDevices = async () => {
      try {
        const response = await apiClient.get<AccountDevicesResponse>('/api/auth/sessions')
        const data = response.data
        if (ignore) return
        setDeviceLimit(data.max_active_devices)
        setDevices(data.devices)
      } catch {
        if (!ignore) {
          setDevices([])
        }
      } finally {
        if (!ignore) {
          setIsDevicesLoading(false)
        }
      }
    }

    void hydrateDevices()

    return () => {
      ignore = true
    }
  }, [status])

  const isWebDevice = (device: AccountDevice) => {
    return (
      device.platform.toLowerCase() === 'web' ||
      device.device_name.toLowerCase().includes('browser')
    )
  }

  const activeDeviceCount = useMemo(
    () => devices.filter((device) => device.active && !isWebDevice(device)).length,
    [devices],
  )

  const mutateDevice = async (action: 'trust' | 'untrust' | 'revoke', deviceId: string) => {
    setActiveDeviceAction(deviceId)
    setMsg(null)

    try {
      const response = await apiClient.patch<AccountDevicesResponse>('/api/auth/sessions', {
        action,
        device_id: deviceId,
      })

      const data = response.data

      if (!data || !('devices' in data)) {
        throw new Error('Không thể cập nhật thiết bị.')
      }

      setDeviceLimit(data.max_active_devices)
      setDevices(data.devices)
      setMsg({
        type: 'ok',
        text: 'Thiết bị đã được đăng xuất.',
      })
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Không thể cập nhật thiết bị.',
      })
    } finally {
      setActiveDeviceAction(null)
    }
  }

  const handleAvatarClick = () => {
    const newUrl = prompt('Nhập đường dẫn URL ảnh đại diện mới của bạn:', avatarUrl)
    if (newUrl !== null) {
      setAvatarUrl(newUrl.trim())
    }
  }

  if (status === 'booting') {
    return (
      <div
        style={{
          minHeight: '60vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <div style={{ textAlign: 'center' }}>
          <Loader2
            size={32}
            className="portal-spinner animate-spin"
            style={{ margin: '0 auto 16px', color: '#003fb1' }}
          />
          <p style={{ color: '#434654' }}>Đang đồng bộ dữ liệu tài khoản...</p>
        </div>
      </div>
    )
  }

  if (status === 'guest' || !user) {
    return null
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsSaving(true)
    setMsg(null)

    try {
      await apiClient.patch('/api/auth/profile', {
        name: name.trim() || null,
        avatar_url: avatarUrl.trim() || null,
      })
      await refreshAuthState()
      setMsg({ type: 'ok', text: 'Cập nhật tài khoản thành công!' })
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Không thể cập nhật tài khoản.',
      })
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <>
      <style>{`
        :root {
          --background: #f9f9ff !important;
          --foreground: #141b2b !important;
          color-scheme: light !important;
        }
        body {
          background-color: #f9f9ff !important;
          color: #141b2b !important;
        }
        body::before {
          display: none !important;
        }
        .profile-input {
          width: 100%;
          height: 46px;
          padding: 0 16px;
          border-radius: 12px;
          background: #ffffff;
          border: 1px solid rgba(0, 0, 0, 0.12);
          color: #141b2b;
          font-size: 0.95rem;
          transition: all 150ms ease;
        }
        .profile-input:focus {
          outline: none;
          border-color: #003fb1;
          box-shadow: 0 0 0 4px rgba(0, 63, 177, 0.1);
        }
        .profile-grid {
          display: grid;
          grid-template-columns: 1.1fr 0.9fr;
          gap: 64px;
          align-items: start;
          margin-top: 8px;
        }
        @media (max-width: 800px) {
          .profile-grid {
            grid-template-columns: 1fr;
            gap: 48px;
          }
        }
        .avatar-container {
          position: relative;
          width: 100px;
          height: 100px;
          border-radius: 50%;
          overflow: hidden;
          background: #e9edff;
          border: 2px solid rgba(0, 63, 177, 0.12);
          display: flex;
          align-items: center;
          justifyContent: center;
          box-shadow: 0 8px 24px rgba(0, 0, 0, 0.05);
          cursor: pointer;
          transition: all 0.2s ease;
        }
        .avatar-container:hover {
          transform: scale(1.04);
          border-color: #003fb1;
        }
        .avatar-overlay {
          position: absolute;
          inset: 0;
          background: rgba(0, 0, 0, 0.5);
          color: #ffffff;
          display: flex;
          align-items: center;
          justifyContent: center;
          font-size: 0.75rem;
          font-weight: 700;
          opacity: 0;
          transition: opacity 0.25s ease;
        }
        .avatar-container:hover .avatar-overlay {
          opacity: 1;
        }
      `}</style>

      <div 
        style={{
          maxWidth: '1000px',
          width: '100%',
          margin: '0 auto',
          padding: '6rem 2rem 4rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '32px',
          animation: 'portalRise 0.6s cubic-bezier(0.16, 1, 0.3, 1) both',
        }}
      >
        {/* Header Section */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid rgba(0, 0, 0, 0.06)', paddingBottom: '20px' }}>
          <div>
            <h1 style={{ fontSize: '1.75rem', fontWeight: 850, letterSpacing: '-0.04em', margin: 0, color: '#141b2b' }}>
              Hồ sơ cá nhân
            </h1>
            <p style={{ fontSize: '0.88rem', color: '#434654', margin: '4px 0 0' }}>
              {user.email}
            </p>
          </div>
          
          <button
            type="button"
            onClick={() => void signOut()}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '6px',
              height: '38px',
              padding: '0 16px',
              borderRadius: '999px',
              background: 'rgba(239, 68, 68, 0.08)',
              color: '#ef4444',
              fontWeight: 600,
              fontSize: '0.85rem',
              border: '1px solid rgba(239, 68, 68, 0.12)',
              cursor: 'pointer',
              transition: 'all 0.2s ease',
            }}
          >
            <LogOut size={14} />
            Đăng xuất
          </button>
        </div>

        {msg && (
          <div
            style={{
              padding: '14px 18px',
              borderRadius: '12px',
              fontSize: '0.9rem',
              fontWeight: 600,
              border: '1px solid',
              background: msg.type === 'ok' ? 'rgba(16, 185, 129, 0.08)' : 'rgba(239, 68, 68, 0.08)',
              borderColor: msg.type === 'ok' ? 'rgba(16, 185, 129, 0.16)' : 'rgba(239, 68, 68, 0.16)',
              color: msg.type === 'ok' ? '#10b981' : '#ef4444',
            }}
          >
            {msg.text}
          </div>
        )}

        <div className="profile-grid">
          {/* Left Column: Profile Form */}
          <div>
            <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          
          {/* Avatar Preview & URL Input */}
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '16px' }}>
            <div 
              className="avatar-container"
              onClick={handleAvatarClick}
              title="Click để đổi ảnh đại diện"
            >
              {avatarUrl.trim() ? (
                <img 
                  src={avatarUrl} 
                  alt="Avatar" 
                  style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                  onError={(e) => {
                    e.currentTarget.style.display = 'none'
                  }}
                />
              ) : (
                <User size={40} style={{ color: '#003fb1' }} />
              )}
              <div className="avatar-overlay">
                <span>Đổi ảnh</span>
              </div>
            </div>
            
            <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <label style={{ fontSize: '0.88rem', fontWeight: 700, color: '#141b2b' }}>
                Ảnh đại diện (URL)
              </label>
              <input
                type="url"
                value={avatarUrl}
                onChange={(e) => setAvatarUrl(e.target.value)}
                placeholder="Nhập đường dẫn URL ảnh của bạn"
                className="profile-input"
              />
            </div>
          </div>

          {/* Name Input */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.88rem', fontWeight: 700, color: '#141b2b' }}>
              Tên hiển thị
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Nhập tên hiển thị"
              required
              className="profile-input"
            />
          </div>

          {/* Plan Info Status */}
          <div 
            style={{ 
              display: 'flex', 
              justifyContent: 'space-between', 
              alignItems: 'center', 
              padding: '16px 4px',
              borderTop: '1px solid rgba(0, 0, 0, 0.06)',
              borderBottom: '1px solid rgba(0, 0, 0, 0.06)',
              marginTop: '8px'
            }}
          >
            <span style={{ fontSize: '0.9rem', fontWeight: 600, color: '#434654' }}>Gói tài khoản</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              {user.is_pro ? (
                <>
                  <ShieldCheck size={16} style={{ color: '#f97316' }} />
                  <span style={{ fontSize: '0.9rem', fontWeight: 750, color: '#f97316' }}>Notch Pro</span>
                </>
              ) : (
                <span style={{ fontSize: '0.9rem', fontWeight: 750, color: '#434654' }}>Miễn phí</span>
              )}
            </div>
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={isSaving}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px',
              minHeight: '3rem',
              padding: '0 2rem',
              borderRadius: '999px',
              background: '#003fb1',
              color: '#ffffff',
              fontWeight: 700,
              fontSize: '0.95rem',
              boxShadow: 'rgba(0, 63, 177, 0.15) 0px 4px 12px 0px',
              border: 'none',
              transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
              cursor: 'pointer',
              marginTop: '12px',
            }}
            onMouseEnter={(e) => {
              if (!isSaving) {
                e.currentTarget.style.transform = 'translateY(-2px)'
                e.currentTarget.style.boxShadow = 'rgba(0, 63, 177, 0.25) 0px 8px 20px 0px'
              }
            }}
            onMouseLeave={(e) => {
              if (!isSaving) {
                e.currentTarget.style.transform = 'translateY(0)'
                e.currentTarget.style.boxShadow = 'rgba(0, 63, 177, 0.15) 0px 4px 12px 0px'
              }
            }}
          >
            {isSaving ? (
              <Loader2 size={18} className="animate-spin" />
            ) : (
              <Save size={18} />
            )}
            Lưu thay đổi
          </button>
        </form>
      </div>

      {/* Right Column: Device Management Section */}
      <div>
        <div 
          style={{ 
            display: 'flex',
            flexDirection: 'column',
            gap: '16px'
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 800, margin: 0, color: '#141b2b' }}>
              Thiết bị hoạt động
            </h2>
            <span style={{ fontSize: '0.8rem', fontWeight: 700, color: '#434654' }}>
              {activeDeviceCount}/{deviceLimit || '∞'} thiết bị
            </span>
          </div>

          {isDevicesLoading ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '12px 0' }}>
              <Loader2 size={16} className="animate-spin style-spinner" style={{ color: '#003fb1' }} />
              <span style={{ fontSize: '0.88rem', color: '#434654' }}>Đang tải thiết bị...</span>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
              {devices.map((device) => (
                <div 
                  key={device.device_id}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '12px 0',
                    borderBottom: '1px solid rgba(0, 0, 0, 0.04)'
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <div 
                      style={{ 
                        width: '36px', 
                        height: '36px', 
                        borderRadius: '50%', 
                        background: device.current ? 'rgba(0, 63, 177, 0.08)' : 'rgba(0, 0, 0, 0.04)',
                        color: device.current ? '#003fb1' : '#434654',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center'
                      }}
                    >
                      {getDeviceIcon(device.platform, device.device_name)}
                    </div>
                    <div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <span style={{ fontSize: '0.9rem', fontWeight: 700, color: '#141b2b' }}>
                          {device.device_name}
                        </span>
                        {device.current && (
                          <span style={{ fontSize: '0.75rem', fontWeight: 750, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '2px 6px', borderRadius: '4px' }}>
                            Hiện tại
                          </span>
                        )}
                      </div>
                      <div style={{ fontSize: '0.75rem', color: '#434654', marginTop: '2px' }}>
                        {device.platform} • Hoạt động: {formatDate(device.last_seen_at)}
                      </div>
                    </div>
                  </div>

                  {!device.current && device.active && (
                    <button
                      type="button"
                      disabled={activeDeviceAction === device.device_id}
                      onClick={() => void mutateDevice('revoke', device.device_id)}
                      style={{
                        background: 'none',
                        border: 'none',
                        color: '#ef4444',
                        fontSize: '0.8rem',
                        fontWeight: 700,
                        cursor: 'pointer',
                        padding: '4px 8px',
                        borderRadius: '6px',
                        transition: 'background-color 0.2s',
                      }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.backgroundColor = 'rgba(239, 68, 68, 0.08)'
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.backgroundColor = 'transparent'
                      }}
                    >
                      {activeDeviceAction === device.device_id ? (
                        <Loader2 size={12} className="animate-spin" />
                      ) : (
                        'Đăng xuất'
                      )}
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
        
    {/* Back Link */}
        <div style={{ textAlign: 'center', marginTop: '-8px' }}>
          <Link
            to="/"
            style={{
              fontSize: '0.88rem',
              fontWeight: 600,
              color: '#434654',
              transition: 'color 0.2s ease',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.color = '#003fb1'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.color = '#434654'
            }}
          >
            Quay lại trang chủ
          </Link>
        </div>
      </div>
    </>
  )
}

