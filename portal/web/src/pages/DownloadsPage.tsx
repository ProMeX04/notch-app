import { Download, Globe, ShieldAlert } from 'lucide-react'
import { PageShell } from '@/components/ui/PageShell'

export function DownloadsPage() {
  return (
    <PageShell>
      <main style={{ minHeight: '80vh', display: 'flex', flexDirection: 'column', padding: '40px 20px' }}>
        <header style={{ textAlign: 'center', marginBottom: '60px' }}>
          <span className="portal-badge" style={{ marginBottom: '16px', display: 'inline-block' }}>Cài đặt</span>
          <h1 style={{ fontSize: 'clamp(2.5rem, 6vw, 4rem)', fontWeight: 800, margin: '0 0 16px 0', letterSpacing: '-0.03em' }}>Tải ứng dụng Notch</h1>
          <p style={{ color: 'var(--muted)', maxWidth: '600px', margin: '0 auto', fontSize: '1.1rem', lineHeight: '1.5' }}>
            Hỗ trợ đầy đủ macOS Sonoma (14.0) trở lên. Trải nghiệm tập trung Pomodoro và điều khiển media đỉnh cao.
          </p>
        </header>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '32px', maxWidth: '1000px', width: '100%', margin: '0 auto' }}>
          {/* macOS App Card */}
          <div className="portal-card" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '40px', borderRadius: '24px', display: 'flex', flexDirection: 'column' }}>
            <div style={{ color: 'var(--accent)', marginBottom: '24px' }}>
              <Download size={40} />
            </div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '12px' }}>Notch cho macOS</h2>
            <p style={{ color: 'var(--muted)', flex: 1, marginBottom: '24px', lineHeight: '1.5' }}>
              Bản build chính thức hỗ trợ chip Apple Silicon (M1/M2/M3/M4) và Intel. Cài đặt trực tiếp qua file DMG.
            </p>
            <button type="button" className="portal-button" style={{ width: '100%', height: '50px', background: 'white', color: 'black', border: 'none', borderRadius: '12px', fontWeight: 600, cursor: 'pointer' }}>
              Tải xuống .DMG (Universal)
            </button>
          </div>

          {/* Chrome Extension Card */}
          <div className="portal-card" style={{ background: 'var(--card)', border: '1px solid var(--border)', padding: '40px', borderRadius: '24px', display: 'flex', flexDirection: 'column' }}>
            <div style={{ color: '#a855f7', marginBottom: '24px' }}>
              <Globe size={40} />
            </div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '12px' }}>Chrome Focus Blocker</h2>
            <p style={{ color: 'var(--muted)', flex: 1, marginBottom: '24px', lineHeight: '1.5' }}>
              Extension bổ trợ chặn các trang web gây xao nhãng tự động khi đang bật Pomodoro trên Notch app.
            </p>
            <a href="/help" className="portal-button-ghost" style={{ width: '100%', height: '50px', display: 'flex', alignItems: 'center', justifyContent: 'center', textDecoration: 'none', border: '1px solid var(--border)', borderRadius: '12px', fontWeight: 600 }}>
              Xem hướng dẫn cài đặt
            </a>
          </div>
        </div>

        {/* Installation Instruction Section */}
        <section className="portal-card" style={{ background: 'rgba(255,255,255,0.01)', border: '1px solid var(--border)', padding: '40px', borderRadius: '24px', maxWidth: '1000px', width: '100%', margin: '48px auto 0' }}>
          <h3 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '8px', margin: '0 0 20px 0' }}>
            <ShieldAlert size={20} style={{ color: 'var(--warm)' }} />
            Lưu ý bảo mật Gatekeeper
          </h3>
          <p style={{ color: 'var(--muted)', fontSize: '0.95rem', lineHeight: 1.6, margin: 0 }}>
            Do Notch truy cập hệ thống để tương tác với menu bar và media, nếu hệ thống hiển thị cảnh báo từ nhà phát triển không xác định:
            <br />
            1. Mở <strong>System Settings</strong> &gt; <strong>Privacy & Security</strong>.
            <br />
            2. Cuộn xuống phần Security, chọn <strong>Open Anyway</strong> để cấp quyền khởi chạy ứng dụng.
          </p>
        </section>
      </main>
    </PageShell>
  )
}
