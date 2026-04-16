'use client';

import { Suspense, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { Loader2 } from 'lucide-react';

type BridgeAuthPayload = {
  access_token: string;
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
    user?: { email?: unknown; name?: unknown; is_pro?: unknown };
  };

  return (
    typeof candidate.access_token === 'string' &&
    !!candidate.user &&
    typeof candidate.user.email === 'string' &&
    typeof candidate.user.is_pro === 'boolean'
  );
}

function BridgeCard({ message }: { message: string }) {
  return (
    <div className="bridge-container">
      <div className="bridge-card glass">
        <Loader2 className="spinner" size={24} />
        <p>{message}</p>
      </div>

      <style jsx>{`
        .bridge-container {
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 24px;
        }

        .bridge-card {
          width: 100%;
          max-width: 420px;
          padding: 28px;
          border-radius: 22px;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 14px;
          text-align: center;
        }

        .bridge-card p {
          color: var(--muted);
          line-height: 1.5;
        }

        .spinner {
          animation: spin 1s linear infinite;
        }

        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}

function BridgeAuthContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [message, setMessage] = useState('Signing you in from Notch...');

  useEffect(() => {
    let ignore = false;

    const bridgeToken = searchParams.get('token')?.trim() ?? '';
    if (!bridgeToken) {
      setMessage('This sign-in link is invalid. Please return to the Notch app and try again.');
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
          const detail = typeof data === 'object' && data && 'detail' in data ? String((data as { detail?: string }).detail ?? '') : '';
          throw new Error(detail || 'Unable to sign you in.');
        }

        if (!isBridgeAuthPayload(data)) {
          throw new Error('Unable to sign you in.');
        }

        if (ignore) return;

        localStorage.setItem('notch:accessToken', data.access_token);

        router.replace('/pro');
      } catch (error) {
        if (ignore) return;
        setMessage(error instanceof Error ? error.message : 'Unable to sign you in.');
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
    <Suspense fallback={<BridgeCard message="Preparing secure sign-in..." />}>
      <BridgeAuthContent />
    </Suspense>
  );
}
