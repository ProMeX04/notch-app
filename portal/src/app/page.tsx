'use client';

import { Suspense, useEffect, useState } from 'react';
import Link from 'next/link';
import {
  BrainCircuit,
  Clock3,
  FolderKanban,
  Music,
  Sparkles,
  ChevronRight,
  Loader2
} from 'lucide-react';
import { usePortalAuth } from '@/components/portal/PortalAuthProvider';
import { apiClient } from '@/lib/api-client';
import { Navbar } from '@/components/portal/Navbar';

type PortalCapability = {
  key: string;
  name: string;
  description: string;
  isProOnly: boolean;
  isEnabled: boolean;
};

function HomeContent() {
  const { isAuthenticated } = usePortalAuth();
  const [capabilities, setCapabilities] = useState<PortalCapability[]>([]);

  useEffect(() => {
    apiClient.get<PortalCapability[]>("/api/capabilities")
      .then(res => setCapabilities(Array.isArray(res.data) ? res.data : []))
      .catch(() => {});
  }, []);

  const primaryHref = isAuthenticated ? '/account' : '/api/auth/google';
  const freeFeatures = capabilities.filter(c => !c.isProOnly);
  const proFeatures = capabilities.filter(c => c.isProOnly);

  return (
    <main className="landing-page" style={{ background: 'var(--background)', color: 'var(--foreground)', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <Navbar />

      <div className="portal-shell" style={{ flex: 1 }}>
          {/* Cinematic Hero Section */}
          <section className="landing-hero" style={{ 
            paddingTop: '200px', 
            paddingBottom: '120px',
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
                border: '1px solid var(--border-strong)',
                backdropFilter: 'blur(10px)'
              }}>
                <Sparkles size={14} />
                Trải nghiệm macOS không giới hạn
              </span>
              <h1 style={{ 
                fontSize: 'clamp(4rem, 12vw, 8rem)', 
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
          <section id="tinh-nang" className="portal-section" style={{ paddingTop: '80px', paddingBottom: '120px' }}>
            <div className="portal-section-head animate-slide-up" style={{ textAlign: 'center', margin: '0 auto 80px' }}>
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
                    <div style={{ height: '120px', background: 'var(--surface-soft)', borderRadius: '16px', border: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                       <p style={{color: 'var(--muted)', fontSize: '0.9rem', display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}>Kéo thả tệp tin vào đây</p>
                    </div>
                  </div>
                </div>
              </article>

              {/* Tall Feature */}
              <article className="bento-item bento-tall animate-slide-up delay-100">
                <div className="glow-effect" />
                <div style={{ position: 'relative', zIndex: 1, display: 'flex', flexDirection: 'column', height: '100%' }}>
                  <div style={{ color: 'var(--purple)', marginBottom: '24px' }}>
                    <Clock3 size={48} strokeWidth={1.5} />
                  </div>
                  <h3 style={{ fontSize: '2rem', fontWeight: 800, marginBottom: '16px' }}>Pomodoro Tối Giản</h3>
                  <p style={{ color: 'var(--muted)', fontSize: '1.1rem' }}>
                    Kiểm soát thời gian làm việc và nghỉ ngơi ngay trên thanh menu. Không còn mở app ngoài, duy trì trạng thái luồng (flow state).
                  </p>
                  <div style={{ marginTop: 'auto', paddingTop: '32px', display: 'flex', justifyContent: 'center' }}>
                     <div style={{ width: '140px', height: '140px', borderRadius: '50%', border: '12px solid var(--border-strong)', borderTopColor: 'var(--purple)', borderRightColor: 'var(--purple)', transform: 'rotate(45deg)' }} />
                  </div>
                </div>
              </article>

              {/* Normal Feature */}
              <article className="bento-item animate-slide-up delay-200">
                <div className="glow-effect" />
                <div style={{ position: 'relative', zIndex: 1 }}>
                  <div style={{ color: 'var(--green)', marginBottom: '24px' }}>
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
                  <div style={{ color: 'var(--warm)', marginBottom: '24px' }}>
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
          <section id="pricing" className="portal-section" style={{ padding: '120px 0' }}>
            <div className="portal-section-head animate-slide-up" style={{ textAlign: 'center', margin: '0 auto 80px' }}>
              <h2 style={{ fontSize: 'clamp(2.5rem, 5vw, 4rem)', fontWeight: 800 }}>Đầu tư một lần.</h2>
              <p style={{ fontSize: '1.2rem', color: 'var(--muted)', marginTop: '16px' }}>Đơn giản, minh bạch, không phí ẩn.</p>
            </div>

            <div className="portal-pricing-grid" style={{ 
              display: 'grid', 
              gridTemplateColumns: 'repeat(auto-fit, minmax(340px, 1fr))', 
              gap: '32px',
              maxWidth: '1000px',
              margin: '0 auto',
              alignItems: 'center'
            }}>
              {/* Free Plan */}
              <div className="portal-pricing-card animate-slide-up" style={{ 
                padding: '48px', 
                borderRadius: '40px', 
                background: 'var(--card)',
                border: '1px solid var(--border)',
                display: 'flex',
                flexDirection: 'column'
              }}>
                <h3 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '16px', color: 'var(--muted-strong)' }}>Miễn phí</h3>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: '8px', marginBottom: '24px' }}>
                  <span style={{ fontSize: '3.5rem', fontWeight: 900 }}>0</span>
                  <span style={{ color: 'var(--muted)', fontWeight: 700 }}>VND</span>
                </div>
                <p style={{ color: 'var(--muted)', marginBottom: '32px' }}>Trải nghiệm Notch cơ bản</p>
                <div style={{ height: '1px', background: 'var(--border)', margin: '0 0 32px 0' }} />
                <ul style={{ listStyle: 'none', display: 'grid', gap: '16px', marginBottom: '40px', flex: 1 }}>
                  {freeFeatures.length > 0 ? freeFeatures.map(f => (
                    <li key={f.key} style={{ display: 'flex', gap: '12px', alignItems: 'center', color: 'var(--muted-strong)' }}>
                      <ChevronRight size={18} style={{ color: 'var(--green)' }} /> {f.name}
                    </li>
                  )) : (
                    <li style={{ display: 'flex', gap: '12px', alignItems: 'center', color: 'var(--muted-strong)' }}>
                      <ChevronRight size={18} style={{ color: 'var(--green)' }} /> Kéo thả files vào shelf
                    </li>
                  )}
                </ul>
                <a href={primaryHref} className="portal-button-ghost" style={{ width: '100%', height: '56px', borderRadius: '16px', border: '1px solid var(--border-strong)', display: 'flex', alignItems: 'center', justifyContent: 'center', textDecoration: 'none' }}>
                  Bắt đầu ngay
                </a>
              </div>

              {/* Pro Plan */}
              <div className="portal-pricing-card featured animate-slide-up delay-100" style={{ 
                padding: '64px 48px', 
                borderRadius: '40px', 
                background: 'linear-gradient(180deg, rgba(255,255,255,0.05) 0%, transparent 100%)',
                color: 'white',
                position: 'relative',
                display: 'flex',
                flexDirection: 'column',
                boxShadow: '0 40px 80px -20px rgba(0,0,0, 0.8)',
                border: '1px solid rgba(255,255,255,0.1)'
              }}>
                <div style={{ 
                  position: 'absolute', 
                  top: '0', 
                  left: '0', 
                  right: '0', 
                  height: '1px', 
                  background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.5), transparent)' 
                }} />
                <div style={{ 
                  position: 'absolute', 
                  top: '24px', 
                  right: '24px', 
                  background: 'var(--foreground)', 
                  color: 'var(--background)', 
                  padding: '8px 16px', 
                  borderRadius: '999px',
                  fontSize: '0.8rem',
                  fontWeight: 800,
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em'
                }}>Phổ biến nhất</div>
                <h3 style={{ fontSize: '1.75rem', fontWeight: 800, marginBottom: '16px' }}>Notch Pro</h3>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: '8px', marginBottom: '24px' }}>
                  <span style={{ fontSize: '4rem', fontWeight: 900, lineHeight: 1 }}>99<span style={{ fontSize: '3rem' }}>.000</span></span>
                  <span style={{ opacity: 0.6, fontWeight: 700 }}>VND</span>
                </div>
                <p style={{ opacity: 0.8, marginBottom: '32px', fontSize: '1.1rem' }}>Toàn bộ quyền lực trong tay bạn</p>
                <div style={{ height: '1px', background: 'rgba(255,255,255,0.1)', margin: '0 0 32px 0' }} />
                <ul style={{ listStyle: 'none', display: 'grid', gap: '16px', marginBottom: '40px', flex: 1 }}>
                  <li style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem' }}>
                    <ChevronRight size={20} style={{ color: 'var(--green)' }} /> <strong>Mọi tính năng gói Free</strong>
                  </li>
                  {proFeatures.length > 0 ? proFeatures.map(f => (
                    <li key={f.key} style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem', opacity: 0.9 }}>
                      <ChevronRight size={20} style={{ color: 'var(--green)' }} /> {f.name}
                    </li>
                  )) : (
                    <>
                      <li style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem', opacity: 0.9 }}>
                        <ChevronRight size={20} style={{ color: 'var(--green)' }} /> Đồng bộ không giới hạn thiết bị
                      </li>
                      <li style={{ display: 'flex', gap: '12px', alignItems: 'center', fontSize: '1.05rem', opacity: 0.9 }}>
                        <ChevronRight size={20} style={{ color: 'var(--green)' }} /> Tích hợp Gemini Live AI
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

          {/* CTA Section */}
          <section className="portal-section" style={{ paddingBottom: '160px' }}>
            <div className="animate-slide-up" style={{ 
              background: 'var(--card)', 
              border: '1px solid var(--border)',
              padding: '100px 48px', 
              borderRadius: '48px', 
              textAlign: 'center',
              position: 'relative',
              overflow: 'hidden'
            }}>
               <div style={{
                position: 'absolute',
                top: '0',
                left: '50%',
                transform: 'translateX(-50%)',
                width: '600px',
                height: '600px',
                background: 'radial-gradient(circle, rgba(255,255,255,0.05) 0%, transparent 60%)',
                pointerEvents: 'none',
                zIndex: 0
              }} />
              <div style={{ position: 'relative', zIndex: 1 }}>
                <h2 style={{ fontSize: 'clamp(2.5rem, 6vw, 4.5rem)', fontWeight: 900, marginBottom: '24px', letterSpacing: '-0.05em' }}>Sẵn sàng thay đổi?</h2>
                <p style={{ fontSize: '1.25rem', opacity: 0.7, maxWidth: '600px', margin: '0 auto 48px', lineHeight: 1.6 }}>
                  Nâng tầm hiệu suất công việc của bạn với Notch ngay hôm nay.
                </p>
                <div style={{ display: 'flex', gap: '16px', justifyContent: 'center' }}>
                  <a href={primaryHref} className="portal-button" style={{ background: 'white', color: 'black', height: '64px', padding: '0 40px', fontSize: '1.1rem', borderRadius: '999px', fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', textDecoration: 'none' }}>
                    Bắt đầu miễn phí
                  </a>
                </div>
              </div>
            </div>
          </section>
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

export default function Home() {
  return (
    <Suspense fallback={
      <div style={{ display: 'flex', height: '100vh', width: '100vw', alignItems: 'center', justifyContent: 'center', background: '#000', color: '#fff' }}>
        <Loader2 className="animate-spin" size={24} />
      </div>
    }>
      <HomeContent />
    </Suspense>
  );
}
