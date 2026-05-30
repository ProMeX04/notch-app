'use client';

import { Sparkles, Terminal, Heart } from 'lucide-react';
import { Navbar } from '@/components/portal/Navbar';

export default function AboutPage() {
  return (
    <main className="landing-page" style={{ background: 'var(--background)', color: 'var(--foreground)', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <Navbar />

      <div className="portal-shell" style={{ flex: 1, paddingTop: '160px', paddingBottom: '100px' }}>
        <header style={{ textAlign: 'center', marginBottom: '60px' }}>
          <span className="portal-badge" style={{ marginBottom: '16px' }}>Về Notch</span>
          <h1 style={{ fontSize: 'clamp(2.5rem, 6vw, 4rem)', fontWeight: 800 }}>Dự án Notch</h1>
          <p style={{ color: 'var(--muted)', maxWidth: '600px', margin: '16px auto 0', fontSize: '1.1rem' }}>
            Chúng tôi kiến tạo trải nghiệm tương tác tối giản ngay trên thanh notch của MacBook.
          </p>
        </header>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '32px', maxWidth: '800px', margin: '0 auto' }}>
          {/* Mission Card */}
          <section className="portal-card" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '40px', borderRadius: 'var(--radius-xl)' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '10px' }}>
              <Sparkles size={20} style={{ color: 'var(--accent)' }} />
              Sứ mệnh sản phẩm
            </h2>
            <p style={{ color: 'var(--muted)', fontSize: '1rem', lineHeight: 1.6 }}>
              Biến vùng khuyết (notch) vô dụng trên màn hình MacBook thành một trợ lý hiệu năng đắc lực. Thay vì cài đặt nhiều phần mềm chạy ngầm cồng kềnh, Notch tích hợp toàn bộ các tính năng từ Shelf lưu tệp tin tạm thời, Đồng hồ tập trung Pomodoro, tới Điều khiển bài hát và Trợ lý Gemini AI trong một ứng dụng duy nhất, siêu mượt và siêu nhẹ.
            </p>
          </section>

          {/* Development Card */}
          <section className="portal-card" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '40px', borderRadius: 'var(--radius-xl)' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '10px' }}>
              <Terminal size={20} style={{ color: 'var(--purple)' }} />
              Phát triển bằng Swift nguyên bản
            </h2>
            <p style={{ color: 'var(--muted)', fontSize: '1rem', lineHeight: 1.6 }}>
              Notch được lập trình hoàn toàn bằng SwiftPM nguyên bản không thông qua các bộ khung trung gian để đảm bảo mức tiêu hao tài nguyên CPU và bộ nhớ RAM ở mức tối thiểu. Chúng tôi chú trọng từng chi tiết chuyển động (animation) mượt mà để đồng bộ hoàn hảo với hệ điều hành macOS.
            </p>
          </section>
        </div>

        <div style={{ textAlign: 'center', marginTop: '60px', color: 'var(--muted)', fontSize: '0.9rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
          <span>Phát triển với</span>
          <Heart size={14} style={{ color: 'var(--red)' }} />
          <span>bởi đội ngũ kỹ sư Notch.</span>
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
