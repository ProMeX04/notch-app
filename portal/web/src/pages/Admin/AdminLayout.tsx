import { Link, Outlet } from '@tanstack/react-router'

import { PageShell } from '@/components/ui/PageShell'
import { usePortalAuth } from '@/auth/usePortalAuth'

export function AdminLayout() {
  const { status, user } = usePortalAuth()

  return (
    <PageShell>
      <section className="portal-admin-layout">
        <aside className="portal-admin-sidebar">
          <h2>Admin</h2>
          <Link to="/admin">Dashboard</Link>
          <Link to="/admin/users">Users</Link>
          <Link to="/admin/capabilities">Capabilities</Link>
          <Link to="/admin/gemini-live">Gemini Live</Link>
          <Link to="/admin/settings">Settings</Link>
        </aside>
        <div className="portal-admin-content">
          {status === 'booting' ? <p>Checking admin session…</p> : null}
          {status === 'guest' || !user ? <p>Sign in as an admin to continue.</p> : <Outlet />}
        </div>
      </section>
    </PageShell>
  )
}
