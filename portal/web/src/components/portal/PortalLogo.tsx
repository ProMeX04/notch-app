import { Link } from '@tanstack/react-router'

type PortalLogoProps = {
  to?: string
  caption?: string
}

export function PortalLogo({ to = '/', caption }: PortalLogoProps) {
  return (
    <Link to={to} className="portal-logo" aria-label="Trang chủ Notch">
      <img
        src="/icon.png"
        alt=""
        width={32}
        height={32}
        className="portal-logo-img"
        style={{ borderRadius: '8px' }}
      />
      <span className="portal-logo-copy">
        <strong>Notch</strong>
        {caption ? <small>{caption}</small> : null}
      </span>
    </Link>
  )
}
