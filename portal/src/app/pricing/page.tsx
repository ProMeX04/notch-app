'use client';

import Link from 'next/link';
import { Check, ArrowRight, Sparkles, Zap, Shield, Globe, Cpu } from 'lucide-react';
import { PortalLogo } from '@/components/portal/PortalLogo';

const features = [
  { name: 'Gemini Live AI', free: false, pro: true, desc: 'Tích hợp AI thời gian thực trực tiếp vào Notch.' },
  { name: 'Đồng bộ thiết bị', free: true, pro: true, desc: 'Lưu cài đặt của bạn trên mọi máy Mac.' },
  { name: 'Truy cập Beta', free: false, pro: true, desc: 'Trải nghiệm sớm các tính năng mới nhất.' },
  { name: 'Ưu tiên hỗ trợ', free: false, pro: true, desc: 'Nhận phản hồi nhanh từ đội ngũ phát triển.' },
  { name: 'Toàn bộ tính năng Media', free: true, pro: true, desc: 'Điều khiển nhạc và video cơ bản.' },
  { name: 'Custom Animations', free: false, pro: true, desc: 'Tùy biến hiệu ứng hiển thị của Notch.' },
];

export default function PricingPage() {
  return (
    <main className="portal-pricing-page" style={{ position: 'relative', overflow: 'hidden' }}>
      <div className="portal-bg-mesh" />
      <header className="portal-pricing-header">
        <PortalLogo />
        <nav className="portal-pricing-nav">
          <Link href="/" className="portal-text-link">Sản phẩm</Link>
          <Link href="/login" className="portal-button-ghost">Đăng nhập</Link>
          <Link href="/signup" className="portal-button">Bắt đầu miễn phí</Link>
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
            <li><Check size={18} /> Đồng bộ cơ bản</li>
            <li><Check size={18} /> Media controls</li>
            <li className="disabled"><Check size={18} /> Gemini Live AI</li>
            <li className="disabled"><Check size={18} /> Custom Animations</li>
          </ul>
          <Link href="/signup" className="portal-button-secondary-large">
            Bắt đầu ngay
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
            <li><Check size={18} /> Gemini Live AI mạnh mẽ</li>
            <li><Check size={18} /> Custom Animations độc quyền</li>
            <li><Check size={18} /> Ưu tiên cập nhật tính năng</li>
            <li><Check size={18} /> Đồng bộ Cloud không giới hạn</li>
          </ul>
          <Link href="/upgrade" className="portal-button-primary-large">
            Nâng cấp lên Pro
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
          {features.map((f) => (
            <div key={f.name} className="comparison-row">
              <div className="feature-info">
                <h3>{f.name}</h3>
                <p>{f.desc}</p>
              </div>
              <div className="plan-status">
                <div className="status-col">
                  <span>Free</span>
                  {f.free ? <Check size={20} className="check" /> : <div className="dash" />}
                </div>
                <div className="status-col">
                  <span>Pro</span>
                  {f.pro ? <Check size={20} className="check pro" /> : <div className="dash" />}
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
