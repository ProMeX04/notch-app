'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { ArrowRight, Check, Copy, Loader2, Mail, UserRound } from 'lucide-react';

export default function LoginPage() {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setIsLoading(true);
    setError(null);

    const formData = new FormData(e.currentTarget);
    const email = formData.get('email') as string;
    const password = formData.get('password') as string;

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Something went wrong');
      }

      const token = data.access_token as string;
      setAccessToken(token);
      localStorage.setItem('notch:accessToken', token);

      try {
        await navigator.clipboard.writeText(token);
        setCopied(true);
      } catch {}
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const handleCopy = () => {
    if (!accessToken) return;
    navigator.clipboard.writeText(accessToken);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="auth-container">
      <div className="auth-card glass">
        <div className="auth-header">
          <div className="logo-container">
            <div className="logo-icon">
              <div className="logo-inner" />
            </div>
            <span className="logo-text">Notch</span>
          </div>
          <h1 className="auth-title">{accessToken ? 'Signed in' : 'Welcome back'}</h1>
          <p className="auth-subtitle">
            {accessToken
              ? 'Copy your access token and paste it into the Notch app.'
              : 'Use the same account across the Notch app and the web portal.'}
          </p>
        </div>

        {accessToken ? (
          <div className="success-container">
            <div className="success-icon-wrap">
              <div className="success-pulse" />
              <Check size={32} className="success-check" />
            </div>

            <div className="token-info">
              <p className="instruction">Your access token is ready</p>
              <p className="instruction-sub">Copy it once, then paste it into the Notch app.</p>
            </div>

            <div className="token-display">
              <code>{accessToken}</code>
              <button onClick={handleCopy} className="copy-button">
                {copied ? <Check size={16} /> : <Copy size={16} />}
                <span>{copied ? 'Copied' : 'Copy'}</span>
              </button>
            </div>

            <div className="divider-minimal" />

            <div className="next-step">
              <p className="next-step-label">Account tools</p>
              <Link href="/pro" className="secondary-cta">
                <UserRound size={18} />
                <span>Go to Account</span>
                <ArrowRight size={18} className="arrow" />
              </Link>
            </div>
          </div>
        ) : (
          <>
            <div className="context-panel">
              <div className="context-icon">
                <Mail size={16} />
              </div>
              <div className="context-copy">
                <p className="context-title">Sign in with your main account</p>
                <p className="context-text">This flow matches the account you will use inside the Notch app.</p>
              </div>
            </div>

            {error && <div className="error-message">{error}</div>}

            <form className="auth-form" onSubmit={handleSubmit}>
              <div className="form-group">
                <label htmlFor="email">Email</label>
                <input type="email" id="email" name="email" placeholder="name@company.com" required />
              </div>

              <div className="form-group">
                <label htmlFor="password">Password</label>
                <input type="password" id="password" name="password" placeholder="••••••••" required />
              </div>

              <button type="submit" className="submit-button" disabled={isLoading}>
                {isLoading ? (
                  <Loader2 className="animate-spin" size={20} />
                ) : (
                  <>
                    <span>Sign In</span>
                    <ArrowRight size={18} />
                  </>
                )}
              </button>
            </form>

            <div className="auth-footer">
              <p>
                Don&apos;t have an account? <Link href="/signup">Create one</Link>
              </p>
            </div>
          </>
        )}
      </div>

      <style jsx>{`
        .auth-container {
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          padding: 24px;
        }

        .auth-card {
          width: 100%;
          max-width: 430px;
          padding: 36px;
          border-radius: 24px;
          animation: slideUp 0.6s cubic-bezier(0.16, 1, 0.3, 1);
        }

        .auth-header {
          text-align: center;
          margin-bottom: 28px;
        }

        .logo-container {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 10px;
          margin-bottom: 22px;
        }

        .logo-icon {
          width: 32px;
          height: 32px;
          background: #3b82f6;
          border-radius: 8px;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .logo-inner {
          width: 16px;
          height: 16px;
          background: white;
          border-radius: 4px;
        }

        .logo-text {
          font-size: 24px;
          font-weight: 700;
          letter-spacing: -0.02em;
        }

        .auth-title {
          font-size: 26px;
          font-weight: 650;
          margin-bottom: 8px;
          background: linear-gradient(to bottom, #fff, #a1a1aa);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
        }

        .auth-subtitle {
          font-size: 14px;
          color: var(--muted);
          line-height: 1.55;
        }

        .context-panel {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 14px;
          margin-bottom: 20px;
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid rgba(255, 255, 255, 0.06);
          border-radius: 14px;
        }

        .context-icon {
          width: 34px;
          height: 34px;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 10px;
          background: rgba(59, 130, 246, 0.12);
          color: #7dd3fc;
          flex-shrink: 0;
        }

        .context-title {
          font-size: 13px;
          font-weight: 600;
          color: white;
          margin-bottom: 3px;
        }

        .context-text {
          font-size: 12px;
          color: var(--muted);
          line-height: 1.45;
        }

        .error-message {
          padding: 12px;
          background: rgba(239, 68, 68, 0.1);
          border: 1px solid rgba(239, 68, 68, 0.2);
          border-radius: 10px;
          color: #ef4444;
          font-size: 13px;
          margin-bottom: 18px;
          text-align: center;
        }

        .auth-form {
          display: flex;
          flex-direction: column;
          gap: 18px;
          margin-bottom: 22px;
        }

        .form-group {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        label {
          font-size: 13px;
          font-weight: 500;
          color: #d4d4d8;
        }

        input {
          height: 46px;
          padding: 0 16px;
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid var(--border);
          border-radius: 12px;
          color: white;
          font-size: 14px;
          transition: all 0.2s;
        }

        input:focus {
          outline: none;
          border-color: var(--accent);
          box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.1);
        }

        .submit-button {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          height: 48px;
          background: white;
          color: black;
          border-radius: 12px;
          font-size: 15px;
          font-weight: 600;
          transition: all 0.2s;
        }

        .submit-button:hover:not(:disabled) {
          transform: translateY(-1px);
          background: #f4f4f5;
        }

        .submit-button:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        .auth-footer {
          text-align: center;
          padding-top: 18px;
          border-top: 1px solid var(--border);
        }

        .auth-footer p {
          font-size: 14px;
          color: var(--muted);
        }

        .auth-footer a {
          color: white;
          font-weight: 600;
        }

        .success-container {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 18px;
          text-align: center;
        }

        .success-icon-wrap {
          position: relative;
          width: 64px;
          height: 64px;
          display: flex;
          align-items: center;
          justify-content: center;
          background: rgba(74, 222, 128, 0.1);
          border-radius: 50%;
        }

        .success-pulse {
          position: absolute;
          inset: 0;
          background: rgba(74, 222, 128, 0.2);
          border-radius: 50%;
          animation: ping 2s cubic-bezier(0, 0, 0.2, 1) infinite;
        }

        .success-check {
          color: #4ade80;
          position: relative;
          z-index: 1;
        }

        .instruction {
          font-size: 16px;
          font-weight: 600;
          color: white;
          margin-bottom: 4px;
        }

        .instruction-sub {
          font-size: 14px;
          color: var(--muted);
        }

        .token-display {
          width: 100%;
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 8px 8px 8px 16px;
          background: #0f1116;
          border: 1px solid var(--border);
          border-radius: 14px;
        }

        code {
          flex: 1;
          font-family: 'JetBrains Mono', monospace;
          color: #e4e4e7;
          font-size: 13px;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          text-align: left;
        }

        .copy-button {
          display: flex;
          align-items: center;
          gap: 6px;
          padding: 8px 12px;
          background: #27272a;
          color: white;
          border-radius: 10px;
          font-size: 13px;
          font-weight: 500;
          transition: all 0.2s;
        }

        .copy-button:hover {
          background: #3f3f46;
        }

        .divider-minimal {
          width: 100%;
          height: 1px;
          background: linear-gradient(to right, transparent, var(--border), transparent);
        }

        .next-step {
          width: 100%;
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .next-step-label {
          font-size: 13px;
          color: var(--muted);
          font-weight: 500;
        }

        .secondary-cta {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 10px;
          height: 52px;
          background: rgba(255, 255, 255, 0.05);
          border: 1px solid rgba(255, 255, 255, 0.08);
          color: white;
          border-radius: 12px;
          font-size: 15px;
          font-weight: 600;
          transition: all 0.2s;
        }

        .secondary-cta:hover {
          transform: translateY(-1px);
          background: rgba(255, 255, 255, 0.08);
          border-color: rgba(255, 255, 255, 0.14);
        }

        .arrow {
          transition: transform 0.2s;
        }

        .secondary-cta:hover .arrow {
          transform: translateX(4px);
        }

        .animate-spin {
          animation: spin 1s linear infinite;
        }

        @media (max-width: 640px) {
          .auth-card {
            padding: 24px;
          }

          .token-display {
            flex-direction: column;
            align-items: stretch;
          }

          .copy-button {
            justify-content: center;
          }
        }

        @keyframes slideUp {
          from { opacity: 0; transform: translateY(20px); }
          to { opacity: 1; transform: translateY(0); }
        }

        @keyframes ping {
          75%, 100% {
            transform: scale(1.2);
            opacity: 0;
          }
        }

        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}
