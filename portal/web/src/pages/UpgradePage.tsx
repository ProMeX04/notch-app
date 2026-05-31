import { PageShell } from '@/components/ui/PageShell'
import { apiClient } from '@/api/client'

export function UpgradePage() {
  const startCheckout = async () => {
    const response = await apiClient.post<{ pay_url: string }>('/api/payments/vnpay/create')
    window.location.href = response.data.pay_url
  }

  return (
    <PageShell>
      <section className="portal-card">
        <p className="portal-kicker">Notch Pro</p>
        <h1>Upgrade</h1>
        <p>Payment behavior will stay server-authoritative and VNPay-compatible in the Go API.</p>
        <button type="button" className="portal-button" onClick={() => void startCheckout()}>
          Start VNPay checkout
        </button>
      </section>
    </PageShell>
  )
}
