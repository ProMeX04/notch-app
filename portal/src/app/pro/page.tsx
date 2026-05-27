'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  Loader2,
  LogIn,
  LogOut,
  MonitorSmartphone,
  ShieldCheck,
  Sparkles,
} from 'lucide-react'

import { PortalLogo } from '@/components/portal/PortalLogo'
import { usePortalAuth } from '@/components/portal/PortalAuthProvider'
import { authenticatedFetch } from '@/lib/portal-auth-client'

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

export default function ProPage() {
  const router = useRouter()
  const { status, user, signOut } = usePortalAuth()
  const [isCheckoutLoading, setIsCheckoutLoading] = useState(false)
  const [deviceLimit, setDeviceLimit] = useState(0)
  const [devices, setDevices] = useState<AccountDevice[]>([])
  const [isDevicesLoading, setIsDevicesLoading] = useState(true)
  const [activeDeviceAction, setActiveDeviceAction] = useState<string | null>(null)
  const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null)

  useEffect(() => {
    if (status !== 'authenticated') {
      setDevices([])
      setDeviceLimit(0)
      setIsDevicesLoading(status === 'booting')
      return
    }

    let ignore = false
    setIsDevicesLoading(true)

    const hydrateDevices = async () => {
      try {
        const response = await authenticatedFetch('/api/auth/sessions')
        if (!response.ok) {
          throw new Error('Không thể tải danh sách thiết bị.')
        }

        const data = (await response.json()) as AccountDevicesResponse
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

  const accountName = user?.name?.trim() || 'Notch User'
  const accountEmail = user?.email?.trim() || 'Chưa có email'
  const accountPlan = user?.is_pro ? 'pro' : 'free'
  const activeDeviceCount = useMemo(
    () => devices.filter((device) => device.active).length,
    [devices],
  )

  const mutateDevice = async (action: 'trust' | 'untrust' | 'revoke', deviceId: string) => {
    setActiveDeviceAction(deviceId)
    setMsg(null)

    try {
      const response = await authenticatedFetch('/api/auth/sessions', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          action,
          device_id: deviceId,
        }),
      })

      const data = (await response.json().catch(() => null)) as
        | AccountDevicesResponse
        | { detail?: string }
        | null

      if (!response.ok || !data || !('devices' in data)) {
        throw new Error(
          data && typeof data === 'object' && 'detail' in data && typeof data.detail === 'string'
            ? data.detail
            : 'Không thể cập nhật thiết bị.',
        )
      }

      setDeviceLimit(data.max_active_devices)
      setDevices(data.devices)
      setMsg({
        type: 'ok',
        text:
          action === 'revoke'
            ? 'Thiết bị đã được đăng xuất.'
            : action === 'trust'
              ? 'Thiết bị đã được đánh dấu tin cậy.'
              : 'Thiết bị đã bị bỏ tin cậy.',
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

  const handleSubscribe = async () => {
    setIsCheckoutLoading(true)
    setMsg(null)

    try {
      const response = await authenticatedFetch('/api/payments/vnpay/create', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
      })

      const data = (await response.json()) as { pay_url?: string; detail?: string }
      if (!response.ok || !data.pay_url) {
        throw new Error(data.detail || 'Không thể tạo phiên thanh toán VNPAY.')
      }

      window.location.href = data.pay_url
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Không thể tạo phiên thanh toán VNPAY.',
      })
      setIsCheckoutLoading(false)
    }
  }

  const handleSignOut = () => {
    signOut()
    router.push('/')
  }

  if (status === 'booting') {
    return (
      <main className="portal-dashboard-shell">
        <div className="portal-dashboard-bg">
          <div className="dashboard-blob blob-1"></div>
          <div className="dashboard-blob blob-2"></div>
        </div>

        <div className="dashboard-loading-full">
          <div className="loading-branding">
            <div className="loading-logo-wrap">
              <PortalLogo />
            </div>
            <div className="loading-shimmer-bar">
              <div className="shimmer-progress"></div>
            </div>
            <p>Đang đồng bộ dữ liệu tài khoản...</p>
          </div>
        </div>
      </main>
    )
  }

  if (status === 'guest' || !user) {
    return (
      <main className="portal-pro-container">
        <header className="portal-pro-header">
          <PortalLogo />
          <nav className="portal-pro-nav">
            <Link href="/" className="portal-button-ghost">Trang chủ</Link>
          </nav>
        </header>

        <div className="portal-pro-content">
          <section className="portal-pro-dashboard-hero">
            <div className="portal-pro-dashboard-copy">
              <span className="portal-badge-pro portal-badge-neutral">Dashboard</span>
              <h1>Bảng điều khiển tài khoản</h1>
              <p>Đăng nhập để xem thông tin tài khoản, quản lý thiết bị và theo dõi trạng thái gói Notch.</p>
            </div>
          </section>

          <div className="portal-pro-dashboard-grid">
            <section className="portal-card-pro portal-dashboard-card portal-dashboard-card-wide">
              <div className="portal-dashboard-card-head">
                <div className="portal-dashboard-icon">
                  <LogIn size={18} />
                </div>
                <div>
                  <h2>Chưa đăng nhập</h2>
                  <p>Hãy đăng nhập hoặc tạo tài khoản để truy cập dashboard của bạn.</p>
                </div>
              </div>

              <div className="portal-dashboard-guest-actions">
                <Link href="/api/auth/google" className="portal-button">Đăng nhập với Google</Link>
              </div>
            </section>
          </div>
        </div>
      </main>
    )
  }

  return (
    <main className="portal-dashboard-shell">
      <div className="portal-dashboard-bg">
        <div className="dashboard-blob blob-1"></div>
        <div className="dashboard-blob blob-2"></div>
      </div>

      <header className="dashboard-header">
        <div className="dashboard-header-inner">
          <PortalLogo />
          <nav className="dashboard-nav-actions">
            <button type="button" className="dashboard-logout-btn" onClick={handleSignOut}>
              <span>Đăng xuất</span>
              <LogOut size={16} />
            </button>
          </nav>
        </div>
      </header>

      <div className="dashboard-container">
        <section className="dashboard-hero">
          <div className="dashboard-hero-content">
            <div className="dashboard-user-info">
              <h1>Chào quay lại, {accountName}</h1>
              <div className="dashboard-user-meta">
                <span>{accountEmail}</span>
                <span className="meta-dot" />
                <span className={`plan-badge ${accountPlan === 'pro' ? 'is-pro' : ''}`}>
                  {accountPlan === 'pro' ? 'Gói Pro' : 'Gói Miễn phí'}
                </span>
              </div>
            </div>
          </div>
          
          <div className="dashboard-hero-actions">
            {accountPlan !== 'pro' && (
              <button 
                className="dashboard-upgrade-cta" 
                onClick={handleSubscribe}
                disabled={isCheckoutLoading}
              >
                <Sparkles size={18} />
                <span>Nâng cấp ngay</span>
              </button>
            )}
          </div>
        </section>

        {msg && (
          <div className={`dashboard-alert ${msg.type === 'ok' ? 'is-success' : 'is-error'}`}>
            {msg.text}
          </div>
        )}

        <div className="dashboard-grid">
          {/* Main Content Area */}
          <div className="dashboard-main-col">
            <section className="dashboard-section">
              <div className="section-header">
                <div className="section-title">
                  <MonitorSmartphone size={20} />
                  <h2>Thiết bị của bạn</h2>
                </div>
                <span className="section-badge">{activeDeviceCount}/{deviceLimit || '∞'}</span>
              </div>

              {isDevicesLoading ? (
                <div className="dashboard-loading-state">
                  <Loader2 size={24} className="portal-spinner" />
                  <p>Đang đồng bộ thiết bị...</p>
                </div>
              ) : (
                <div className="device-list-premium">
                  {devices.map((device) => (
                    <div 
                      key={device.device_id} 
                      className={`device-card-premium ${device.current ? 'is-current' : ''}`}
                    >
                      <div className="device-icon">
                        <MonitorSmartphone size={24} />
                      </div>
                      <div className="device-info">
                        <div className="device-name-row">
                          <h3>{device.device_name}</h3>
                          {device.current && <span className="current-pill">Hiện tại</span>}
                          {device.trusted_at && <ShieldCheck size={16} className="trusted-icon" />}
                        </div>
                        <p>{device.platform} • {formatDate(device.last_seen_at)}</p>
                      </div>
                      <div className="device-actions">
                        <button
                          type="button"
                          className="device-action-btn"
                          disabled={activeDeviceAction === device.device_id}
                          onClick={() => mutateDevice(device.trusted_at ? 'untrust' : 'trust', device.device_id)}
                        >
                          {device.trusted_at ? 'Bỏ tin cậy' : 'Tin cậy'}
                        </button>
                        {!device.current && device.active && (
                          <button
                            type="button"
                            className="device-action-btn is-danger"
                            disabled={activeDeviceAction === device.device_id}
                            onClick={() => mutateDevice('revoke', device.device_id)}
                          >
                            Đăng xuất
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>
          </div>

          {/* Sidebar Area */}
          <div className="dashboard-side-col">
            <section className="dashboard-section profile-mini-card">
              <div className="section-title">
                <ShieldCheck size={20} />
                <h2>Bảo mật</h2>
              </div>
              <div className="security-status">
                <div className="status-item">
                  <span>Trạng thái</span>
                  <strong className="status-verified">Đã xác thực</strong>
                </div>
                <div className="status-item">
                  <span>Tham gia</span>
                  <strong>{formatDate(user.created_at, { month: 'short', year: 'numeric' })}</strong>
                </div>
              </div>
            </section>
          </div>
        </div>
      </div>
    </main>
  )
}
