'use client'

import Link from 'next/link'
import { Check, ExternalLink } from 'lucide-react'

type PortalSuccessEffectProps = {
  title?: string
  description?: string
  primaryLabel?: string
  onPrimaryAction?: () => void
}

export function PortalSuccessEffect({
  title = 'Đăng nhập thành công',
  description = 'Đang chuyển hướng bạn quay lại ứng dụng Notch...',
  primaryLabel = 'Mở Notch thủ công',
  onPrimaryAction,
}: PortalSuccessEffectProps) {

  return (
    <div className="portal-success-overlay">
      <div className="portal-success-bg">
        <div className="bg-blob blob-1"></div>
        <div className="bg-blob blob-2"></div>
        <div className="bg-blob blob-3"></div>
      </div>

      <div className="portal-success-content">
        <div className="portal-success-glass-card">
          <div className="success-icon-container">
            <div className="success-ring-outer"></div>
            <div className="success-ring-inner"></div>
            <div className="success-check-box">
              <Check size={40} className="success-check-icon" strokeWidth={3} />
            </div>
          </div>

          <div className="success-text-container">
            <h1 className="success-title">{title}</h1>
            <p className="success-description">{description}</p>
          </div>

          <div className="success-footer">
            <div className="loading-bar-container">
              <div className="loading-bar-progress"></div>
            </div>
            
            {onPrimaryAction && (
              <button 
                onClick={onPrimaryAction}
                className="portal-button-glass"
              >
                <span>{primaryLabel}</span>
                <ExternalLink size={16} />
              </button>
            )}

            <Link href="/pro" className="portal-button-ghost" style={{ border: 'none', background: 'transparent' }}>
              Quay về Dashboard
            </Link>
          </div>
        </div>

        <div className="portal-success-hints">
          <p>Bạn có thể đóng cửa sổ này sau khi chuyển hướng hoàn tất.</p>
        </div>
      </div>
    </div>
  )
}
