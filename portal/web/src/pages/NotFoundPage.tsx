import { Link, useLocation } from '@tanstack/react-router'
import { PageShell } from '@/components/ui/PageShell'
import { Home, ArrowLeft, Compass, HelpCircle } from 'lucide-react'

export function NotFoundPage() {
  const location = useLocation()

  return (
    <PageShell>
      <div 
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: '2rem 1rem',
          position: 'relative',
        }}
      >
        {/* Decorative background glow blob */}
        <div 
          style={{
            position: 'absolute',
            width: '320px',
            height: '320px',
            background: 'radial-gradient(circle, rgba(99, 102, 241, 0.12) 0%, rgba(99, 102, 241, 0) 70%)',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            zIndex: 0,
            pointerEvents: 'none',
          }}
        />

        <div 
          className="portal-card"
          style={{
            maxWidth: '560px',
            width: '100%',
            textAlign: 'center',
            position: 'relative',
            zIndex: 1,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: '24px',
            animation: 'portalRise 0.6s cubic-bezier(0.16, 1, 0.3, 1) both',
          }}
        >
          {/* Animated Compass Icon Container */}
          <div 
            style={{
              position: 'relative',
              width: '96px',
              height: '96px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginBottom: '4px',
            }}
          >
            {/* Outer animated rings */}
            <div 
              className="success-ring-outer" 
              style={{ 
                borderColor: 'var(--primary)',
                animation: 'ringPulse 3s infinite ease-out'
              }} 
            />
            <div 
              className="success-ring-inner" 
              style={{ 
                borderColor: 'var(--accent)',
                animation: 'ringPulse 3s infinite ease-out 0.8s'
              }} 
            />
            
            <div 
              style={{
                width: '64px',
                height: '64px',
                background: 'linear-gradient(135deg, var(--accent) 0%, var(--primary) 100%)',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#030712',
                boxShadow: 'var(--shadow-glow)',
                animation: 'portalFloat 4s ease-in-out infinite',
              }}
            >
              <Compass size={32} style={{ animation: 'portalSpin 25s linear infinite' }} />
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
            <p className="portal-kicker" style={{ margin: 0 }}>404 - Không tìm thấy trang</p>
            <h1 
              style={{ 
                fontSize: 'clamp(2rem, 5vw, 2.75rem)', 
                margin: 0, 
                lineHeight: 1.15,
                background: 'linear-gradient(135deg, #ffffff 40%, var(--accent) 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
              }}
            >
              Bạn đang đi lạc?
            </h1>
            <p style={{ margin: '12px 0 0', fontSize: '0.95rem', color: 'var(--muted)', lineHeight: 1.6 }}>
              Trang bạn đang tìm kiếm (<code style={{ color: 'var(--accent)', background: 'rgba(255,255,255,0.06)', padding: '3px 8px', borderRadius: '6px', fontSize: '0.85em', fontFamily: 'monospace' }}>{location.pathname}</code>) không tồn tại hoặc đã được chuyển sang một địa chỉ mới.
            </p>
          </div>

          {/* Action buttons */}
          <div 
            style={{ 
              display: 'flex', 
              gap: '12px', 
              width: '100%', 
              flexDirection: 'column',
              marginTop: '4px',
            }}
          >
            <Link 
              to="/" 
              className="portal-button-primary-large"
              style={{ textDecoration: 'none', margin: 0, width: '100%' }}
            >
              <Home size={18} />
              Quay lại Trang chủ
            </Link>
            
            <button 
              type="button"
              onClick={() => window.history.back()} 
              className="portal-button-glass"
              style={{ width: '100%' }}
            >
              <ArrowLeft size={18} />
              Quay lại trang trước
            </button>
          </div>

          {/* Quick links footer */}
          <div 
            style={{ 
              width: '100%', 
              borderTop: '1px solid var(--border)', 
              paddingTop: '20px',
              marginTop: '8px',
              textAlign: 'left'
            }}
          >
            <p style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--muted-strong)', margin: '0 0 12px' }}>
              Một số liên kết hữu ích:
            </p>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
              <Link 
                to="/" 
                hash="features"
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  fontSize: '0.88rem', 
                  color: 'var(--muted)',
                  padding: '6px 10px',
                  borderRadius: 'var(--radius-sm)',
                  background: 'rgba(255, 255, 255, 0.01)',
                  border: '1px solid var(--border)',
                }}
              >
                <span style={{ display: 'inline-block', width: '6px', height: '6px', borderRadius: '50%', backgroundColor: 'var(--accent)' }} />
                Tính năng
              </Link>
              <Link 
                to="/" 
                hash="leaderboard"
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  fontSize: '0.88rem', 
                  color: 'var(--muted)',
                  padding: '6px 10px',
                  borderRadius: 'var(--radius-sm)',
                  background: 'rgba(255, 255, 255, 0.01)',
                  border: '1px solid var(--border)',
                }}
              >
                <span style={{ display: 'inline-block', width: '6px', height: '6px', borderRadius: '50%', backgroundColor: 'var(--primary)' }} />
                Xếp hạng
              </Link>
              <Link 
                to="/" 
                hash="download"
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  fontSize: '0.88rem', 
                  color: 'var(--muted)',
                  padding: '6px 10px',
                  borderRadius: 'var(--radius-sm)',
                  background: 'rgba(255, 255, 255, 0.01)',
                  border: '1px solid var(--border)',
                }}
              >
                <span style={{ display: 'inline-block', width: '6px', height: '6px', borderRadius: '50%', backgroundColor: 'var(--purple)' }} />
                Tải xuống
              </Link>
              <Link 
                to="/" 
                hash="help"
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  fontSize: '0.88rem', 
                  color: 'var(--muted)',
                  padding: '6px 10px',
                  borderRadius: 'var(--radius-sm)',
                  background: 'rgba(255, 255, 255, 0.01)',
                  border: '1px solid var(--border)',
                }}
              >
                <HelpCircle size={14} style={{ color: 'var(--warm)' }} />
                Trung tâm hỗ trợ
              </Link>
            </div>
          </div>
        </div>
      </div>
    </PageShell>
  )
}

