import { Link } from '@tanstack/react-router'
import { PageShell } from '@/components/ui/PageShell'

export function NotFoundPage() {
  return (
    <PageShell>
      <style>{`
        body {
          background-color: #f9f9ff !important;
          color: #141b2b !important;
        }
      `}</style>

      <div 
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '60vh',
          padding: '2rem 1rem',
          textAlign: 'center',
          maxWidth: '440px',
          width: '100%',
          margin: '0 auto',
          gap: '24px',
          animation: 'portalRise 0.6s cubic-bezier(0.16, 1, 0.3, 1) both',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <h1 
            style={{ 
              fontSize: '5.5rem', 
              margin: 0, 
              fontWeight: 900,
              lineHeight: 1,
              background: 'linear-gradient(135deg, #003fb1 0%, #1a56db 100%)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              letterSpacing: '-0.05em',
            }}
          >
            404
          </h1>
          <h2 
            style={{ 
              fontSize: '1.35rem', 
              margin: 0, 
              fontWeight: 800,
              color: '#141b2b',
              letterSpacing: '-0.03em',
            }}
          >
            Không tìm thấy trang
          </h2>
          <p style={{ margin: '8px 0 0', fontSize: '0.92rem', color: '#434654', lineHeight: 1.55 }}>
            Trang bạn đang tìm kiếm không tồn tại hoặc đã được di chuyển sang địa chỉ khác.
          </p>
        </div>

        <Link 
          to="/" 
          style={{ 
            textDecoration: 'none', 
            margin: '8px 0 0', 
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
            fontSize: '0.92rem',
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
          Quay lại Trang chủ
        </Link>
      </div>
    </PageShell>
  )
}




