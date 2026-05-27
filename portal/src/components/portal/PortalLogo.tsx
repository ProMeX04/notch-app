import Image from 'next/image';
import Link from 'next/link';

type PortalLogoProps = {
  href?: string;
  caption?: string;
};

export function PortalLogo({ href = '/', caption }: PortalLogoProps) {
  return (
    <Link href={href} className="portal-logo" aria-label="Trang chủ Notch">
      <Image
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
  );
}
