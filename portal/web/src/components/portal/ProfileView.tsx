import { useEffect, useMemo, useState } from 'react'
import {
  Apple,
  Globe,
  Laptop,
  Loader2,
  LogOut,
  MonitorSmartphone,
  ShieldCheck,
  Sparkles,
  Terminal,
} from 'lucide-react'

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
    return <Apple size={20} />
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
    return <Globe size={20} />
  }
  if (p.includes('win') || n.includes('windows') || n.includes('win')) {
    return <Laptop size={20} />
  }
  if (p.includes('linux') || n.includes('linux') || n.includes('ubuntu')) {
    return <Terminal size={20} />
  }
  return <MonitorSmartphone size={20} />
}

export function ProfileView() {
  const { status, user, signOut } = usePortalAuth()
  const [isCheckoutLoading, setIsCheckoutLoading] = useState(false)
  const [deviceLimit, setDeviceLimit] = useState(0)
  const [devices, setDevices] = useState<AccountDevice[]>([])
  const [isDevicesLoading, setIsDevicesLoading] = useState(true)
  const [activeDeviceAction, setActiveDeviceAction] = useState<string | null>(null)
  const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null)

  const [prevStatus, setPrevStatus] = useState(status)
  if (status !== prevStatus) {
    setPrevStatus(status)
    if (status === 'authenticated') {
      setIsDevicesLoading(true)
    }
  }

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

  const accountName = user?.name?.trim() || 'Notch User'
  const accountEmail = user?.email?.trim() || 'Chưa có email'
  const accountPlan = user?.is_pro ? 'pro' : 'free'
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
      const response = await apiClient.post<{ pay_url?: string; detail?: string }>(
        '/api/payments/vnpay/create',
      )
      const data = response.data
      if (!data.pay_url) {
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

  if (status === 'booting') {
    return (
      <div
        className="dashboard-loading-full"
        style={{
          minHeight: '60vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <div className="loading-branding">
          <Loader2
            size={32}
            className="portal-spinner animate-spin"
            style={{ margin: '0 auto 16px' }}
          />
          <p style={{ color: 'var(--muted)' }}>Đang đồng bộ dữ liệu tài khoản...</p>
        </div>
      </div>
    )
  }

  if (status === 'guest' || !user) {
    return null
  }

  return (
    <>
      <style>{`
        body {
          background-color: #f9f9ff;
          color: #141b2b;
        }
        .glass-panel {
          background-color: rgba(255, 255, 255, 0.85);
          backdrop-filter: blur(20px);
          -webkit-backdrop-filter: blur(20px);
          border: 1px solid rgba(0, 0, 0, 0.05);
          box-shadow: 0 4px 20px 0 rgba(0, 0, 0, 0.04);
        }
        .ambient-bg {
          background: radial-gradient(circle at 50% -20%, rgba(26, 86, 219, 0.05) 0%, transparent 70%);
        }
      `}</style>

      <div className="max-w-5xl mx-auto px-6 pt-24 pb-32 relative overflow-x-hidden ambient-bg">
        
        {/* Welcome Section */}
        <section className="glass-panel rounded-3xl p-8 mb-8 flex flex-wrap justify-between items-center gap-6">
          <div className="space-y-2">
            <h1 className="text-2xl md:text-3xl font-extrabold text-[#141b2b] tracking-tight">
              Chào quay lại, {accountName}
            </h1>
            <div className="flex items-center gap-3 flex-wrap text-sm text-[#434654] font-medium">
              <span>{accountEmail}</span>
              <span className="w-1 h-1 rounded-full bg-gray-300" />
              <span
                className={`px-3 py-1 rounded-full text-xs font-bold ${
                  accountPlan === 'pro'
                    ? 'bg-[#facc15]/10 text-yellow-600 border border-[#facc15]/20'
                    : 'bg-gray-100 text-gray-600 border border-gray-200'
                }`}
              >
                {accountPlan === 'pro' ? 'Gói Pro' : 'Gói Miễn phí'}
              </span>
            </div>
          </div>

          <button
            type="button"
            onClick={() => void signOut()}
            className="bg-red-50 hover:bg-red-100 border border-red-200 text-red-600 rounded-full px-5 py-2 font-semibold text-xs transition-all active:scale-95 flex items-center gap-1.5"
          >
            <LogOut size={14} />
            <span>Đăng xuất</span>
          </button>
        </section>

        {msg && (
          <div
            className={`p-4 rounded-xl mb-6 text-sm border font-semibold ${
              msg.type === 'ok' 
                ? 'bg-emerald-50 border-emerald-200 text-emerald-600' 
                : 'bg-red-50 border-red-200 text-red-600'
            }`}
          >
            {msg.text}
          </div>
        )}

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start">
          
          {/* Main Column: Devices */}
          <div className="lg:col-span-2">
            <section className="glass-panel rounded-3xl p-8 space-y-6">
              
              <div className="flex justify-between items-center border-b border-black/5 pb-4">
                <div className="flex items-center gap-2.5 text-gray-900 font-bold">
                  <MonitorSmartphone size={20} className="text-[#003fb1]" />
                  <h2 className="text-lg font-bold">Thiết bị của bạn</h2>
                </div>
                <span className="bg-[#003fb1]/10 text-[#003fb1] border border-[#003fb1]/20 text-xs font-bold px-2.5 py-0.5 rounded-full">
                  {activeDeviceCount}/{deviceLimit || '∞'}
                </span>
              </div>

              {isDevicesLoading ? (
                <div className="flex flex-col items-center gap-3 py-12">
                  <Loader2 size={24} className="text-[#003fb1] animate-spin" />
                  <p className="text-sm text-gray-500">Đang đồng bộ thiết bị...</p>
                </div>
              ) : (
                <div className="space-y-4">
                  {devices.map((device) => (
                    <div
                      key={device.device_id}
                      className={`flex flex-wrap items-center justify-between gap-4 p-5 rounded-2xl border transition-all duration-300 ${
                        device.current
                          ? 'bg-[#003fb1]/5 border-[#003fb1]/20 shadow-sm'
                          : 'bg-white/60 border-black/5 hover:-translate-y-0.5'
                      }`}
                    >
                      <div className="flex items-center gap-4">
                        <div
                          className={`w-10 h-10 rounded-full flex items-center justify-center ${
                            device.current ? 'bg-[#003fb1] text-white shadow-sm' : 'bg-gray-100 text-gray-500'
                          }`}
                        >
                          {getDeviceIcon(device.platform, device.device_name)}
                        </div>
                        <div className="space-y-1">
                          <div className="flex items-center gap-2 flex-wrap">
                            <h3 className="font-bold text-sm text-gray-900">{device.device_name}</h3>
                            {device.current && (
                              <span className="bg-[#003fb1]/10 text-[#003fb1] text-[9px] font-bold px-2 py-0.5 rounded-full border border-[#003fb1]/20">
                                Hiện tại
                              </span>
                            )}
                            {device.trusted_at && (
                              <ShieldCheck size={15} className="text-emerald-500" />
                            )}
                          </div>
                          <p className="text-xs text-[#434654]">
                            {device.platform} • Lần cuối: {formatDate(device.last_seen_at)}
                          </p>
                        </div>
                      </div>
                      
                      <div className="flex items-center gap-2">
                        {!device.current && device.active && (
                          <button
                            type="button"
                            disabled={activeDeviceAction === device.device_id}
                            onClick={() => void mutateDevice('revoke', device.device_id)}
                            className="bg-red-50 hover:bg-red-100 border border-red-200 text-red-600 rounded-full px-4 py-1.5 font-semibold text-xs transition-all active:scale-95"
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

          {/* Sidebar Column: Info & Upgrades */}
          <div className="lg:col-span-1 space-y-6">
            <section className="glass-panel rounded-3xl p-8 space-y-6">
              
              <div className="flex items-center gap-2 border-b border-black/5 pb-4 text-gray-900 font-bold">
                <ShieldCheck size={18} className="text-emerald-500" />
                <h2 className="text-base font-bold">Trạng thái tài khoản</h2>
              </div>

              <div className="space-y-4 text-xs font-semibold">
                <div className="flex justify-between items-center border-b border-black/5 pb-3">
                  <span className="text-[#434654]">Xác thực</span>
                  <strong className="text-emerald-600">Đã liên kết Google</strong>
                </div>
                <div className="flex justify-between items-center border-b border-black/5 pb-3">
                  <span className="text-[#434654]">Ngày tham gia</span>
                  <strong className="text-gray-900">{formatDate(user.created_at, { month: 'short', year: 'numeric' })}</strong>
                </div>
                <div className="flex justify-between items-center pb-1">
                  <span className="text-[#434654]">Gói hiện tại</span>
                  <strong
                    className={accountPlan === 'pro' ? 'text-yellow-600' : 'text-gray-600'}
                  >
                    {accountPlan === 'pro' ? 'Gói Pro' : 'Gói Miễn phí'}
                  </strong>
                </div>
              </div>

              {accountPlan !== 'pro' && (
                <>
                  <div className="border-t border-black/5 pt-4 space-y-3">
                    <div className="flex items-center gap-2 text-xs font-medium text-[#434654]">
                      <span className="text-[#003fb1] font-bold">✓</span>
                      <span>Không giới hạn thời gian Focus</span>
                    </div>
                    <div className="flex items-center gap-2 text-xs font-medium text-[#434654]">
                      <span className="text-[#003fb1] font-bold">✓</span>
                      <span>Mở khóa Jarvis & Gemini Live</span>
                    </div>
                    <div className="flex items-center gap-2 text-xs font-medium text-[#434654]">
                      <span className="text-[#003fb1] font-bold">✓</span>
                      <span>Đồng bộ Cloud & Shelf không giới hạn</span>
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => void handleSubscribe()}
                    disabled={isCheckoutLoading}
                    className="w-full py-3.5 rounded-xl bg-[#facc15] font-semibold text-xs text-[#241a00] hover:bg-yellow-500 active:scale-95 transition-all shadow-md flex items-center justify-center gap-2 border-none cursor-pointer"
                  >
                    {isCheckoutLoading ? (
                      <>
                        <Loader2 size={14} className="animate-spin" />
                        Đang kết nối VNPAY...
                      </>
                    ) : (
                      <>
                        <Sparkles size={14} />
                        <span>Nâng cấp Pro ngay</span>
                      </>
                    )}
                  </button>
                </>
              )}
            </section>
          </div>

        </div>
      </div>
    </>
  )
}
