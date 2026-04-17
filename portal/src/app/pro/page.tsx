'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  ArrowRight,
  BrainCircuit,
  Check,
  CreditCard,
  FolderKanban,
  Loader2,
  LogOut,
  ShieldCheck,
  Sparkles,
  UserRound,
  Waves,
} from 'lucide-react';
import { PortalLogo } from '@/components/portal/PortalLogo';
import { authenticatedFetch, signOutImmediately } from '@/lib/portal-auth-client';

type AccountPlan = 'free' | 'pro';
type AccountMe = {
  id: string;
  email: string;
  name: string | null;
  created_at: string;
  is_pro: boolean;
};

const appCapabilities = [
  {
    icon: BrainCircuit,
    title: 'Gemini Live trong đúng ngữ cảnh',
    description: 'Giữ trợ lý AI gần thao tác đang làm thay vì tách thành một tab hoặc cửa sổ khác.',
  },
  {
    icon: FolderKanban,
    title: 'Shelf kéo thả cho file và link',
    description: 'Thu gom tài liệu đang dùng trong phiên làm việc, đỡ mất thời gian tìm lại.',
  },
  {
    icon: Waves,
    title: 'Media controls liền mạch',
    description: 'Đổi bài, theo dõi phát nhạc và giữ nhịp làm việc mà không rời app chính.',
  },
];

const premiumFeatures = [
  'Mở rộng quyền truy cập Gemini Live khi dùng các tính năng AI thời gian thực.',
  'Ưu tiên các trải nghiệm mới và khu vực thử nghiệm đang được phát triển.',
  'Quản lý tài khoản và kích hoạt thanh toán VNPAY ngay trong web portal.',
];

