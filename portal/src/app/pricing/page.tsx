'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Check, ArrowRight, Loader2 } from 'lucide-react';
import { PortalLogo } from '@/components/portal/PortalLogo';
import { usePortalAuth } from '@/components/portal/PortalAuthProvider';

export default function PricingPage() {
  const { isAuthenticated, user } = usePortalAuth();
  const [capabilities, setCapabilities] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/capabilities")
      .then(res => res.json())
      .then(data => {
        setCapabilities(Array.isArray(data) ? data : []);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  const primaryHref = isAuthenticated ? '/pro' : '/signup';
  const primaryLabel = isAuthenticated ? 'Mở portal' : 'Bắt đầu miễn phí';
  const secondaryHref = isAuthenticated ? '/pro' : '/login';
  const secondaryLabel = isAuthenticated ? (user?.name?.trim() || 'Tài khoản') : 'Đăng nhập';

  if (loading) {
    return (
      <div className="h-screen w-full flex items-center justify-center bg-white">
        <Loader2 className="animate-spin text-[var(--accent)]" size={48} />
      </div>
    );
  }

  const freeFeatures = capabilities.filter(c => !c.isProOnly);
  const proFeatures = capabilities.filter(c => c.isProOnly);

  return (
    <main className="portal-pricing-page" style={{ position: 'relative', overflow: 'hidden' }}>
      <div className="portal-bg-mesh" />
      <header className="portal-pricing-header">
        <PortalLogo />
        <nav className="portal-pricing-nav">
          <Link href="/" className="portal-text-link">Sản phẩm</Link>
          <Link href={secondaryHref} className="portal-button-ghost">{secondaryLabel}</Link>
          <Link href={primaryHref} className="portal-button">{primaryLabel}</Link>
        </nav>
      </header>

      <section className="portal-pricing-hero">
        <h1 className="portal-pricing-title">Đầu tư một lần,<br />dùng Notch mãi mãi.</h1>
        <p className="portal-pricing-subtitle">Chọn gói phù hợp với nhu cầu của bạn. Nâng cấp bất cứ lúc nào.</p>
      </section>

      <div className="portal-pricing-grid">
        {/* Free Plan */}
        <div className="portal-pricing-card">
          <div className="card-header">
            <h2>Miễn phí</h2>
            <div className="price">
              <span className="amount">0</span>
              <span className="currency">VND</span>
            </div>
            <p>Trải nghiệm Notch cơ bản</p>
          </div>
          <div className="portal-divider-subtle" />
          <ul className="feature-list">
            {freeFeatures.map(f => (
              <li key={f.key}><Check size={18} /> {f.name}</li>
            ))}
            {proFeatures.slice(0, 2).map(f => (
              <li key={f.key} className="disabled"><Check size={18} /> {f.name}</li>
            ))}
          </ul>
          <Link href={primaryHref} className="portal-button-secondary-large">
            {isAuthenticated ? 'Mở portal' : 'Bắt đầu ngay'}
          </Link>
        </div>

        {/* Pro Plan */}
        <div className="portal-pricing-card featured">
          <div className="badge-featured">Phổ biến nhất</div>
          <div className="card-header">
            <h2>Notch Pro</h2>
            <div className="price">
              <span className="amount">99,000</span>
              <span className="currency">VND</span>
            </div>
            <p>Toàn bộ quyền lực trong tay bạn</p>
          </div>
          <div className="portal-divider-subtle" />
          <ul className="feature-list">
            <li><Check size={18} /> <strong>Mọi tính năng từ gói Free</strong></li>
            {proFeatures.map(f => (
              <li key={f.key}><Check size={18} /> {f.name}</li>
            ))}
          </ul>
          <Link href={primaryHref} className="portal-button-primary-large">
            {isAuthenticated ? 'Vào portal để nâng cấp' : 'Tạo tài khoản để nâng cấp'}
            <ArrowRight size={18} />
          </Link>
        </div>
      </div>

      <section className="portal-pricing-comparison">
        <div className="comparison-header">
          <h2>So sánh chi tiết</h2>
          <p>Mọi thứ bạn cần biết về Notch và Notch Pro.</p>
        </div>

        <div className="comparison-table">
          {capabilities.map((f) => (
            <div key={f.key} className="comparison-row">
              <div className="feature-info">
                <h3>{f.name}</h3>
                <p>{f.description}</p>
              </div>
              <div className="plan-status">
                <div className="status-col">
                  <span>Free</span>
                  {!f.isProOnly ? <Check size={20} className="check" /> : <div className="dash" />}
                </div>
                <div className="status-col">
                  <span>Pro</span>
                  <Check size={20} className="check pro" />
                </div>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="portal-pricing-faq">
        <h2>Câu hỏi thường gặp</h2>
        <div className="faq-grid">
          <div className="faq-item">
            <h3>Thanh toán một lần hay hàng tháng?</h3>
            <p>Hiện tại Notch Pro là thanh toán một lần. Bạn chỉ cần trả 99,000 VND để sở hữu vĩnh viễn các tính năng hiện có và tương lai.</p>
          </div>
          <div className="faq-item">
            <h3>Tôi có thể dùng trên nhiều máy Mac không?</h3>
            <p>Có, chỉ cần đăng nhập cùng một tài khoản Notch, gói Pro của bạn sẽ được đồng bộ trên mọi thiết bị bạn sở hữu.</p>
          </div>
        </div>
      </section>

      <footer className="portal-pricing-footer">
        <PortalLogo />
        <p>&copy; 2026 Notch App. All rights reserved.</p>
      </footer>
    </main>
  );
}
