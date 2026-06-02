import { useEffect, useState } from 'react'
import { Link, useLocation } from '@tanstack/react-router'
import { User, Menu, X } from 'lucide-react'

import { usePortalAuth } from '@/auth/usePortalAuth'
import { PortalLogo } from '@/components/portal/PortalLogo'
import { setIsProgrammaticScroll } from './scrollState'

export function PageShell({
  children,
  noShell = false,
  noHeader = false,
}: Readonly<{
  children: React.ReactNode
  noShell?: boolean
  noHeader?: boolean
}>) {
  const { status, isAuthenticated, user } = usePortalAuth()
  const location = useLocation()
  const pathname = location.pathname

  const [scrolled, setScrolled] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [activeHash, setActiveHash] = useState(() => {
    return window.location.hash.replace('#', '') || 'hero'
  })

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 20)
    }
    const handleHashChange = () => {
      setActiveHash(window.location.hash.replace('#', '') || 'hero')
    }

    window.addEventListener('scroll', handleScroll)
    window.addEventListener('hashchange', handleHashChange)
    window.addEventListener('activesectionchange', handleHashChange)

    return () => {
      window.removeEventListener('scroll', handleScroll)
      window.removeEventListener('hashchange', handleHashChange)
      window.removeEventListener('activesectionchange', handleHashChange)
    }
  }, [])

  const isHomeActive = pathname === '/' && (!activeHash || activeHash === 'hero')
  const isFeaturesActive = pathname === '/' && activeHash === 'features'
  const isLeaderboardActive = pathname === '/' && activeHash === 'leaderboard'
  const isDownloadsActive = pathname === '/' && activeHash === 'download'
  const isPricingActive = pathname === '/' && activeHash === 'pricing'
  const isHelpActive = pathname === '/' && activeHash === 'help'
  const isProfileActive = pathname === '/account'

  const linkStyle = (isActive: boolean) => ({
    fontSize: '0.9rem',
    fontWeight: 600,
    color: isActive ? '#003fb1' : '#434654',
    transition: 'all 0.2s ease',
    opacity: isActive ? 1 : 0.8,
    textDecoration: 'none',
  })

  const handleNavClick = (e: React.MouseEvent<HTMLAnchorElement>, targetId: string) => {
    if (pathname === '/') {
      e.preventDefault()
      const el = document.getElementById(targetId)
      if (el) {
        setIsProgrammaticScroll(true)
        setActiveHash(targetId)
        window.history.replaceState(null, '', `#${targetId}`)
        el.scrollIntoView({ behavior: 'smooth', block: 'start' })

        const clearFlag = () => {
          setIsProgrammaticScroll(false)
          window.removeEventListener('scrollend', clearFlag)
        }
        window.addEventListener('scrollend', clearFlag)

        setTimeout(() => {
          setIsProgrammaticScroll(false)
        }, 1000)
      }
    }
  }

  const renderNavLink = (id: string, label: string, isActive: boolean, isMobile = false) => {
    const href = pathname === '/' ? `#${id}` : `/#${id}`
    return (
      <a
        href={href}
        onClick={(e) => {
          if (isMobile) {
            setMobileMenuOpen(false)
          }
          handleNavClick(e, id)
        }}
        style={linkStyle(isActive)}
        className={isMobile ? '' : 'portal-text-link'}
      >
        {label}
      </a>
    )
  }

  return (
    <main className="portal-page">
      {!noHeader && (
        <nav
          className={`landing-nav ${scrolled ? 'scrolled' : ''}`}
          style={{
            position: 'fixed',
            top: scrolled ? '16px' : '28px',
            left: '50%',
            transform: 'translateX(-50%)',
            zIndex: 1000,
            width: scrolled ? 'min(1400px, calc(100% - 40px))' : 'min(1440px, calc(100% - 40px))',
            transition: 'all 0.4s cubic-bezier(0.16, 1, 0.3, 1)',
          }}
        >
        <div
          className="glass"
          style={{
            display: 'flex',
            flexDirection: 'column',
            padding: scrolled ? '10px 24px' : '14px 28px',
            borderRadius: scrolled ? '20px' : 'var(--radius-xl)',
            boxShadow: scrolled ? '0 10px 30px rgba(0, 0, 0, 0.05)' : 'none',
            border: scrolled ? '1px solid rgba(0, 0, 0, 0.08)' : '1px solid rgba(0, 0, 0, 0.04)',
            background: scrolled ? 'rgba(255, 255, 255, 0.85)' : 'rgba(255, 255, 255, 0.6)',
            backdropFilter: 'blur(24px) saturate(180%)',
            WebkitBackdropFilter: 'blur(24px) saturate(180%)',
            transition: 'all 0.4s cubic-bezier(0.16, 1, 0.3, 1)',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
            <PortalLogo />

            {/* Desktop Links */}
            <div className="nav-links" style={{ display: 'flex', gap: '28px', alignItems: 'center' }}>
              {renderNavLink('hero', 'Giới thiệu', isHomeActive)}
              {renderNavLink('features', 'Tính năng', isFeaturesActive)}
              {renderNavLink('leaderboard', 'Xếp hạng', isLeaderboardActive)}
              {renderNavLink('download', 'Tải xuống', isDownloadsActive)}
              {renderNavLink('pricing', 'Mức giá', isPricingActive)}
              {renderNavLink('help', 'Hỗ trợ', isHelpActive)}

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
                          background: isProfileActive ? '#e9edff' : 'transparent',
                          width: '36px',
                          height: '36px',
                          borderRadius: '50%',
                          border: isProfileActive ? '1px solid rgba(0, 63, 177, 0.2)' : '1px solid rgba(0, 0, 0, 0.1)',
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
                          <User size={16} style={{ color: '#434654' }} />
                        )}
                      </Link>
                    </div>
                  ) : (
                    <a
                      href="/api/auth/google"
                      className="portal-button"
                      style={{
                        height: '38px',
                        padding: '0 18px',
                        fontSize: '0.85rem',
                        background: '#003fb1',
                        color: 'white',
                        marginLeft: '12px',
                        fontWeight: 600,
                        borderRadius: '999px',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        boxShadow: 'rgba(0, 63, 177, 0.15) 0px 4px 12px 0px',
                        border: 'none',
                        textDecoration: 'none',
                      }}
                    >
                      Đăng nhập
                    </a>
                  )}
                </>
              )}
            </div>

            {/* Mobile Menu Button */}
            <button
              type="button"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              style={{ color: '#434654', background: 'none', border: 'none', cursor: 'pointer' }}
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
              {renderNavLink('hero', 'Giới thiệu', isHomeActive, true)}
              {renderNavLink('features', 'Tính năng', isFeaturesActive, true)}
              {renderNavLink('leaderboard', 'Xếp hạng', isLeaderboardActive, true)}
              {renderNavLink('download', 'Tải xuống', isDownloadsActive, true)}
              {renderNavLink('pricing', 'Mức giá', isPricingActive, true)}
              {renderNavLink('help', 'Hỗ trợ', isHelpActive, true)}

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
                    <a
                      href="/api/auth/google"
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
                        textDecoration: 'none',
                      }}
                    >
                      Đăng nhập
                    </a>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </nav>
      )}
      {noShell ? (
        children
      ) : (
        <section className="portal-shell">{children}</section>
      )}
    </main>
  )
}

