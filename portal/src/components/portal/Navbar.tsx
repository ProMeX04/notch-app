'use client';

import { useEffect, useState, Suspense } from 'react';
import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';
import { LogOut, User, Menu, X } from 'lucide-react';
import { PortalLogo } from './PortalLogo';
import { usePortalAuth } from './PortalAuthProvider';

function NavbarContent() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { status, signOut, user } = usePortalAuth();
  const isAuthenticated = status === 'authenticated';
  
  const [scrolled, setScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 20);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const tab = searchParams.get('tab');
  
  const isHomeActive = pathname === '/' && (!isAuthenticated || tab === 'intro');
  const isProfileActive = pathname === '/account';
  const isLeaderboardActive = pathname === '/leaderboard';
  const isDownloadsActive = pathname === '/downloads';
  const isDocsActive = pathname === '/docs';
  const isAboutActive = pathname === '/about';
  const isHelpActive = pathname === '/help';

  const linkStyle = (isActive: boolean) => ({
    fontSize: '0.95rem',
    fontWeight: 500,
    color: isActive ? 'var(--foreground)' : 'var(--muted-strong)',
    transition: 'all 0.2s ease',
    opacity: isActive ? 1 : 0.7,
  });

  return (
    <nav className={`landing-nav ${scrolled ? 'scrolled' : ''}`} style={{ 
      position: 'fixed', 
      top: scrolled ? '12px' : '20px', 
      left: '50%', 
      transform: 'translateX(-50%)', 
      zIndex: 1000,
      width: scrolled ? 'min(1000px, calc(100% - 40px))' : 'min(1100px, calc(100% - 40px))',
      transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)'
    }}>
      <div className="glass" style={{ 
        display: 'flex', 
        flexDirection: 'column',
        padding: '12px 24px', 
        borderRadius: scrolled ? '24px' : 'var(--radius-full)',
        boxShadow: scrolled ? 'var(--shadow-lg)' : 'none',
        border: scrolled ? '1px solid var(--border-strong)' : '1px solid var(--border)',
        background: scrolled ? 'rgba(0,0,0,0.85)' : 'rgba(0,0,0,0.4)',
        backdropFilter: 'blur(20px)',
        transition: 'all 0.3s ease'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
          <PortalLogo />
          
          {/* Desktop Links */}
          <div className="nav-links" style={{ gap: '28px', alignItems: 'center' }}>
            <Link href="/?tab=intro" style={linkStyle(isHomeActive)} className="portal-text-link">Giới thiệu</Link>
            <Link href="/downloads" style={linkStyle(isDownloadsActive)} className="portal-text-link">Tải về</Link>
            <Link href="/leaderboard" style={linkStyle(isLeaderboardActive)} className="portal-text-link">Xếp hạng</Link>
            <Link href="/docs" style={linkStyle(isDocsActive)} className="portal-text-link">Tài liệu</Link>
            <Link href="/about" style={linkStyle(isAboutActive)} className="portal-text-link">Về Notch</Link>
            <Link href="/help" style={linkStyle(isHelpActive)} className="portal-text-link">Hỗ trợ</Link>
            
            {status !== 'booting' && (
              <>
                 {isAuthenticated ? (
                  <div style={{ display: 'flex', alignItems: 'center', marginLeft: '12px' }}>
                    <Link href="/account" style={{
                      ...linkStyle(isProfileActive),
                      display: 'flex',
                      alignItems: 'center',
                      gap: '8px',
                      background: isProfileActive ? 'var(--card-strong)' : 'transparent',
                      padding: user?.avatar_url ? '4px 14px 4px 6px' : '6px 14px',
                      borderRadius: '999px',
                      border: '1px solid var(--border)',
                    }}>
                      {user?.avatar_url ? (
                        <img 
                          src={user.avatar_url} 
                          alt="Avatar" 
                          referrerPolicy="no-referrer"
                          style={{
                            width: '22px',
                            height: '22px',
                            borderRadius: '50%',
                            objectFit: 'cover'
                          }}
                        />
                      ) : (
                        <User size={14} />
                      )}
                      Tài khoản
                    </Link>
                  </div>
                ) : (
                  <Link href="/login" className="portal-button" style={{ 
                    height: '38px', 
                    padding: '0 18px', 
                    fontSize: '0.85rem', 
                    background: 'white', 
                    color: 'black',
                    marginLeft: '12px'
                  }}>
                    Đăng nhập
                  </Link>
                )}
              </>
            )}
          </div>

          {/* Mobile Menu Button */}
          <button 
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            style={{ color: 'white' }}
            className="mobile-menu-btn"
          >
            {mobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
          </button>
        </div>

        {/* Mobile Links */}
        {mobileMenuOpen && (
          <div style={{ 
            display: 'flex', 
            flexDirection: 'column', 
            gap: '16px', 
            paddingTop: '20px', 
            paddingBottom: '8px',
            borderTop: '1px solid var(--border)',
            marginTop: '12px'
          }}>
            <Link href="/?tab=intro" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isHomeActive)}>Giới thiệu</Link>
            <Link href="/downloads" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isDownloadsActive)}>Tải về</Link>
            <Link href="/leaderboard" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isLeaderboardActive)}>Xếp hạng</Link>
            <Link href="/docs" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isDocsActive)}>Tài liệu</Link>
            <Link href="/about" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isAboutActive)}>Về Notch</Link>
            <Link href="/help" onClick={() => setMobileMenuOpen(false)} style={linkStyle(isHelpActive)}>Hỗ trợ</Link>
            
            {status !== 'booting' && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', paddingTop: '10px', borderTop: '1px solid var(--border)' }}>
                 {isAuthenticated ? (
                  <Link href="/account" onClick={() => setMobileMenuOpen(false)} style={{
                    ...linkStyle(isProfileActive),
                    display: 'flex',
                    alignItems: 'center',
                    gap: '10px',
                    padding: '8px 0',
                  }}>
                    {user?.avatar_url ? (
                      <img 
                        src={user.avatar_url} 
                        alt="Avatar" 
                        referrerPolicy="no-referrer"
                        style={{
                          width: '24px',
                          height: '24px',
                          borderRadius: '50%',
                          objectFit: 'cover'
                        }}
                      />
                    ) : (
                      <User size={16} />
                    )}
                    Tài khoản cá nhân
                  </Link>
                ) : (
                  <Link href="/login" onClick={() => setMobileMenuOpen(false)} className="portal-button" style={{ 
                    width: '100%', 
                    height: '42px', 
                    background: 'white', 
                    color: 'black',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center'
                  }}>
                    Đăng nhập
                  </Link>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </nav>
  );
}

export function Navbar() {
  return (
    <Suspense fallback={
      <nav className="landing-nav" style={{ position: 'fixed', top: '20px', left: '50%', transform: 'translateX(-50%)', zIndex: 1000, width: 'min(1100px, calc(100% - 40px))' }}>
        <div className="glass" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 24px', borderRadius: 'var(--radius-full)', background: 'rgba(0,0,0,0.4)', border: '1px solid var(--border)' }}>
          <PortalLogo />
        </div>
      </nav>
    }>
      <NavbarContent />
    </Suspense>
  );
}
