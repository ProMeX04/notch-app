import { CheckCircle2, Loader2 } from 'lucide-react'

type PortalAppHandoffCardProps = {
  mode: 'loading' | 'ready'
  title?: string
  description?: string
  primaryLabel: string
  onPrimaryAction: () => void
}

export function PortalAppHandoffCard({
  mode,
  title,
  description,
  primaryLabel,
  onPrimaryAction,
}: PortalAppHandoffCardProps) {
  const resolvedTitle =
    title ??
    (mode === 'loading' ? 'Đang chuyển sang Notch' : 'Tiếp tục trong ứng dụng Notch')

  const resolvedDescription =
    description ??
    (mode === 'loading'
      ? 'Trình duyệt đang mở Notch để hoàn tất đăng nhập.'
      : 'Nếu ứng dụng chưa hiện lên, bạn có thể mở lại ngay.')

  return (
    <div className="portal-app-handoff-card">
      <div className={`portal-app-handoff-badge ${mode === 'loading' ? 'is-loading' : 'is-ready'}`}>
        {mode === 'loading' ? (
          <Loader2 size={20} className="portal-spinner" />
        ) : (
          <CheckCircle2 size={22} />
        )}
      </div>

      <div className="portal-app-handoff-copy">
        <h2>{resolvedTitle}</h2>
        <p>{resolvedDescription}</p>
      </div>

      <div className="portal-app-handoff-actions">
        <button type="button" className="portal-button" style={{ width: '100%' }} onClick={onPrimaryAction}>
          {primaryLabel}
        </button>
      </div>
    </div>
  )
}
