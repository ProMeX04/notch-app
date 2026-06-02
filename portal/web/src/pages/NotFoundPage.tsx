import { Link, useLocation } from '@tanstack/react-router'
import { PageShell } from '@/components/ui/PageShell'
import { Home, ArrowLeft, Compass, HelpCircle } from 'lucide-react'

export function NotFoundPage() {
  const location = useLocation()

  return (
    <PageShell>
      <style>{`
        body {
          background-color: #f9f9ff !important;
          color: #141b2b !important;
        }
        .glass-panel {
          background-color: rgba(255, 255, 255, 0.8) !important;
          backdrop-filter: blur(20px) !important;
          -webkit-backdrop-filter: blur(20px) !important;
          border: 1px solid rgba(0, 0, 0, 0.06) !important;
          box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.04) !important;
          transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1) !important;
        }
        .glass-panel:hover {
          border-color: rgba(0, 0, 0, 0.1) !important;
          transform: translateY(-2px) !important;
          box-shadow: 0 12px 40px 0 rgba(0, 0, 0, 0.06) !important;
        }
        .ambient-bg {
          background: radial-gradient(circle at 50% -20%, rgba(26, 86, 219, 0.05) 0%, transparent 70%);
        }
        @keyframes float-soft {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-6px); }
        }
        @keyframes spin-slow {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        @keyframes pulse-ring {
          0% { transform: scale(0.9); opacity: 0.3; }
          100% { transform: scale(1.3); opacity: 0; }
        }
      `}</style>

      <div 
        className="ambient-bg"
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '65vh',
          padding: '2rem 1rem',
          position: 'relative',
        }}
      >
        {/* Decorative background glow blob */}
        <div 
          style={{
            position: 'absolute',
            width: '350px',
            height: '350px',
            background: 'radial-gradient(circle, rgba(26, 86, 219, 0.06) 0%, rgba(26, 86, 219, 0) 70%)',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            zIndex: 0,
            pointerEvents: 'none',
          }}
        />

        <div 
          className="glass-panel"
          style={{
            maxWidth: '560px',
            width: '100%',
            padding: '40px',
            borderRadius: '24px',
            textAlign: 'center',
            position: 'relative',
            zIndex: 1,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: '28px',
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
            }}
          >
            {/* Outer animated rings */}
            <div 
              style={{ 
                position: 'absolute',
                inset: '-12px',
                borderRadius: '50%',
                border: '2px solid #003fb1',
                opacity: 0.1,
                animation: 'pulse-ring 3s infinite ease-out'
              }} 
            />
            <div 
              style={{ 
                position: 'absolute',
                inset: '-2px',
                borderRadius: '50%',
                border: '2px solid #1a56db',
                opacity: 0.05,
                animation: 'pulse-ring 3s infinite ease-out 0.8s'
              }} 
            />
            
            <div 
              style={{
                width: '64px',
                height: '64px',
                background: 'linear-gradient(135deg, #e9edff 0%, #dce2f7 100%)',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#003fb1',
                border: '1px solid rgba(0, 63, 177, 0.1)',
                boxShadow: '0 8px 24px rgba(0, 63, 177, 0.08)',
                animation: 'float-soft 4s ease-in-out infinite',
              }}
            >
              <Compass size={32} style={{ animation: 'spin-slow 25s linear infinite' }} />
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
            <p 
              style={{ 
                margin: 0,
                fontSize: '0.85rem',
                fontWeight: 800,
                letterSpacing: '0.15em',
                textTransform: 'uppercase',
                background: 'linear-gradient(135deg, #003fb1 0%, #1a56db 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
              }}
            >
              404 - Không tìm thấy trang
            </p>
            <h1 
              style={{ 
                fontSize: 'clamp(2rem, 5vw, 2.5rem)', 
                margin: 0, 
                fontWeight: 850,
                lineHeight: 1.15,
                color: '#141b2b',
                letterSpacing: '-0.04em',
              }}
            >
              Bạn đang đi lạc?
            </h1>
            <p style={{ margin: '8px 0 0', fontSize: '0.95rem', color: '#434654', lineHeight: 1.6 }}>
              Trang bạn đang tìm kiếm (<code style={{ color: '#003fb1', background: 'rgba(0, 63, 177, 0.05)', border: '1px solid rgba(0, 63, 177, 0.1)', padding: '3px 8px', borderRadius: '6px', fontSize: '0.85em', fontFamily: 'monospace' }}>{location.pathname}</code>) không tồn tại hoặc đã được chuyển sang một địa chỉ mới.
            </p>
          </div>

          {/* Action buttons */}
          <div 
            style={{ 
              display: 'flex', 
              gap: '12px', 
              width: '100%', 
              flexDirection: 'column',
            }}
          >
            <Link 
              to="/" 
              style={{ 
                textDecoration: 'none', 
                margin: 0, 
                width: '100%',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                minHeight: '3rem',
                padding: '0 2rem',
                borderRadius: '999px',
                background: '#003fb1',
                color: '#ffffff',
                fontWeight: 700,
                fontSize: '0.95rem',
                boxShadow: 'rgba(0, 63, 177, 0.15) 0px 4px 12px 0px',
                border: 'none',
                transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                cursor: 'pointer',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.transform = 'translateY(-2px)'
                e.currentTarget.style.boxShadow = 'rgba(0, 63, 177, 0.25) 0px 8px 20px 0px'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = 'translateY(0)'
                e.currentTarget.style.boxShadow = 'rgba(0, 63, 177, 0.15) 0px 4px 12px 0px'
              }}
            >
              <Home size={18} style={{ marginRight: '8px' }} />
              Quay lại Trang chủ
            </Link>
            
            <button 
              type="button"
              onClick={() => window.history.back()} 
              style={{ 
                width: '100%',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                minHeight: '3rem',
                padding: '0 2rem',
                borderRadius: '999px',
                background: 'rgba(0, 0, 0, 0.02)',
                border: '1px solid rgba(0, 0, 0, 0.08)',
                color: '#141b2b',
                fontWeight: 600,
                fontSize: '0.95rem',
                transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                cursor: 'pointer',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.transform = 'translateY(-2px)'
                e.currentTarget.style.background = 'rgba(0, 0, 0, 0.04)'
                e.currentTarget.style.borderColor = 'rgba(0, 0, 0, 0.12)'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = 'translateY(0)'
                e.currentTarget.style.background = 'rgba(0, 0, 0, 0.02)'
                e.currentTarget.style.borderColor = 'rgba(0, 0, 0, 0.08)'
              }}
            >
              <ArrowLeft size={18} style={{ marginRight: '8px' }} />
              Quay lại trang trước
            </button>
          </div>

          {/* Quick links footer */}
          <div 
            style={{ 
              width: '100%', 
              borderTop: '1px solid rgba(0, 0, 0, 0.06)', 
              paddingTop: '24px',
              textAlign: 'left'
            }}
          >
            <p style={{ fontSize: '0.85rem', fontWeight: 700, color: '#141b2b', margin: '0 0 14px' }}>
              Một số liên kết hữu ích:
            </p>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px' }}>
              <Link 
                to="/" 
                hash="features"
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  fontSize: '0.88rem', 
                  color: '#434654',
                  padding: '8px 12px',
                  borderRadius: '12px',
                  background: 'rgba(0, 0, 0, 0.01)',
                  border: '1px solid rgba(0, 0, 0, 0.04)',
                  fontWeight: 500,
                  transition: 'all 0.2s ease',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = 'rgba(0, 63, 177, 0.03)'
                  e.currentTarget.style.borderColor = 'rgba(0, 63, 177, 0.1)'
                  e.currentTarget.style.color = '#003fb1'
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = 'rgba(0, 0, 0, 0.01)'
                  e.currentTarget.style.borderColor = 'rgba(0, 0, 0, 0.04)'
                  e.currentTarget.style.color = '#434654'
                }}
              >
                <span style={{ display: 'inline-block', width: '6px', height: '6px', borderRadius: '50%', backgroundColor: '#003fb1' }} />
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
                  color: '#434654',
                  padding: '8px 12px',
                  borderRadius: '12px',
                  background: 'rgba(0, 0, 0, 0.01)',
                  border: '1px solid rgba(0, 0, 0, 0.04)',
                  fontWeight: 500,
                  transition: 'all 0.2s ease',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = 'rgba(99, 102, 241, 0.03)'
                  e.currentTarget.style.borderColor = 'rgba(99, 102, 241, 0.1)'
                  e.currentTarget.style.color = '#6366f1'
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = 'rgba(0, 0, 0, 0.01)'
                  e.currentTarget.style.borderColor = 'rgba(0, 0, 0, 0.04)'
                  e.currentTarget.style.color = '#434654'
                }}
              >
                <span style={{ display: 'inline-block', width: '6px', height: '6px', borderRadius: '50%', backgroundColor: '#6366f1' }} />
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
                  color: '#434654',
                  padding: '8px 12px',
                  borderRadius: '12px',
                  background: 'rgba(0, 0, 0, 0.01)',
                  border: '1px solid rgba(0, 0, 0, 0.04)',
                  fontWeight: 500,
                  transition: 'all 0.2s ease',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = 'rgba(168, 85, 247, 0.03)'
                  e.currentTarget.style.borderColor = 'rgba(168, 85, 247, 0.1)'
                  e.currentTarget.style.color = '#a855f7'
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = 'rgba(0, 0, 0, 0.01)'
                  e.currentTarget.style.borderColor = 'rgba(0, 0, 0, 0.04)'
                  e.currentTarget.style.color = '#434654'
                }}
              >
                <span style={{ display: 'inline-block', width: '6px', height: '6px', borderRadius: '50%', backgroundColor: '#a855f7' }} />
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
                  color: '#434654',
                  padding: '8px 12px',
                  borderRadius: '12px',
                  background: 'rgba(0, 0, 0, 0.01)',
                  border: '1px solid rgba(0, 0, 0, 0.04)',
                  fontWeight: 500,
                  transition: 'all 0.2s ease',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = 'rgba(249, 115, 22, 0.03)'
                  e.currentTarget.style.borderColor = 'rgba(249, 115, 22, 0.1)'
                  e.currentTarget.style.color = '#f97316'
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = 'rgba(0, 0, 0, 0.01)'
                  e.currentTarget.style.borderColor = 'rgba(0, 0, 0, 0.04)'
                  e.currentTarget.style.color = '#434654'
                }}
              >
                <HelpCircle size={14} style={{ color: '#f97316' }} />
                Trợ giúp
              </Link>
            </div>
          </div>
        </div>
      </div>
    </PageShell>
  )
}


