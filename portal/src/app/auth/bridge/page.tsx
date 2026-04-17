'use client';

import { Suspense, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Loader2 } from 'lucide-react';
import { PortalLogo } from '@/components/portal/PortalLogo';
import { storeAuthSession } from '@/lib/portal-auth-client';

type BridgeAuthPayload = {
  access_token: string;
  expires_at: string;
  refresh_token: string;
  refresh_expires_at: string;
  user: {
    email: string;
    name: string | null;
    is_pro: boolean;
  };
};

function isBridgeAuthPayload(value: unknown): value is BridgeAuthPayload {
  if (!value || typeof value !== 'object') return false;
  if (!('access_token' in value) || !('user' in value)) return false;

  const candidate = value as {
    access_token?: unknown;
    expires_at?: unknown;
    refresh_token?: unknown;
    refresh_expires_at?: unknown;
    user?: { email?: unknown; name?: unknown; is_pro?: unknown };
  };

  return (
    typeof candidate.access_token === 'string' &&
    typeof candidate.expires_at === 'string' &&
    typeof candidate.refresh_token === 'string' &&
    typeof candidate.refresh_expires_at === 'string' &&
    !!candidate.user &&
    typeof candidate.user.email === 'string' &&
    typeof candidate.user.is_pro === 'boolean'
  );
}

function BridgeCard({ message }: { message: string }) {
  return (
    <main className="portal-bridge-page">
      <div className="portal-loading-card portal-card">
        <PortalLogo caption="Đăng nhập bảo mật từ Notch app" />
        <Loader2 className="portal-spinner" size={24} />
        <p>{message}</p>
        <Link href="/" className="portal-text-link">
          Quay về trang chủ
        </Link>
      </div>
    </main>
  );
}

function BridgeAuthContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [message, setMessage] = useState('Đang đăng nhập từ Notch app...');

  useEffect(() => {
    let ignore = false;

    const bridgeToken = searchParams.get('token')?.trim() ?? '';
    if (!bridgeToken) {
      setMessage('Liên kết đăng nhập không hợp lệ. Vui lòng quay lại Notch app và thử lại.');
      return;
    }

    const exchange = async () => {
      try {
        const response = await fetch('/api/auth/web-bridge/exchange', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: bridgeToken }),
        });

        const data = await response.json();
        if (!response.ok) {
          const detail =
            typeof data === 'object' && data && 'detail' in data
              ? String((data as { detail?: string }).detail ?? '')
              : '';
          throw new Error(detail || 'Không thể đăng nhập.');
        }

        if (!isBridgeAuthPayload(data)) {
          throw new Error('Không thể đăng nhập.');
        }

        if (ignore) return;

        storeAuthSession(data);
        router.replace('/pro');
      } catch (error) {
        if (ignore) return;
        setMessage(error instanceof Error ? error.message : 'Không thể đăng nhập.');
      }
    };

    exchange();

    return () => {
      ignore = true;
    };
  }, [router, searchParams]);

  return <BridgeCard message={message} />;
}

export default function AuthBridgePage() {
  return (
    <Suspense fallback={<BridgeCard message="Đang chuẩn bị đăng nhập an toàn..." />}>
      <BridgeAuthContent />
    </Suspense>
  );
}
