import { useEffect, useState } from 'react'
import {
  BrainCircuit,
  Clock3,
  FolderKanban,
  Music,
  Sparkles,
  ChevronRight,
} from 'lucide-react'

import { PageShell } from '@/components/ui/PageShell'
import { usePortalAuth } from '@/auth/usePortalAuth'
import { apiClient } from '@/api/client'

type PortalCapability = {
  key: string
  name: string
  description: string
  isProOnly: boolean
  isEnabled: boolean
}

const defaultCapabilities: PortalCapability[] = [
  { key: 'talk_connection', name: 'Gemini Live', description: 'Trò chuyện với AI trực tiếp từ Notch', isProOnly: true, isEnabled: true },
  { key: 'focus_pomodoro', name: 'Focus Pomodoro', description: 'Hỗ trợ tập trung và quản lý phiên làm việc', isProOnly: false, isEnabled: true },
  { key: 'focus_website_blocklist', name: 'Chặn website', description: 'Chặn trang web gây xao nhãng', isProOnly: false, isEnabled: true },
  { key: 'media_controls', name: 'Điều khiển nhạc', description: 'Điều khiển nhạc trên Notch', isProOnly: false, isEnabled: true },
  { key: 'browser_bridge', name: 'Kết nối trình duyệt', description: 'Kết nối ứng dụng với trình duyệt', isProOnly: false, isEnabled: true },
  { key: 'panel_shelf', name: 'Shelf', description: 'Lưu tạm file, văn bản và đường dẫn trong Notch', isProOnly: true, isEnabled: true }
]

