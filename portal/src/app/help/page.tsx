'use client';

import { HelpCircle, Mail, MessageSquare } from 'lucide-react';
import { Navbar } from '@/components/portal/Navbar';

export default function HelpPage() {
  const faqs = [
    {
      q: 'Làm sao để kết nối Chrome Focus Blocker?',
      a: 'Hãy bật cổng WebSocket Bridge trong Notch App Settings. Sau đó mở Chrome extensions, bật Developer mode, chọn "Load unpacked" và chọn thư mục chrome-extension/notch-focus-blocker có sẵn trong repo.'
    },
    {
      q: 'Làm sao để nâng cấp tài khoản Pro?',
      a: 'Sau khi đăng nhập bằng Google trên trang chủ Portal, bạn sẽ được tự động đưa đến trang cá nhân. Nhấn nút "Nâng cấp Pro ngay" để chuyển tiếp qua cổng VNPAY thực hiện giao dịch.'
    },
    {
      q: 'Tại sao app không thể mở sau khi tải về?',
      a: 'Do cơ chế bảo mật Gatekeeper của macOS chặn phần mềm ngoài App Store. Bạn hãy vào System Settings > Privacy & Security, kéo xuống dưới cùng mục Security và chọn "Open Anyway" là xong.'
    }
  ];

  return (
    <main className="landing-page" style={{ background: 'var(--background)', color: 'var(--foreground)', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <Navbar />

      <div className="portal-shell" style={{ flex: 1, paddingTop: '160px', paddingBottom: '100px' }}>
        <header style={{ textAlign: 'center', marginBottom: '60px' }}>
          <span className="portal-badge" style={{ marginBottom: '16px' }}>Hỗ trợ</span>
          <h1 style={{ fontSize: 'clamp(2.5rem, 6vw, 4rem)', fontWeight: 800 }}>Trợ giúp & FAQ</h1>
          <p style={{ color: 'var(--muted)', maxWidth: '600px', margin: '16px auto 0', fontSize: '1.1rem' }}>
            Tìm câu trả lời cho các vấn đề thường gặp hoặc liên hệ trực tiếp với bộ phận hỗ trợ kỹ thuật của chúng tôi.
          </p>
        </header>

        {/* FAQs */}
        <div style={{ maxWidth: '800px', margin: '0 auto 48px' }}>
          <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '24px', textAlign: 'center' }}>Câu hỏi thường gặp</h2>
          <div style={{ display: 'grid', gap: '20px' }}>
            {faqs.map((faq, index) => (
              <div key={index} className="portal-card" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '24px', borderRadius: 'var(--radius-lg)' }}>
                <h3 style={{ fontSize: '1.1rem', fontWeight: 700, marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <HelpCircle size={18} style={{ color: 'var(--accent)' }} />
                  {faq.q}
                </h3>
                <p style={{ color: 'var(--muted)', fontSize: '0.95rem', lineHeight: 1.6 }}>{faq.a}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Contact Info */}
        <div className="portal-card" style={{ background: 'linear-gradient(180deg, rgba(255,255,255,0.03) 0%, transparent 100%)', border: '1px solid var(--border)', padding: '40px', borderRadius: 'var(--radius-xl)', maxWidth: '800px', margin: '0 auto', textAlign: 'center' }}>
          <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '12px' }}>Không tìm thấy câu trả lời?</h2>
          <p style={{ color: 'var(--muted)', marginBottom: '28px' }}>Liên hệ trực tiếp với chúng tôi qua các kênh hỗ trợ kỹ thuật bên dưới.</p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '24px', flexWrap: 'wrap' }}>
            <a href="mailto:support@notch.app" className="portal-button-ghost" style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '12px 24px', borderRadius: '999px' }}>
              <Mail size={16} />
              <span>support@notch.app</span>
            </a>
            <a href="https://github.com/ProMeX04/notch-app/issues" target="_blank" rel="noopener noreferrer" className="portal-button-ghost" style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '12px 24px', borderRadius: '999px' }}>
              <MessageSquare size={16} />
              <span>Báo lỗi trên GitHub</span>
            </a>
          </div>
        </div>
      </div>

      <footer style={{ borderTop: '1px solid var(--border)', padding: '60px 0', background: 'var(--background)' }}>
        <div className="portal-shell" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ fontSize: '1.1rem', fontWeight: 800 }}>Notch App</div>
          <p style={{ color: 'var(--muted)', fontSize: '0.9rem' }}>&copy; 2026 Notch App. Built for macOS.</p>
        </div>
      </footer>
    </main>
  );
}