export default function ProPage() {
  const [isLoading, setIsLoading] = useState(false);
  const [isAccountLoading, setIsAccountLoading] = useState(true);
  const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);
  const [accountEmail, setAccountEmail] = useState('');
  const [accountName, setAccountName] = useState('');
  const [accountPlan, setAccountPlan] = useState<AccountPlan>('free');
  const [createdAt, setCreatedAt] = useState<string | null>(null);

  useEffect(() => {
    let ignore = false;

    const hydrateAccount = async () => {
      try {
        const response = await authenticatedFetch('/api/auth/me');

        if (!response.ok) {
          throw new Error('Phiên đăng nhập đã hết hạn');
        }

        const data = (await response.json()) as AccountMe;
        if (ignore) return;

        setAccountEmail(data.email ?? '');
        setAccountName(data.name ?? '');
        setAccountPlan(data.is_pro ? 'pro' : 'free');
        setCreatedAt(data.created_at);
      } catch {
        signOutImmediately();

        if (!ignore) {
          setAccountEmail('');
          setAccountName('');
          setAccountPlan('free');
          setCreatedAt(null);
        }
      } finally {
        if (!ignore) {
          setIsAccountLoading(false);
        }
      }
    };

    hydrateAccount();

    return () => {
      ignore = true;
    };
  }, []);

  const title = useMemo(() => {
    if (accountName.trim()) return accountName.trim();
    if (accountEmail.trim()) return accountEmail.trim();
    return 'Tài khoản Notch của bạn';
  }, [accountEmail, accountName]);

  const subtitle = accountEmail.trim()
    ? 'Tài khoản đã được kết nối và sẵn sàng dùng trong Notch app.'
    : 'Đăng nhập để tải thông tin tài khoản, gói hiện tại và quyền truy cập trên app.';

  const hasAccount = Boolean(accountEmail.trim() || accountName.trim());
  const memberSince = createdAt
    ? new Intl.DateTimeFormat('vi-VN', { month: 'long', year: 'numeric' }).format(new Date(createdAt))
    : null;

  const handleSubscribe = async () => {
    setIsLoading(true);
    setMsg(null);

    try {
      const response = await authenticatedFetch('/api/payments/vnpay/create', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      const data = (await response.json()) as { pay_url?: string; detail?: string };
      if (!response.ok || !data.pay_url) {
        throw new Error(data.detail || 'Không thể tạo phiên thanh toán VNPAY.');
      }

      window.location.href = data.pay_url;
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Không thể tạo phiên thanh toán VNPAY.',
      });
      setIsLoading(false);
    }
  };

  const handleSignOut = async () => {
    signOutImmediately();
    window.location.replace('/login');
  };

  return (
    <main className="portal-pro-container">
      <header className="portal-pro-header">
        <PortalLogo />
        <nav className="portal-pro-nav">
          <Link href="/" className="portal-button-ghost">Trang chủ</Link>
        </nav>
      </header>

      <div className="portal-pro-content">
        <section className="portal-pro-hero">
          <div className="portal-pro-user-info">
            <div className="portal-avatar-large">
              {accountName?.charAt(0) || 'U'}
            </div>
            <div>
              <span className="portal-badge-pro">
                {accountPlan === 'pro' ? 'Premium Member' : 'Free Account'}
              </span>
              <h1>{isAccountLoading ? 'Đang tải...' : accountName || 'Người dùng Notch'}</h1>
              <p className="portal-muted">{accountEmail}</p>
            </div>
          </div>
          
          <div className="portal-pro-hero-actions">
            {accountPlan !== 'pro' && (
              <button className="portal-button-pro" onClick={handleSubscribe} disabled={isLoading}>
                {isLoading ? 'Đang chuẩn bị...' : 'Nâng cấp Premium'}
              </button>
            )}
          </div>
        </section>

        <div className="portal-pro-grid">
          <div className="portal-card-pro">
            <div className="portal-card-pro-header">
              <UserRound size={20} />
              <h2>Chi tiết tài khoản</h2>
            </div>
            <div className="portal-pro-details">
              <div className="portal-pro-row">
                <label>Email liên kết</label>
                <span>{accountEmail}</span>
              </div>
              <div className="portal-pro-row">
                <label>Ngày tham gia</label>
                <span>{memberSince}</span>
              </div>
              <div className="portal-pro-row">
                <label>Trạng thái gói</label>
                <span className={accountPlan === 'pro' ? 'status-pro' : ''}>
                  {accountPlan === 'pro' ? 'Đã kích hoạt Premium' : 'Đang sử dụng bản miễn phí'}
                </span>
              </div>

              <div className="portal-pro-divider" />
              
              <button onClick={handleSignOut} className="portal-button-ghost" style={{ justifyContent: 'flex-start', padding: '0', height: 'auto', fontWeight: 600, color: 'var(--muted-strong)' }}>
                Đăng xuất khỏi thiết bị này
              </button>
            </div>
          </div>

          <div className="portal-card-pro portal-card-dark">
            <div className="portal-card-pro-header">
              <Sparkles size={20} color="var(--accent)" />
              <h2>Quyền lợi Notch Pro</h2>
            </div>
            
            <ul className="portal-pro-features">
              {premiumFeatures.map((feature) => (
                <li key={feature}>
                  <Check size={16} />
                  {feature}
                </li>
              ))}
            </ul>

            <div className="portal-pro-price-tag">
              <span className="amount">99,000</span>
              <span className="currency">VND</span>
            </div>

            <button 
              className={`portal-button-upgrade ${accountPlan === 'pro' ? 'is-active' : ''}`}
              onClick={handleSubscribe}
              disabled={isLoading || accountPlan === 'pro'}
            >
              {accountPlan === 'pro' ? 'Bạn đang là thành viên Pro' : 'Nâng cấp ngay với VNPAY'}
            </button>
            
            {msg && <p className="portal-pro-msg">{msg.text}</p>}
          </div>
        </div>

        <footer className="portal-pro-footer">
          <p>Mở Notch app trên Mac và chọn <strong>Refresh Pro status</strong> sau khi thanh toán thành công.</p>
        </footer>
      </div>
    </main>
  );
}
