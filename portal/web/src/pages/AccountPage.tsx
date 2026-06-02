import { PageShell } from '@/components/ui/PageShell'
import { ProfileView } from '@/components/portal/ProfileView'

export function AccountPage() {
  return (
    <PageShell noShell noHeader>
      <ProfileView />
    </PageShell>
  )
}

