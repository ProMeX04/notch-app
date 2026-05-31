import { PageShell } from '@/components/ui/PageShell'
import { usePortalAuth } from '@/auth/usePortalAuth'

export function HomePage() {
  const { isAuthenticated } = usePortalAuth()

  return (
    <PageShell>
      <div className="portal-hero">
        <p className="portal-kicker">Vite React migration scaffold</p>
        <h1>Notch Portal</h1>
        <p>
          New SPA shell for the Portal migration. The existing Next.js Portal remains active while Go API and Vite UI reach feature parity.
        </p>
        <a className="portal-button" href={isAuthenticated ? '/account' : '/api/auth/google'}>
          {isAuthenticated ? 'Open account' : 'Continue with Google'}
        </a>
      </div>
    </PageShell>
  )
}
