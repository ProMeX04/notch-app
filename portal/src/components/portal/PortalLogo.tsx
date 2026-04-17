import Link from 'next/link';

type PortalLogoProps = {
  href?: string;
  caption?: string;
};

export function PortalLogo({ href = '/', caption }: PortalLogoProps) {
  return (
    <Link href={href} className="portal-logo" aria-label="Trang chủ Notch">
      <img 
        src="/icon.png" 
        alt="" 
        className="portal-logo-img" 
        style={{ width: '32px', height: '32px', borderRadius: '8px' }} 
      />
      <span className="portal-logo-copy">
        <strong>Notch</strong>
        {caption ? <small>{caption}</small> : null}
      </span>
    </Link>
  );
}
