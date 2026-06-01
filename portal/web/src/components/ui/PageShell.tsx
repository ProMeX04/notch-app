import { useEffect, useState } from 'react'
import { Link, useLocation } from '@tanstack/react-router'
import { User, Menu, X } from 'lucide-react'

import { usePortalAuth } from '@/auth/usePortalAuth'
import { PortalLogo } from '@/components/portal/PortalLogo'

export function PageShell({
  children,
  noShell = false,
}: Readonly<{
  children: React.ReactNode
  noShell?: boolean
}>) {
  const { status, isAuthenticated, user } = usePortalAuth()
  const location = useLocation()
  const pathname = location.pathname

  const [scrolled, setScrolled] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 20)
    }
    window.addEventListener('scroll', handleScroll)
    return () => window.removeEventListener('scroll', handleScroll)
  }, [])

  const isHomeActive = pathname === '/'
  const isProfileActive = pathname === '/account'
  const isLeaderboardActive = pathname === '/leaderboard'
  const isDownloadsActive = pathname === '/downloads'
  const isHelpActive = pathname === '/help'

  const linkStyle = (isActive: boolean) => ({
    fontSize: '0.95rem',
    fontWeight: 500,
    color: isActive ? 'var(--foreground)' : 'var(--muted-strong)',
    transition: 'all 0.2s ease',
    opacity: isActive ? 1 : 0.7,
  })

  return (
    <main className="portal-page">
      <nav
        className={`landing-nav ${scrolled ? 'scrolled' : ''}`}
        style={{
          position: 'fixed',
          top: scrolled ? '12px' : '20px',
          left: '50%',
          transform: 'translateX(-50%)',
          zIndex: 1000,
          width: scrolled ? 'min(1000px, calc(100% - 40px))' : 'min(1100px, calc(100% - 40px))',
          transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
        }}
      >
        <div
          className="glass"
          style={{
            display: 'flex',
            flexDirection: 'column',
            padding: '12px 24px',
            borderRadius: scrolled ? '24px' : 'var(--radius-full)',
            boxShadow: scrolled ? 'var(--shadow-lg)' : 'none',
            border: scrolled ? '1px solid var(--border-strong)' : '1px solid var(--border)',
            background: scrolled ? 'rgba(0,0,0,0.85)' : 'rgba(0,0,0,0.4)',
            backdropFilter: 'blur(20px)',
            transition: 'all 0.3s ease',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
            <PortalLogo />

            {/* Desktop Links */}
            <div className="nav-links" style={{ gap: '28px', alignItems: 'center' }}>
              <Link to="/" style={linkStyle(isHomeActive)} className="portal-text-link">
                Giới thiệu
              </Link>
              <Link to="/downloads" style={linkStyle(isDownloadsActive)} className="portal-text-link">
                Tải về
              </Link>
              <Link to="/leaderboard" style={linkStyle(isLeaderboardActive)} className="portal-text-link">
                Xếp hạng
              </Link>
              <Link to="/help" style={linkStyle(isHelpActive)} className="portal-text-link">
                Hỗ trợ
              </Link>

              {status !== 'booting' && (
                <>
                  {isAuthenticated ? (
                    <div style={{ display: 'flex', alignItems: 'center', marginLeft: '12px' }}>
                      <Link
                        to="/account"
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          background: isProfileActive ? 'var(--card-strong)' : 'transparent',
                          width: '36px',
                          height: '36px',
                          borderRadius: '50%',
                          border: '1px solid var(--border)',
                          transition: 'all 0.2s ease',
                        }}
                        title="Tài khoản"
                      >
                        {user?.avatar_url ? (
                          <img
                            src={user.avatar_url}
                            alt="Avatar"
                            referrerPolicy="no-referrer"
                            style={{
                              width: '26px',
                              height: '26px',
                              borderRadius: '50%',
                              objectFit: 'cover',
                            }}
                          />
                        ) : (
                          <User size={16} style={{ color: 'var(--foreground)' }} />
                        )}
                      </Link>
                    </div>
                  ) : (
                    <Link
                      to="/login"
                      className="portal-button"
                      style={{
                        height: '38px',
                        padding: '0 18px',
                        fontSize: '0.85rem',
                        background: 'white',
                        color: 'black',
                        marginLeft: '12px',
                      }}
                    >
                      Đăng nhập
                    </Link>
                  )}
                </>
              )}
            </div>

            {/* Mobile Menu Button */}
            <button
              type="button"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              style={{ color: 'white', background: 'none', border: 'none', cursor: 'pointer' }}
              className="mobile-menu-btn"
            >
              {mobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
            </button>
          </div>

          {/* Mobile Links */}
          {mobileMenuOpen && (
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                gap: '16px',
                paddingTop: '20px',
                paddingBottom: '8px',
                borderTop: '1px solid var(--border)',
                marginTop: '12px',
              }}
            >
              <Link to="/" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isHomeActive)}>
                Giới thiệu
              </Link>
              <Link to="/downloads" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isDownloadsActive)}>
                Tải về
              </Link>
              <Link to="/leaderboard" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isLeaderboardActive)}>
                Xếp hạng
              </Link>
              <Link to="/help" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isHelpActive)}>
                Hỗ trợ
              </Link>

              {status !== 'booting' && (
                <div
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '10px',
                    paddingTop: '10px',
                    borderTop: '1px solid var(--border)',
                  }}
                >
                  {isAuthenticated ? (
                    <Link
                      to="/account"
                      onClick={() => setMobileMenuOpen(false)}
                      style={{
                        ...linkStyle(isProfileActive),
                        display: 'flex',
                        alignItems: 'center',
                        gap: '10px',
                        padding: '8px 0',
                      }}
                    >
                      {user?.avatar_url ? (
                        <img
                          src={user.avatar_url}
                          alt="Avatar"
                          referrerPolicy="no-referrer"
                          style={{
                            width: '24px',
                            height: '24px',
                            borderRadius: '50%',
                            objectFit: 'cover',
                          }}
                        />
                      ) : (
                        <User size={16} />
                      )}
                      Tài khoản cá nhân
                    </Link>
                  ) : (
                    <Link
                      to="/login"
                      onClick={() => setMobileMenuOpen(false)}
                      className="portal-button"
                      style={{
                        width: '100%',
                        height: '42px',
                        background: 'white',
                        color: 'black',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                      }}
                    >
                      Đăng nhập
                    </Link>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </nav>
      {noShell ? (
        children
      ) : (
        <section className="portal-shell">{children}</section>
      )}
    </main>
  )
}