export function HomePage() {
  const { isAuthenticated } = usePortalAuth()
  const [capabilities, setCapabilities] = useState<PortalCapability[]>(defaultCapabilities)

  useEffect(() => {
    apiClient.get<{ version: number; features: Record<string, string> }>('/api/capabilities')
      .then(res => {
        const features = res.data?.features
        if (features) {
          setCapabilities(prev => prev.map(c => {
            const req = features[c.key]
            if (!req) return c
            return {
              ...c,
              isProOnly: req === 'pro',
              isEnabled: req !== 'disabled'
            }
          }))
        }
      })
      .catch(() => {})
  }, [])

  const primaryHref = isAuthenticated ? '/account' : '/api/auth/google'
  const freeFeatures = capabilities.filter(c => c.isEnabled && !c.isProOnly)
  const proFeatures = capabilities.filter(c => c.isEnabled && c.isProOnly)

  return (
    <PageShell>
      <main className="landing-page" style={{ color: 'var(--foreground)', display: 'flex', flexDirection: 'column' }}>
        {/* Cinematic Hero Section */}
        <section className="landing-hero" style={{ 
          paddingTop: '80px', 
          paddingBottom: '80px',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          textAlign: 'center',
          position: 'relative'
        }}>
          <div style={{
            position: 'absolute',
            top: '-20%',
            left: '50%',
            transform: 'translateX(-50%)',
            width: '800px',
            height: '800px',
            background: 'radial-gradient(circle, rgba(56, 189, 248, 0.15) 0%, transparent 70%)',
            pointerEvents: 'none',
            zIndex: 0
          }} />
          
          <div className="animate-slide-up" style={{ position: 'relative', zIndex: 1 }}>
            <span className="portal-badge" style={{ 
              marginBottom: '32px', 
              background: 'rgba(255,255,255,0.05)', 
              color: 'var(--muted-strong)', 
              border: '1px solid var(--border)',
              borderRadius: '999px',
              padding: '6px 14px',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '6px',
              fontSize: '0.85rem'
            }}>
              <Sparkles size={14} />
              Trải nghiệm macOS không giới hạn
            </span>
            <h1 style={{ 
              fontSize: 'clamp(3rem, 10vw, 6rem)', 
              fontWeight: 900, 
              lineHeight: 0.9, 
              letterSpacing: '-0.06em',
              marginBottom: '32px',
              background: 'linear-gradient(180deg, #FFFFFF 0%, rgba(255,255,255,0.4) 100%)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              color: 'transparent'
            }}>
              Tối thượng.<br />
              Tập trung.
            </h1>
            <p style={{ 
              fontSize: '1.25rem', 
              color: 'var(--muted)', 
              maxWidth: '640px', 
              margin: '0 auto 48px',
              lineHeight: 1.6
            }}>
              Notch là trợ lý hoàn hảo ngay trên thanh menu của bạn. Kéo thả, điều khiển media, và giữ sự tập trung cao độ mà không cần mở bất kỳ cửa sổ nào.
            </p>

            <div style={{ display: 'flex', gap: '16px', justifyContent: 'center', alignItems: 'center' }}>
              <a href={primaryHref} className="portal-button" style={{ 
                height: '60px', 
                padding: '0 40px', 
                fontSize: '1.1rem', 
                borderRadius: '999px',
                background: 'white',
                color: 'black',
                fontWeight: 600,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                textDecoration: 'none'
              }}>
                {isAuthenticated ? 'Xem tài khoản của tôi' : 'Khám phá ngay'}
              </a>
            </div>
          </div>
        </section>

        {/* Bento Box Feature Grid */}
        <section id="tinh-nang" style={{ paddingTop: '80px', paddingBottom: '120px' }}>
          <div className="animate-slide-up" style={{ textAlign: 'center', margin: '0 auto 80px' }}>
            <h2 style={{ fontSize: 'clamp(2.5rem, 5vw, 4rem)', fontWeight: 800 }}>Tính năng mạnh mẽ.<br/> Bố cục thông minh.</h2>
          </div>

          <div className="bento-grid">
            {/* Wide Feature */}
            <article className="bento-item bento-wide animate-slide-up">
              <div className="glow-effect" />
              <div style={{ position: 'relative', zIndex: 1, display: 'flex', flexDirection: 'column', height: '100%' }}>
                <div style={{ color: 'var(--accent)', marginBottom: '24px' }}>
                  <FolderKanban size={48} strokeWidth={1.5} />
                </div>
                <h3 style={{ fontSize: '2rem', fontWeight: 800, marginBottom: '16px' }}>Shelf Thông Minh</h3>
                <p style={{ color: 'var(--muted)', fontSize: '1.1rem', maxWidth: '400px' }}>
                  Kéo và thả mọi thứ vào Notch. File, URL, hình ảnh - tất cả đều được lưu trữ tạm thời mượt mà, sẵn sàng bất cứ khi nào bạn cần mà không làm rối Desktop.
                </p>
                <div style={{ marginTop: 'auto', paddingTop: '32px' }}>
                  <div style={{ height: '120px', background: 'rgba(255,255,255,0.02)', borderRadius: '16px', border: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                     <p style={{color: 'var(--muted)', fontSize: '0.9rem', display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}>Kéo thả tệp tin vào đây</p>
                  </div>
                </div>
              </div>
            </article>

            {/* Tall Feature */}
            <article className="bento-item bento-tall animate-slide-up delay-100">
              <div className="glow-effect" />
              <div style={{ position: 'relative', zIndex: 1, display: 'flex', flexDirection: 'column', height: '100%' }}>
                <div style={{ color: '#a855f7', marginBottom: '24px' }}>
                  <Clock3 size={48} strokeWidth={1.5} />
                </div>
                <h3 style={{ fontSize: '2rem', fontWeight: 800, marginBottom: '16px' }}>Pomodoro Tối Giản</h3>
                <p style={{ color: 'var(--muted)', fontSize: '1.1rem' }}>
                  Kiểm soát thời gian làm việc và nghỉ ngơi ngay trên thanh menu. Không còn mở app ngoài, duy trì trạng thái luồng (flow state).
                </p>
                <div style={{ marginTop: 'auto', paddingTop: '32px', display: 'flex', justifyContent: 'center' }}>
                   <div style={{ width: '140px', height: '140px', borderRadius: '50%', border: '12px solid rgba(255,255,255,0.05)', borderTopColor: '#a855f7', borderRightColor: '#a855f7', transform: 'rotate(45deg)' }} />
                </div>
              </div>
            </article>

            {/* Normal Feature */}
            <article className="bento-item animate-slide-up delay-200">
              <div className="glow-effect" />
              <div style={{ position: 'relative', zIndex: 1 }}>
                <div style={{ color: '#10b981', marginBottom: '24px' }}>
                  <Music size={40} strokeWidth={1.5} />
                </div>
                <h3 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '12px' }}>Media Control</h3>
                <p style={{ color: 'var(--muted)' }}>
                  Phát, tạm dừng, bỏ qua bài hát trên Spotify hay Apple Music trực tiếp từ Notch.
                </p>
              </div>
            </article>

            {/* Normal Feature */}
            <article className="bento-item animate-slide-up delay-300">
              <div className="glow-effect" />
              <div style={{ position: 'relative', zIndex: 1 }}>
                <div style={{ color: '#f59e0b', marginBottom: '24px' }}>
                  <BrainCircuit size={40} strokeWidth={1.5} />
                </div>
                <h3 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '12px' }}>Gemini AI</h3>
                <p style={{ color: 'var(--muted)' }}>
                  Trò chuyện, tóm tắt và phân tích nội dung với sức mạnh AI tích hợp sâu.
                </p>
              </div>
            </article>
          </div>
        </section>

        {/* Pricing Section Integration */}
        <section id="pricing" style={{ padding: '120px 0', borderTop: '1px solid var(--border)' }}>
          <div className="animate-slide-up" style={{ textAlign: 'center', margin: '0 auto 80px' }}>
            <h2 style={{ fontSize: 'clamp(2.5rem, 5vw, 4rem)', fontWeight: 800 }}>Đầu tư một lần.</h2>
            <p style={{ fontSize: '1.2rem', color: 'var(--muted)', marginTop: '16px' }}>Đơn giản, minh bạch, không phí ẩn.</p>
          </div>

          <div className="portal-pricing-grid">
            {/* Free Plan */}
            <div className="portal-pricing-card animate-slide-up">
              <h3 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '16px', color: 'var(--muted-strong)' }}>Miễn phí</h3>
              <div className="price">
                <span className="amount">0</span>
                <span className="currency">VND</span>
              </div>
              <p style={{ color: 'var(--muted)', marginBottom: '32px' }}>Trải nghiệm Notch cơ bản</p>
              <div style={{ height: '1px', background: 'var(--border)', margin: '0 0 32px 0' }} />
              <ul style={{ listStyle: 'none', padding: 0, margin: '0 0 40px 0', display: 'grid', gap: '16px', flex: 1 }}>
                {freeFeatures.length > 0 ? freeFeatures.map(f => (
                  <li key={f.key} style={{ display: 'flex', gap: '12px', alignItems: 'center', color: 'var(--muted-strong)' }}>
                    <ChevronRight size={18} style={{ color: '#10b981' }} /> {f.name}
                  </li>
                )) : (
                  <li style={{ display: 'flex', gap: '12px', alignItems: 'center', color: 'var(--muted-strong)' }}>
                    <ChevronRight size={18} style={{ color: '#10b981' }} /> Kéo thả files vào shelf
                  </li>
                )}
              </ul>
              <a href={primaryHref} className="portal-button" style={{ 
                width: '100%', 
                height: '56px', 
                borderRadius: '16px', 
                border: '1px solid var(--border)', 
                display: 'flex', 
                alignItems: 'center', 
                justifyContent: 'center', 
                textDecoration: 'none',
                fontWeight: 600
              }}>
                Bắt đầu ngay
              </a>
            </div>

            {/* Pro Plan */}
            <div className="portal-pricing-card featured animate-slide-up delay-100">
              <div className="badge-featured">Phổ biến nhất</div>
              <h3 style={{ fontSize: '1.75rem', fontWeight: 800, marginBottom: '16px' }}>Notch Pro</h3>
              <div className="price">
                <span className="amount">99<span style={{ fontSize: '3rem' }}>.000</span></span>
                <span className="currency">VND</span>
              </div>
              <p style={{ opacity: 0.8, marginBottom: '32px', fontSize: '1.1rem' }}>Toàn bộ quyền lực trong tay bạn</p>
              <div style={{ height: '1px', background: 'rgba(255,255,255,0.1)', margin: '0 0 32px 0' }} />
              <ul style={{ listStyle: 'none', padding: 0, margin: '0 0 40px 0', display: 'grid', gap: '16px', flex: 1 }}>
                <li style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem' }}>
                  <ChevronRight size={20} style={{ color: '#10b981' }} /> <strong>Mọi tính năng gói Free</strong>
                </li>
                {proFeatures.length > 0 ? proFeatures.map(f => (
                  <li key={f.key} style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem', opacity: 0.9 }}>
                    <ChevronRight size={20} style={{ color: '#10b981' }} /> {f.name}
                  </li>
                )) : (
                  <>
                    <li style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem', opacity: 0.9 }}>
                      <ChevronRight size={20} style={{ color: '#10b981' }} /> Đồng bộ không giới hạn thiết bị
                    </li>
                    <li style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem', opacity: 0.9 }}>
                      <ChevronRight size={20} style={{ color: '#10b981' }} /> Tích hợp Gemini Live AI
                    </li>
                  </>
                )}
              </ul>
              <a href={primaryHref} className="portal-button" style={{ 
                width: '100%', 
                height: '60px', 
                borderRadius: '16px', 
                background: 'white', 
                color: 'black',
                fontSize: '1.05rem',
                fontWeight: 600,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                textDecoration: 'none'
              }}>
                {isAuthenticated ? 'Quản lý tài khoản' : 'Đăng nhập để nâng cấp'}
              </a>
            </div>
          </div>
        </section>

        {/* Footer */}
        <footer style={{ borderTop: '1px solid var(--border)', padding: '60px 0', marginTop: '80px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ fontSize: '1.1rem', fontWeight: 800 }}>Notch App</div>
            <p style={{ color: 'var(--muted)', fontSize: '0.9rem' }}>&copy; 2026 Notch App. Built for macOS.</p>
          </div>
        </footer>
      </main>
    </PageShell>
  )
}

