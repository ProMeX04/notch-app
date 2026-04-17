'use client';

import { type FormEvent, useState } from 'react';
import Link from 'next/link';
import { AlertCircle, ArrowRight, Check, Copy, Loader2, ShieldCheck, UserPlus, UserRound } from 'lucide-react';
import { PortalAuthShowcase } from '@/components/portal/PortalAuthShowcase';
import { PortalLogo } from '@/components/portal/PortalLogo';
import { storeAuthSession } from '@/lib/portal-auth-client';

export default function SignupPage() {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [appSessionToken, setAppSessionToken] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setIsLoading(true);
    setError(null);

    const formData = new FormData(e.currentTarget);
    const name = formData.get('name') as string;
    const email = formData.get('email') as string;
    const password = formData.get('password') as string;

    try {
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, password }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Không thể tạo tài khoản. Vui lòng thử lại.');
      }

      const token = (data.session_token as string | undefined) ?? (data.access_token as string);
      setAppSessionToken(token);
      storeAuthSession(data);

      try {
        await navigator.clipboard.writeText(token);
        setCopied(true);
      } catch {}
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Không thể tạo tài khoản. Vui lòng thử lại.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleCopy = () => {
    if (!appSessionToken) return;
    navigator.clipboard.writeText(appSessionToken);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <main className="portal-auth-page-centered">
      <div className="portal-auth-topbar-minimal">
        <PortalLogo />
        <Link href="/login" className="portal-button-ghost">
          Đăng nhập
        </Link>
      </div>

      <section className="portal-auth-container">
        <div className="portal-auth-header-centered">
          <h1 className="portal-auth-title-large">Bắt đầu dùng Notch</h1>
          <p className="portal-muted">Tạo tài khoản để đồng bộ cài đặt và sử dụng các tính năng Premium.</p>
        </div>

        <div className="portal-card portal-auth-card">
          {appSessionToken ? (
            <div className="portal-success-view">
              <div className="portal-success-ring">
                <Check size={32} />
              </div>
              <h2>Tài khoản đã sẵn sàng!</h2>
              <p className="portal-muted">Sao chép token bên dưới và dán vào Notch app để đăng nhập.</p>

              <div className="portal-token-box">
                <code>{appSessionToken}</code>
                <button type="button" onClick={handleCopy} className="portal-token-copy">
                  {copied ? <Check size={16} /> : <Copy size={16} />}
                  {copied ? 'Đã chép' : 'Sao chép'}
                </button>
              </div>

              <div className="portal-divider" />

              <div style={{ display: 'grid', gap: '12px' }}>
                <Link href="/pro" className="portal-button-secondary" style={{ width: '100%' }}>
                  Đi tới trang quản lý tài khoản
                </Link>
                <Link href="/" className="portal-button-ghost" style={{ width: '100%' }}>
                  Quay về trang chủ
                </Link>
              </div>
            </div>
          ) : (
            <form className="portal-auth-form" onSubmit={handleSubmit}>
              {error ? (
                <div className="portal-error">
                  <AlertCircle size={18} />
                  <span>{error}</span>
                </div>
              ) : null}
              
              <div className="portal-field">
                <label htmlFor="name">Họ và tên</label>
                <input className="portal-input" type="text" id="name" name="name" placeholder="Nguyen Van A" required />
              </div>

              <div className="portal-field">
                <label htmlFor="email">Email</label>
                <input className="portal-input" type="email" id="email" name="email" placeholder="email@example.com" required />
              </div>

              <div className="portal-field">
                <label htmlFor="password">Mật khẩu</label>
                <input className="portal-input" type="password" id="password" name="password" placeholder="••••••••" required />
              </div>

              <button type="submit" className="portal-button" disabled={isLoading} style={{ width: '100%', marginTop: '8px' }}>
                {isLoading ? <Loader2 size={18} className="portal-spinner" /> : 'Tạo tài khoản'}
              </button>
            </form>
          )}
        </div>

        {!appSessionToken && (
          <p className="portal-auth-footer-simple">
            Đã có tài khoản? <Link href="/login">Đăng nhập ngay</Link>
          </p>
        )}
      </section>
    </main>
  );
}
