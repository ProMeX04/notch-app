'use client';

import { type FormEvent, useState } from 'react';
import Link from 'next/link';
import { ArrowRight, Check, Loader2, Sparkles, Mail } from 'lucide-react';
import { PortalLogo } from '@/components/portal/PortalLogo';

export default function UpgradePage() {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [email, setEmail] = useState('');

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/payments/vnpay/create-guest', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.detail || 'Không thể tạo phiên thanh toán. Vui lòng thử lại.');
      }

      if (data.pay_url) {
        window.location.href = data.pay_url;
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Không thể kết nối máy chủ.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <main className="portal-auth-page-centered" style={{ position: 'relative', overflow: 'hidden' }}>
      <div className="portal-bg-mesh" />
      
      <div className="portal-auth-topbar-minimal">
        <PortalLogo />
        <Link href="/pricing" className="portal-button-ghost" style={{ backdropFilter: 'blur(8px)' }}>
          Xem bảng giá
        </Link>
      </div>

      <section className="portal-auth-container" style={{ position: 'relative', zIndex: 1 }}>
        <div className="portal-auth-header-centered">
          <div className="portal-badge-pro" style={{ marginBottom: '16px', background: 'rgba(37, 99, 235, 0.1)', color: 'var(--accent)', border: '1px solid rgba(37, 99, 235, 0.2)' }}>
            <Sparkles size={14} />
            Notch Pro Upgrade
          </div>
          <h1 className="portal-auth-title-large" style={{ fontSize: '3.5rem', fontWeight: 900, letterSpacing: '-0.06em', marginBottom: '16px' }}>
            Chỉ một bước nữa
          </h1>
          <p className="portal-muted" style={{ fontSize: '1.1rem', maxWidth: '400px', margin: '0 auto 32px' }}>
            Nhập email của bạn để bắt đầu thanh toán nâng cấp Pro.
          </p>
        </div>

        <div className="portal-auth-card portal-glass-card" style={{ padding: '48px' }}>
          <form className="portal-auth-form" onSubmit={handleSubmit}>
            {error ? (
              <div className="portal-error" style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#dc2626', padding: '12px', borderRadius: '12px', fontSize: '0.9rem', marginBottom: '8px' }}>
                {error}
              </div>
            ) : null}
            
            <div className="portal-field">
              <label htmlFor="email" style={{ fontSize: '0.85rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em', color: 'var(--muted)', marginBottom: '10px', display: 'block' }}>
                Email tài khoản
              </label>
              <div style={{ position: 'relative' }}>
                <input 
                  className="portal-input" 
                  style={{ 
                    paddingLeft: '44px', 
                    height: '56px', 
                    borderRadius: '16px', 
                    fontSize: '1.05rem', 
                    background: 'rgba(255, 255, 255, 0.8)',
                    border: '1px solid rgba(0, 0, 0, 0.1)',
                    width: '100%'
                  }}
                  type="email" 
                  id="email" 
                  name="email" 
                  placeholder="email@example.com" 
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required 
                />
                <Mail size={20} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', opacity: 0.4, color: 'var(--accent)' }} />
              </div>
              <p className="portal-input-hint" style={{ marginTop: '12px', fontSize: '13px', color: 'var(--muted)', fontWeight: 500 }}>
                Nếu chưa có tài khoản, chúng tôi sẽ tự động tạo cho bạn.
              </p>
            </div>

            <button 
              type="submit" 
              className="portal-button" 
              disabled={isLoading || !email} 
              style={{ 
                width: '100%', 
                marginTop: '12px', 
                height: '60px', 
                borderRadius: '18px', 
                fontSize: '1.1rem',
                boxShadow: '0 10px 20px rgba(37, 99, 235, 0.2)'
              }}
            >
              {isLoading ? (
                <>
                  <Loader2 size={20} className="portal-spinner" />
                  Đang chuẩn bị thanh toán...
                </>
              ) : (
                <>
                  Tiếp tục thanh toán VNPAY
                  <ArrowRight size={20} />
                </>
              )}
            </button>
          </form>

          <div className="portal-divider" style={{ margin: '32px 0' }} />
          
          <div className="portal-auth-info-box" style={{ display: 'grid', gap: '14px' }}>
            <div className="info-item" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyItems: 'center', flexShrink: 0 }}>
                <Check size={14} style={{ margin: 'auto' }} />
              </div>
              <span>Giá chỉ 99,000 VND</span>
            </div>
            <div className="info-item" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyItems: 'center', flexShrink: 0 }}>
                <Check size={14} style={{ margin: 'auto' }} />
              </div>
              <span>Dùng vĩnh viễn không gia hạn</span>
            </div>
            <div className="info-item" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyItems: 'center', flexShrink: 0 }}>
                <Check size={14} style={{ margin: 'auto' }} />
              </div>
              <span>Mở khóa toàn bộ tính năng AI</span>
            </div>
          </div>
        </div>

        <p className="portal-auth-footer-simple" style={{ marginTop: '32px', fontSize: '1rem' }}>
          Bạn đã đăng nhập? <Link href="/pro" style={{ color: 'var(--accent)', fontWeight: 800 }}>Vào trang cá nhân</Link>
        </p>
      </section>
    </main>
  );
}
