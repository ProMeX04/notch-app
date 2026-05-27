'use client';

import Link from 'next/link';
import { ArrowRight, Check, Sparkles } from 'lucide-react';
import { usePortalAuth } from '@/components/portal/PortalAuthProvider';
import { PortalLogo } from '@/components/portal/PortalLogo';

export default function UpgradePage() {
  const { isAuthenticated } = usePortalAuth();

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
          <div className="portal-badge-pro" style={{ marginBottom: '16px', background: 'var(--accent-soft)', color: 'var(--accent)', border: '1px solid rgba(56, 189, 248, 0.2)' }}>
            <Sparkles size={14} />
            Notch Pro Upgrade
          </div>
          <h1 className="portal-auth-title-large" style={{ fontSize: '3.5rem', fontWeight: 900, letterSpacing: '-0.06em', marginBottom: '16px' }}>
            Cần tài khoản để nâng cấp Pro
          </h1>
          <p className="portal-muted" style={{ fontSize: '1.1rem', maxWidth: '400px', margin: '0 auto 32px' }}>
            Luồng thanh toán guest đã được tắt. Hãy đăng nhập hoặc tạo tài khoản rồi vào trang cá nhân để thanh toán VNPAY.
          </p>
        </div>

        <div className="portal-auth-card portal-glass-card" style={{ padding: '48px' }}>
          <div className="portal-auth-info-box" style={{ display: 'grid', gap: '14px' }}>
            <div className="info-item" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyItems: 'center', flexShrink: 0 }}>
                <Check size={14} style={{ margin: 'auto' }} />
              </div>
              <span>Đăng nhập hoặc Đăng ký bằng Google</span>
            </div>
            <div className="info-item" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyItems: 'center', flexShrink: 0 }}>
                <Check size={14} style={{ margin: 'auto' }} />
              </div>
              <span>Vào trang tài khoản `/pro`</span>
            </div>
            <div className="info-item" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'var(--foreground)', fontWeight: 600 }}>
              <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyItems: 'center', flexShrink: 0 }}>
                <Check size={14} style={{ margin: 'auto' }} />
              </div>
              <span>Thanh toán VNPAY sau khi đã xác thực</span>
            </div>
          </div>

          <div style={{ display: 'grid', gap: '12px', marginTop: '24px' }}>
            <Link href={isAuthenticated ? '/pro' : '/api/auth/google'} className="portal-button" style={{ width: '100%', height: '60px', borderRadius: '18px', fontSize: '1.1rem', boxShadow: '0 10px 20px rgba(37, 99, 235, 0.2)' }}>
              {isAuthenticated ? 'Vào trang tài khoản' : 'Đăng nhập với Google để nâng cấp'}
              <ArrowRight size={20} />
            </Link>
          </div>

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
          Đã đăng nhập rồi? <Link href="/pro" style={{ color: 'var(--accent)', fontWeight: 800 }}>Vào trang cá nhân để nâng cấp</Link>
        </p>
      </section>
    </main>
  );
}
