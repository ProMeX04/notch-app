'use client';

import { Suspense, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Loader2 } from 'lucide-react';
import { Navbar } from '@/components/portal/Navbar';
import { ProfileView } from '@/components/portal/ProfileView';
import { usePortalAuth } from '@/components/portal/PortalAuthProvider';

function AccountPageContent() {
  const router = useRouter();
  const { status, isAuthenticated } = usePortalAuth();

  useEffect(() => {
    if (status === 'guest') {
      router.replace('/login');
    }
  }, [status, router]);

  if (status === 'booting') {
    return (
      <main style={{ background: 'var(--background)', color: 'var(--foreground)', minHeight: '100vh' }}>
        <Navbar />
        <div style={{ display: 'flex', height: '80vh', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: '16px' }}>
          <Loader2 size={28} className="animate-spin" style={{ color: 'var(--accent)' }} />
          <p style={{ color: 'var(--muted)', fontSize: '0.95rem' }}>Đang tải tài khoản...</p>
        </div>
      </main>
    );
  }

  if (!isAuthenticated) {
    return null;
  }

  return (
    <main style={{ background: 'var(--background)', color: 'var(--foreground)', minHeight: '100vh' }}>
      <Navbar />
      <ProfileView />
    </main>
  );
}

export default function AccountPage() {
  return (
    <Suspense
      fallback={
        <div style={{ display: 'flex', height: '100vh', width: '100vw', alignItems: 'center', justifyContent: 'center', background: '#000', color: '#fff' }}>
          <Loader2 className="animate-spin" size={24} />
        </div>
      }
    >
      <AccountPageContent />
    </Suspense>
  );
}
