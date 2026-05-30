'use client';

import { useEffect, useMemo, useState } from 'react';
import { Loader2, MonitorSmartphone, ShieldCheck, Sparkles } from 'lucide-react';
import { usePortalAuth } from './PortalAuthProvider';
import { apiClient } from '@/lib/api-client';

type AccountDevice = {
  device_id: string;
  device_name: string;
  platform: string;
  trusted_at: string | null;
  created_at: string;
  last_seen_at: string;
  revoked_at: string | null;
  revoked_reason: string | null;
  active: boolean;
  current: boolean;
  active_session_count: number;
};

type AccountDevicesResponse = {
  max_active_devices: number;
  devices: AccountDevice[];
};

function formatDate(value: string | null, options?: Intl.DateTimeFormatOptions) {
  if (!value) return 'Chưa có';

  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) return 'Chưa có';

  return new Intl.DateTimeFormat(
    'vi-VN',
    options ?? {
      dateStyle: 'medium',
      timeStyle: 'short',
    },
  ).format(new Date(parsed));
}

export function ProfileView() {
  const { status, user } = usePortalAuth();
  const [isCheckoutLoading, setIsCheckoutLoading] = useState(false);
  const [deviceLimit, setDeviceLimit] = useState(0);
  const [devices, setDevices] = useState<AccountDevice[]>([]);
  const [isDevicesLoading, setIsDevicesLoading] = useState(true);
  const [activeDeviceAction, setActiveDeviceAction] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

  useEffect(() => {
    if (status !== 'authenticated') {
      setDevices([]);
      setDeviceLimit(0);
      setIsDevicesLoading(status === 'booting');
      return;
    }

    let ignore = false;
    setIsDevicesLoading(true);

    const hydrateDevices = async () => {
      try {
        const response = await apiClient.get<AccountDevicesResponse>('/api/auth/sessions');
        const data = response.data;
        if (ignore) return;
        setDeviceLimit(data.max_active_devices);
        setDevices(data.devices);
      } catch {
        if (!ignore) {
          setDevices([]);
        }
      } finally {
        if (!ignore) {
          setIsDevicesLoading(false);
        }
      }
    };

    void hydrateDevices();

    return () => {
      ignore = false;
    };
  }, [status]);

  const accountName = user?.name?.trim() || 'Notch User';
  const accountEmail = user?.email?.trim() || 'Chưa có email';
  const accountPlan = user?.is_pro ? 'pro' : 'free';
  const isWebDevice = (device: AccountDevice) => {
    return device.platform.toLowerCase() === 'web' || device.device_name.toLowerCase().includes('browser');
  };

  const activeDeviceCount = useMemo(
    () => devices.filter((device) => device.active && !isWebDevice(device)).length,
    [devices],
  );

  const mutateDevice = async (action: 'trust' | 'untrust' | 'revoke', deviceId: string) => {
    setActiveDeviceAction(deviceId);
    setMsg(null);

    try {
      const response = await apiClient.patch<AccountDevicesResponse>('/api/auth/sessions', {
        action,
        device_id: deviceId,
      });

      const data = response.data;

      if (!data || !('devices' in data)) {
        throw new Error('Không thể cập nhật thiết bị.');
      }

      setDeviceLimit(data.max_active_devices);
      setDevices(data.devices);
      setMsg({
        type: 'ok',
        text:
          action === 'revoke'
            ? 'Thiết bị đã được đăng xuất.'
            : action === 'trust'
              ? 'Thiết bị đã được đánh dấu tin cậy.'
              : 'Thiết bị đã bị bỏ tin cậy.',
      });
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Không thể cập nhật thiết bị.',
      });
    } finally {
      setActiveDeviceAction(null);
    }
  };

  const handleSubscribe = async () => {
    setIsCheckoutLoading(true);
    setMsg(null);

    try {
      const response = await apiClient.post<{ pay_url?: string; detail?: string }>('/api/payments/vnpay/create');
      const data = response.data;
      if (!data.pay_url) {
        throw new Error(data.detail || 'Không thể tạo phiên thanh toán VNPAY.');
      }

      window.location.href = data.pay_url;
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Không thể tạo phiên thanh toán VNPAY.',
      });
      setIsCheckoutLoading(false);
    }
  };

  if (status === 'booting') {
    return (
      <div className="dashboard-loading-full" style={{ minHeight: '60vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div className="loading-branding">
          <Loader2 size={32} className="portal-spinner animate-spin" style={{ margin: '0 auto 16px' }} />
          <p style={{ color: 'var(--muted)' }}>Đang đồng bộ dữ liệu tài khoản...</p>
        </div>
      </div>
    );
  }

  if (status === 'guest' || !user) {
    return null;
  }

  return (
    <div className="dashboard-container" style={{ paddingTop: '100px', paddingBottom: '100px' }}>
      <section className="dashboard-hero" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '32px', borderRadius: 'var(--radius-lg)', display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: '24px', marginBottom: '40px' }}>
        <div className="dashboard-hero-content">
          <div className="dashboard-user-info">
            <h1 style={{ fontSize: '2rem', fontWeight: 800, marginBottom: '8px' }}>Chào quay lại, {accountName}</h1>
            <div className="dashboard-user-meta" style={{ display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap', color: 'var(--muted)' }}>
              <span>{accountEmail}</span>
              <span className="meta-dot" style={{ width: '4px', height: '4px', background: 'var(--border-strong)', borderRadius: '50%' }} />
              <span className={`plan-badge ${accountPlan === 'pro' ? 'is-pro' : ''}`} style={{
                background: accountPlan === 'pro' ? 'linear-gradient(135deg, rgba(249, 115, 22, 0.15), rgba(168, 85, 247, 0.15))' : 'rgba(255,255,255,0.06)',
                border: accountPlan === 'pro' ? '1px solid rgba(249, 115, 22, 0.3)' : '1px solid var(--border)',
                color: accountPlan === 'pro' ? 'var(--warm)' : 'var(--muted-strong)',
                padding: '4px 12px',
                borderRadius: '999px',
                fontSize: '0.8rem',
                fontWeight: 600
              }}>
                {accountPlan === 'pro' ? 'Gói Pro' : 'Gói Miễn phí'}
              </span>
            </div>
          </div>
        </div>
        
        <div className="dashboard-hero-actions">
          {accountPlan !== 'pro' && (
            <button 
              className="dashboard-upgrade-cta portal-button" 
              onClick={handleSubscribe}
              disabled={isCheckoutLoading}
              style={{ background: 'var(--accent)', color: 'white', display: 'flex', alignItems: 'center', gap: '8px' }}
            >
              <Sparkles size={16} />
              <span>Nâng cấp Pro ngay</span>
            </button>
          )}
        </div>
      </section>

      {msg && (
        <div className={`dashboard-alert ${msg.type === 'ok' ? 'is-success' : 'is-error'}`} style={{
          padding: '16px',
          borderRadius: 'var(--radius-md)',
          marginBottom: '24px',
          fontSize: '0.9rem',
          border: '1px solid',
          borderColor: msg.type === 'ok' ? 'rgba(16, 185, 129, 0.2)' : 'rgba(239, 68, 68, 0.2)',
          background: msg.type === 'ok' ? 'rgba(16, 185, 129, 0.05)' : 'rgba(239, 68, 68, 0.05)',
          color: msg.type === 'ok' ? 'var(--green)' : 'var(--red)',
        }}>
          {msg.text}
        </div>
      )}

      <div className="dashboard-grid" style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '32px', alignItems: 'start' }}>
        {/* Main Content Area */}
        <div className="dashboard-main-col">
          <section className="dashboard-section" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '24px', borderRadius: 'var(--radius-lg)' }}>
            <div className="section-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border)', paddingBottom: '16px', marginBottom: '20px' }}>
              <div className="section-title" style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <MonitorSmartphone size={20} className="text-accent" style={{ color: 'var(--accent)' }} />
                <h2 style={{ fontSize: '1.25rem', fontWeight: 700 }}>Thiết bị của bạn</h2>
              </div>
              <span className="section-badge" style={{ fontSize: '0.85rem', color: 'var(--muted)', background: 'rgba(255,255,255,0.06)', padding: '2px 10px', borderRadius: '999px' }}>
                {activeDeviceCount}/{deviceLimit || '∞'}
              </span>
            </div>

            {isDevicesLoading ? (
              <div className="dashboard-loading-state" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '12px', padding: '40px 0' }}>
                <Loader2 size={24} className="portal-spinner animate-spin" style={{ color: 'var(--accent)' }} />
                <p style={{ color: 'var(--muted)', fontSize: '0.9rem' }}>Đang đồng bộ thiết bị...</p>
              </div>
            ) : (
              <div className="device-list-premium" style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                {devices.map((device) => (
                  <div 
                    key={device.device_id} 
                    className={`device-card-premium ${device.current ? 'is-current' : ''}`}
                    style={{
                      display: 'flex',
                      flexWrap: 'wrap',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: '16px',
                      padding: '16px',
                      borderRadius: 'var(--radius-md)',
                      background: device.current ? 'rgba(56, 189, 248, 0.04)' : 'rgba(255,255,255,0.01)',
                      border: device.current ? '1px solid rgba(56, 189, 248, 0.2)' : '1px solid var(--border)',
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                      <div className="device-icon" style={{
                        width: '40px',
                        height: '40px',
                        borderRadius: '50%',
                        background: 'rgba(255,255,255,0.04)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        color: device.current ? 'var(--accent)' : 'var(--muted)'
                      }}>
                        <MonitorSmartphone size={20} />
                      </div>
                      <div className="device-info">
                        <div className="device-name-row" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                          <h3 style={{ fontSize: '1rem', fontWeight: 600 }}>{device.device_name}</h3>
                          {device.current && <span className="current-pill" style={{ fontSize: '0.75rem', padding: '2px 8px', borderRadius: '999px', background: 'rgba(56, 189, 248, 0.15)', color: 'var(--accent)', fontWeight: 600 }}>Hiện tại</span>}
                          {device.trusted_at && <ShieldCheck size={16} className="trusted-icon" style={{ color: 'var(--green)' }} />}
                        </div>
                        <p style={{ color: 'var(--muted)', fontSize: '0.85rem', marginTop: '4px' }}>{device.platform} • Lần cuối: {formatDate(device.last_seen_at)}</p>
                      </div>
                    </div>
                    <div className="device-actions" style={{ display: 'flex', gap: '10px' }}>
                      <button
                        type="button"
                        className="portal-button-ghost"
                        disabled={activeDeviceAction === device.device_id}
                        onClick={() => mutateDevice(device.trusted_at ? 'untrust' : 'trust', device.device_id)}
                        style={{ height: '32px', padding: '0 12px', fontSize: '0.8rem', borderRadius: '999px' }}
                      >
                        {device.trusted_at ? 'Bỏ tin cậy' : 'Tin cậy'}
                      </button>
                      {!device.current && device.active && (
                        <button
                          type="button"
                          className="portal-button-ghost"
                          disabled={activeDeviceAction === device.device_id}
                          onClick={() => mutateDevice('revoke', device.device_id)}
                          style={{
                            height: '32px',
                            padding: '0 12px',
                            fontSize: '0.8rem',
                            borderRadius: '999px',
                            border: '1px solid rgba(239, 68, 68, 0.2)',
                            color: 'var(--red)',
                            background: 'rgba(239, 68, 68, 0.05)'
                          }}
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

        {/* Sidebar Info Area */}
        <div className="dashboard-side-col" style={{ display: 'grid', gap: '24px' }}>
          <section className="dashboard-section profile-mini-card" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '20px', borderRadius: 'var(--radius-lg)' }}>
            <div className="section-title" style={{ display: 'flex', alignItems: 'center', gap: '8px', borderBottom: '1px solid var(--border)', paddingBottom: '12px', marginBottom: '16px' }}>
              <ShieldCheck size={18} style={{ color: 'var(--green)' }} />
              <h2 style={{ fontSize: '1.05rem', fontWeight: 700 }}>Trạng thái tài khoản</h2>
            </div>
            <div className="security-status" style={{ display: 'flex', flexDirection: 'column', gap: '12px', fontSize: '0.9rem' }}>
              <div className="status-item" style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--muted)' }}>Xác thực</span>
                <strong style={{ color: 'var(--green)' }}>Đã liên kết Google</strong>
              </div>
              <div className="status-item" style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--muted)' }}>Ngày tham gia</span>
                <strong>{formatDate(user.created_at, { month: 'short', year: 'numeric' })}</strong>
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
