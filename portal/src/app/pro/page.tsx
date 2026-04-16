'use client';

import React, { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  ArrowRight,
  Check,
  CreditCard,
  Loader2,
  LogOut,
  Mail,
  Shield,
  Sparkles,
  UserRound,
  Zap,
} from 'lucide-react';

type AccountPlan = 'free' | 'pro';
type AccountMe = {
  id: string;
  email: string;
  name: string | null;
  created_at: string;
  is_pro: boolean;
};

export default function ProPage() {
  const [isLoading, setIsLoading] = useState(false);
  const [isAccountLoading, setIsAccountLoading] = useState(true);
  const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);
  const [accountEmail, setAccountEmail] = useState('');
  const [accountName, setAccountName] = useState('');
  const [accountPlan, setAccountPlan] = useState<AccountPlan>('free');
  const [createdAt, setCreatedAt] = useState<string | null>(null);

  useEffect(() => {
    let ignore = false;

    const hydrateAccount = async () => {
      const token = localStorage.getItem('notch:accessToken') ?? '';
      if (!token) {
        if (!ignore) {
          setIsAccountLoading(false);
        }
        return;
      }

      try {
        const response = await fetch('/api/auth/me', {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        });

        if (!response.ok) {
          throw new Error('Session expired');
        }

        const data = (await response.json()) as AccountMe;
        if (ignore) return;

        setAccountEmail(data.email ?? '');
        setAccountName(data.name ?? '');
        setAccountPlan(data.is_pro ? 'pro' : 'free');
        setCreatedAt(data.created_at);
      } catch {
        localStorage.removeItem('notch:accessToken');

        if (!ignore) {
          setAccountEmail('');
          setAccountName('');
          setAccountPlan('free');
          setCreatedAt(null);
        }
      } finally {
        if (!ignore) {
          setIsAccountLoading(false);
        }
      }
    };

    hydrateAccount();

    return () => {
      ignore = true;
    };
  }, []);

  const title = useMemo(() => {
    if (accountName.trim()) {
      return accountName.trim();
    }
    if (accountEmail.trim()) {
      return accountEmail.trim();
    }
    return 'Your Notch Account';
  }, [accountEmail, accountName]);

  const subtitle = accountEmail.trim()
    ? 'Your account is connected and ready to use in the Notch app.'
    : 'Use this page to manage your account and upgrade to Premium when you are ready.';
  const hasAccount = Boolean(accountEmail.trim() || accountName.trim());
  const memberSince = createdAt
    ? new Intl.DateTimeFormat('en', { month: 'short', year: 'numeric' }).format(new Date(createdAt))
    : null;

  const handleSubscribe = async () => {
    setIsLoading(true);
    setMsg(null);
    const token = localStorage.getItem('notch:accessToken') ?? '';

    if (!token) {
      setMsg({ type: 'err', text: 'Please sign in again before starting VNPAY checkout.' });
      setIsLoading(false);
      return;
    }

    try {
      const response = await fetch('/api/payments/vnpay/create', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
      });

      const data = await response.json() as { pay_url?: string; detail?: string };
      if (!response.ok || !data.pay_url) {
        throw new Error(data.detail || 'Unable to create VNPAY checkout.');
      }

      window.location.href = data.pay_url;
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Unable to create VNPAY checkout.',
      });
      setIsLoading(false);
    }
  };

  const handleSignOut = async () => {
    const token = localStorage.getItem('notch:accessToken');

    if (token) {
      await fetch('/api/auth/logout', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
        },
      }).catch(() => {});
    }

    localStorage.removeItem('notch:accessToken');
    window.location.href = '/login';
  };

  return (
    <div className="account-container">
      <div className="account-card glass">
        <div className="account-header">
          <div className="badge">
            <UserRound size={14} />
            <span>Account</span>
          </div>
          <h1 className="account-title">Your Notch Account</h1>
          <p className="account-subtitle">Manage your account and upgrade to Premium from one place.</p>
        </div>

        <section className="account-summary">
          <div className="summary-top">
            <div className="avatar-shell">
              <UserRound size={26} />
            </div>
            <div className="summary-copy">
              <div className="summary-headline">
                <h2>{isAccountLoading ? 'Loading account...' : title}</h2>
                <span className={`plan-pill ${accountPlan === 'pro' ? 'pro' : 'free'}`}>
                  {accountPlan === 'pro' ? 'Premium' : 'Free'}
                </span>
              </div>
              <p>{isAccountLoading ? 'Checking your current session and loading account details.' : subtitle}</p>
            </div>
          </div>

          <div className="summary-meta">
            <div className="meta-row">
              <span>Email</span>
              <strong>{isAccountLoading ? 'Loading...' : accountEmail || 'No account loaded yet'}</strong>
            </div>
            <div className="meta-row">
              <span>Status</span>
              <strong>
                {isAccountLoading ? 'Checking...' : accountPlan === 'pro' ? 'Premium active' : 'Ready to upgrade'}
              </strong>
            </div>
            <div className="meta-row">
              <span>Member since</span>
              <strong>{isAccountLoading ? 'Loading...' : memberSince || 'Sign in to load account data'}</strong>
            </div>
          </div>
        </section>

        <section className="upgrade-panel">
          <div className="upgrade-copy">
            <div className="badge premium">
              <Sparkles size={14} />
              <span>Premium</span>
            </div>
            <h3>Upgrade to Premium</h3>
            <p>Start a VNPAY checkout directly from your account page and unlock the current Pro plan.</p>
          </div>

          <div className="features-list">
            <div className="feature-item">
              <div className="icon-wrap blue"><Zap size={18} /></div>
              <div className="feature-text">
                <h4>Unlimited Gemini Live</h4>
                <p>No more usage limits for real-time AI conversations.</p>
              </div>
              <Check size={18} className="check-icon" />
            </div>

            <div className="feature-item">
              <div className="icon-wrap purple"><Shield size={18} /></div>
              <div className="feature-text">
                <h4>Advanced Privacy</h4>
                <p>Priority local processing and enhanced data encryption.</p>
              </div>
              <Check size={18} className="check-icon" />
            </div>

            <div className="feature-item">
              <div className="icon-wrap green"><Sparkles size={18} /></div>
              <div className="feature-text">
                <h4>Early Access</h4>
                <p>Be the first to try new experimental features and tools.</p>
              </div>
              <Check size={18} className="check-icon" />
            </div>
          </div>

          <div className="pricing-section">
            <div className="price">
              <span className="amount">99,000</span>
              <span className="period">VND</span>
            </div>
            <p className="billing-info">Current checkout amount for the web plan.</p>
          </div>

          {msg && <div className={`message ${msg.type}`}>{msg.text}</div>}

          <div className="actions">
            <button className="primary-button" onClick={handleSubscribe} disabled={isLoading || accountPlan === 'pro'}>
              {isLoading ? (
                <Loader2 className="animate-spin" size={20} />
              ) : accountPlan === 'pro' ? (
                <>
                  <Check size={20} />
                  <span>Premium Active</span>
                </>
              ) : (
                <>
                  <CreditCard size={20} />
                  <span>Pay with VNPAY</span>
                </>
              )}
            </button>

            <button className="secondary-button" onClick={handleSignOut}>
              <LogOut size={18} />
              <span>Sign out</span>
            </button>
          </div>
        </section>

        <div className="account-footer">
          <p>After upgrading, tap <b>Refresh Pro status</b> in the Notch app settings.</p>
          <div className="links">
            {hasAccount ? (
              <Link href="/login">
                <Mail size={15} />
                <span>Switch account</span>
              </Link>
            ) : (
              <>
                <Link href="/login">
                  <Mail size={15} />
                  <span>Sign in</span>
                </Link>
                <span className="dot">•</span>
                <Link href="/signup">
                  <ArrowRight size={15} />
                  <span>Create account</span>
                </Link>
              </>
            )}
          </div>
        </div>
      </div>

      <style jsx>{`
        .account-container {
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          padding: 24px;
        }

        .account-card {
          width: 100%;
          max-width: 560px;
          padding: 36px;
          border-radius: 24px;
          animation: slideUp 0.6s cubic-bezier(0.16, 1, 0.3, 1);
        }

        .account-header {
          text-align: center;
          margin-bottom: 28px;
        }

        .badge {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 6px 12px;
          background: rgba(59, 130, 246, 0.1);
          border: 1px solid rgba(59, 130, 246, 0.18);
          border-radius: 999px;
          color: #7dd3fc;
          font-size: 12px;
          font-weight: 600;
          margin-bottom: 16px;
        }

        .badge.premium {
          margin-bottom: 14px;
          background: rgba(168, 85, 247, 0.12);
          border-color: rgba(168, 85, 247, 0.24);
          color: #d8b4fe;
        }

        .account-title {
          font-size: 32px;
          font-weight: 700;
          margin-bottom: 10px;
          background: linear-gradient(to bottom, #fff, #a1a1aa);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
        }

        .account-subtitle {
          font-size: 15px;
          color: var(--muted);
          line-height: 1.5;
        }

        .account-summary,
        .upgrade-panel {
          border: 1px solid var(--border);
          background: rgba(255, 255, 255, 0.025);
          border-radius: 20px;
          padding: 22px;
        }

        .account-summary {
          margin-bottom: 18px;
        }

        .summary-top {
          display: flex;
          gap: 16px;
          align-items: center;
          margin-bottom: 18px;
        }

        .avatar-shell {
          width: 56px;
          height: 56px;
          border-radius: 18px;
          display: flex;
          align-items: center;
          justify-content: center;
          background: linear-gradient(135deg, rgba(59, 130, 246, 0.18), rgba(168, 85, 247, 0.16));
          color: white;
          flex-shrink: 0;
        }

        .summary-copy {
          min-width: 0;
          flex: 1;
        }

        .summary-headline {
          display: flex;
          align-items: center;
          gap: 10px;
          flex-wrap: wrap;
          margin-bottom: 6px;
        }

        .summary-headline h2 {
          font-size: 20px;
          font-weight: 700;
          margin: 0;
          word-break: break-word;
        }

        .summary-copy p {
          font-size: 14px;
          line-height: 1.5;
          color: var(--muted);
          margin: 0;
        }

        .plan-pill {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-height: 28px;
          padding: 0 10px;
          border-radius: 999px;
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 0.02em;
        }

        .plan-pill.free {
          background: rgba(255, 255, 255, 0.06);
          color: #e4e4e7;
        }

        .plan-pill.pro {
          background: rgba(168, 85, 247, 0.14);
          color: #d8b4fe;
        }

        .summary-meta {
          display: grid;
          gap: 10px;
        }

        .meta-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 16px;
          padding: 12px 14px;
          border-radius: 14px;
          background: rgba(255, 255, 255, 0.03);
        }

        .meta-row span {
          font-size: 13px;
          color: var(--muted);
        }

        .meta-row strong {
          font-size: 13px;
          color: white;
          text-align: right;
          word-break: break-word;
        }

        .upgrade-copy {
          margin-bottom: 20px;
        }

        .upgrade-copy h3 {
          font-size: 24px;
          font-weight: 700;
          margin-bottom: 8px;
        }

        .upgrade-copy p {
          font-size: 14px;
          color: var(--muted);
          line-height: 1.55;
        }

        .features-list {
          display: flex;
          flex-direction: column;
          gap: 14px;
          margin-bottom: 24px;
        }

        .feature-item {
          display: flex;
          align-items: center;
          gap: 16px;
          padding: 12px;
          background: rgba(255, 255, 255, 0.02);
          border: 1px solid var(--border);
          border-radius: 14px;
        }

        .icon-wrap {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 36px;
          height: 36px;
          border-radius: 10px;
        }

        .icon-wrap.blue { background: rgba(59, 130, 246, 0.1); color: #3b82f6; }
        .icon-wrap.purple { background: rgba(168, 85, 247, 0.1); color: #a855f7; }
        .icon-wrap.green { background: rgba(34, 197, 94, 0.1); color: #22c55e; }

        .feature-text {
          flex: 1;
        }

        .feature-text h4 {
          font-size: 14px;
          font-weight: 600;
          margin-bottom: 2px;
        }

        .feature-text p {
          font-size: 12px;
          color: var(--muted);
        }

        .check-icon {
          color: #22c55e;
        }

        .pricing-section {
          text-align: center;
          padding: 20px;
          background: rgba(255, 255, 255, 0.02);
          border-radius: 16px;
          margin-bottom: 20px;
        }

        .price {
          margin-bottom: 4px;
        }

        .amount {
          font-size: 36px;
          font-weight: 800;
        }

        .period {
          font-size: 14px;
          color: var(--muted);
        }

        .billing-info {
          font-size: 12px;
          color: var(--muted);
        }

        .message {
          padding: 12px;
          border-radius: 10px;
          font-size: 13px;
          margin-bottom: 20px;
          text-align: center;
        }

        .message.err {
          background: rgba(239, 68, 68, 0.1);
          border: 1px solid rgba(239, 68, 68, 0.2);
          color: #ef4444;
        }

        .message.ok {
          background: rgba(34, 197, 94, 0.1);
          border: 1px solid rgba(34, 197, 94, 0.2);
          color: #22c55e;
        }

        .actions {
          display: flex;
          flex-direction: column;
          gap: 12px;
          margin-bottom: 26px;
        }

        .primary-button {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 10px;
          height: 52px;
          background: white;
          color: black;
          border-radius: 12px;
          font-size: 16px;
          font-weight: 600;
          transition: all 0.2s;
        }

        .primary-button:hover:not(:disabled) {
          background: #f4f4f5;
          transform: translateY(-2px);
          box-shadow: 0 10px 20px -10px rgba(255, 255, 255, 0.2);
        }

        .primary-button:disabled {
          opacity: 0.72;
          cursor: default;
        }

        .secondary-button {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          height: 48px;
          background: transparent;
          border: 1px solid var(--border);
          color: white;
          border-radius: 12px;
          font-size: 14px;
          font-weight: 500;
          transition: all 0.2s;
        }

        .secondary-button:hover {
          background: var(--surface-hover);
          border-color: var(--border-hover);
        }

        .account-footer {
          text-align: center;
        }

        .account-footer p {
          font-size: 13px;
          color: var(--muted);
          line-height: 1.5;
          margin-bottom: 16px;
        }

        .links {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 12px;
          font-size: 14px;
          flex-wrap: wrap;
        }

        .links a {
          color: var(--accent);
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 6px;
        }

        .dot {
          color: var(--border);
        }

        .animate-spin {
          animation: spin 1s linear infinite;
        }

        @media (max-width: 640px) {
          .account-card {
            padding: 24px;
          }

          .summary-top {
            align-items: flex-start;
          }

          .meta-row {
            flex-direction: column;
            align-items: flex-start;
          }

          .meta-row strong {
            text-align: left;
          }
        }

        @keyframes slideUp {
          from { opacity: 0; transform: translateY(20px); }
          to { opacity: 1; transform: translateY(0); }
        }

        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}
