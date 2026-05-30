'use client';

import { BookOpen, Code, ShieldCheck } from 'lucide-react';
import { Navbar } from '@/components/portal/Navbar';

export default function DocsPage() {
  const sections = [
    {
      title: 'Pomodoro & Focus',
      icon: ShieldCheck,
      color: 'var(--purple)',
      desc: 'Giữ sự tập trung tối đa bằng cách khởi chạy đồng hồ Pomodoro trực tiếp trên Notch. Đặt thời gian làm việc và nghỉ ngơi nhanh bằng cách kéo thanh trượt.'
    },
    {
      title: 'Shelf Kéo Thả',
      icon: BookOpen,
      color: 'var(--accent)',
      desc: 'Khi cần lưu trữ file tạm thời, chỉ cần kéo tệp tin, hình ảnh hoặc link liên kết bất kỳ rồi rê lên vùng Notch. Tệp tin sẽ được ghim lại sẵn sàng để kéo đi bất cứ đâu.'
    },
    {
      title: 'WebSocket Bridge',
      icon: Code,
      color: 'var(--green)',
      desc: 'Ứng dụng macOS mở một cổng WebSocket cục bộ tại ws://127.0.0.1:44991 để truyền phát trạng thái Focus tới extension trình duyệt giúp tự động chặn website.'
    }
  ];

  return (
    <main className="landing-page" style={{ background: 'var(--background)', color: 'var(--foreground)', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <Navbar />

      <div className="portal-shell" style={{ flex: 1, paddingTop: '160px', paddingBottom: '100px' }}>
        <header style={{ textAlign: 'center', marginBottom: '60px' }}>
          <span className="portal-badge" style={{ marginBottom: '16px' }}>Documentation</span>
          <h1 style={{ fontSize: 'clamp(2.5rem, 6vw, 4rem)', fontWeight: 800 }}>Tài liệu hướng dẫn</h1>
          <p style={{ color: 'var(--muted)', maxWidth: '600px', margin: '16px auto 0', fontSize: '1.1rem' }}>
            Hướng dẫn thiết lập, phím tắt và cấu hình kết nối ứng dụng Notch trên hệ điều hành macOS.
          </p>
        </header>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '24px', maxWidth: '800px', margin: '0 auto' }}>
          {sections.map((s, index) => (
            <section key={index} className="portal-card" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '32px', borderRadius: 'var(--radius-lg)' }}>
              <div style={{ display: 'flex', gap: '16px', alignItems: 'flex-start' }}>
                <div style={{
                  width: '44px',
                  height: '44px',
                  borderRadius: '12px',
                  background: 'rgba(255,255,255,0.03)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: s.color,
                  border: '1px solid var(--border)',
                  flexShrink: 0
                }}>
                  <s.icon size={22} />
                </div>
                <div>
                  <h2 style={{ fontSize: '1.25rem', fontWeight: 800, marginBottom: '8px' }}>{s.title}</h2>
                  <p style={{ color: 'var(--muted)', fontSize: '0.95rem', lineHeight: 1.6 }}>{s.desc}</p>
                </div>
              </div>
            </section>
          ))}
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
