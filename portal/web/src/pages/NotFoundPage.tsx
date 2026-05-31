import { PageShell } from '@/components/ui/PageShell'

export function NotFoundPage() {
  return (
    <PageShell>
      <section className="portal-card">
        <p className="portal-kicker">404</p>
        <h1>Page not found</h1>
        <p>This route is not part of the Portal migration shell yet.</p>
      </section>
    </PageShell>
  )
}
