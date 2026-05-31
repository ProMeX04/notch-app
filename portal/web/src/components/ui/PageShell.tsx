import { Link } from '@tanstack/react-router'

import { usePortalAuth } from '@/auth/usePortalAuth'

export function PageShell({ children }: Readonly<{ children: React.ReactNode }>) {
  const { status, isAuthenticated, signOut } = usePortalAuth()

  return (
    <main className="portal-page">
      <header className="portal-nav">
        <Link to="/" className="portal-logo" aria-label="Notch Portal home">
          Notch
        </Link>
        <nav className="portal-nav-links" aria-label="Primary navigation">
          <Link to="/leaderboard">Leaderboard</Link>
          <Link to="/upgrade">Upgrade</Link>
          {isAuthenticated ? <Link to="/account">Account</Link> : <Link to="/login">Login</Link>}
          {isAuthenticated ? (
            <button type="button" className="portal-link-button" onClick={() => void signOut()}>
              Logout
            </button>
          ) : null}
        </nav>
        <span className="portal-auth-status">{status}</span>
      </header>
      <section className="portal-shell">{children}</section>
    </main>
  )
}
