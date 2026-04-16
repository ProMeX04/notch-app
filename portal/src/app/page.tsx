'use client';

import Link from 'next/link';
import { ArrowRight, Zap, Shield, Sparkles } from 'lucide-react';

export default function Home() {
  return (
    <main className="landing-container">
      <nav className="nav glass">
        <div className="nav-content">
          <div className="logo-container">
            <div className="logo-icon">
              <div className="logo-inner" />
            </div>
            <span className="logo-text">Notch</span>
          </div>
          <div className="nav-links">
            <Link href="/login" className="login-link">Log In</Link>
            <Link href="/signup" className="signup-link">Sign Up</Link>
          </div>
        </div>
      </nav>

      <section className="hero">
        <div className="badge">
          <Sparkles size={14} className="sparkle" />
          <span>New: Gemini Live Integration</span>
        </div>
        <h1 className="hero-title">
          Build faster with <br />
          <span className="text-gradient">Intelligent Notch</span>
        </h1>
        <p className="hero-subtitle">
          The ultimate productivity companion for your Mac. Focus, work, and collaborate with AI at your fingertips.
        </p>
        <div className="hero-actions">
          <Link href="/signup" className="primary-button">
            Get Started
            <ArrowRight size={18} />
          </Link>
          <button className="secondary-button">
            View Demo
          </button>
        </div>
      </section>

      <section className="features">
        <div className="feature-card glass">
          <Zap className="feature-icon blue" />
          <h3>Lightning Fast</h3>
          <p>Optimized for performance and low memory footprint on your Mac.</p>
        </div>
        <div className="feature-card glass">
          <Sparkles className="feature-icon purple" />
          <h3>AI Powered</h3>
          <p>Seamlessly integrated with Gemini Live for real-time assistance.</p>
        </div>
        <div className="feature-card glass">
          <Shield className="feature-icon green" />
          <h3>Secure by Default</h3>
          <p>Your data stays local and private. We prioritize your security.</p>
        </div>
      </section>

      <style jsx>{`
        .landing-container {
          padding-top: 80px;
          min-height: 100vh;
        }

        .nav {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          height: 64px;
          z-index: 100;
          border-bottom: 1px solid var(--border);
        }

        .nav-content {
          max-width: 1200px;
          margin: 0 auto;
          height: 100%;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0 24px;
        }

        .logo-container {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .logo-icon {
          width: 28px;
          height: 28px;
          background: #3B82F6;
          border-radius: 6px;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .logo-inner {
          width: 14px;
          height: 14px;
          background: white;
          border-radius: 3px;
        }

        .logo-text {
          font-weight: 700;
          font-size: 20px;
          letter-spacing: -0.02em;
        }

        .nav-links {
          display: flex;
          align-items: center;
          gap: 24px;
        }

        .login-link {
          font-size: 14px;
          color: var(--muted);
          transition: color 0.2s;
        }

        .login-link:hover {
          color: white;
        }

        .signup-link {
          font-size: 14px;
          font-weight: 600;
          background: white;
          color: black;
          padding: 8px 16px;
          border-radius: 8px;
          transition: opacity 0.2s;
        }

        .signup-link:hover {
          opacity: 0.9;
        }

        .hero {
          max-width: 800px;
          margin: 120px auto 80px;
          text-align: center;
          padding: 0 24px;
        }

        .badge {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 6px 12px;
          background: rgba(59, 130, 246, 0.1);
          border: 1px solid rgba(59, 130, 246, 0.2);
          border-radius: 100px;
          color: #60a5fa;
          font-size: 12px;
          font-weight: 600;
          margin-bottom: 24px;
        }

        .sparkle {
          animation: pulse 2s infinite;
        }

        .hero-title {
          font-size: clamp(40px, 8vw, 72px);
          font-weight: 800;
          line-height: 1.1;
          letter-spacing: -0.04em;
          margin-bottom: 24px;
        }

        .hero-subtitle {
          font-size: clamp(16px, 2vw, 20px);
          color: var(--muted);
          line-height: 1.6;
          margin-bottom: 40px;
          max-width: 600px;
          margin-left: auto;
          margin-right: auto;
        }

        .hero-actions {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 16px;
        }

        .primary-button {
          display: flex;
          align-items: center;
          gap: 8px;
          height: 52px;
          padding: 0 24px;
          background: white;
          color: black;
          border-radius: 12px;
          font-size: 16px;
          font-weight: 600;
          transition: all 0.2s;
        }

        .primary-button:hover {
          transform: translateY(-2px);
          box-shadow: 0 10px 20px -10px rgba(255, 255, 255, 0.2);
        }

        .secondary-button {
          height: 52px;
          padding: 0 24px;
          border: 1px solid var(--border);
          border-radius: 12px;
          color: white;
          font-size: 16px;
          font-weight: 500;
          transition: all 0.2s;
        }

        .secondary-button:hover {
          background: var(--surface-hover);
          border-color: var(--border-hover);
        }

        .features {
          max-width: 1200px;
          margin: 0 auto 120px;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
          gap: 24px;
          padding: 0 24px;
        }

        .feature-card {
          padding: 32px;
          border-radius: 20px;
          transition: transform 0.2s;
        }

        .feature-card:hover {
          transform: translateY(-5px);
        }

        .feature-icon {
          margin-bottom: 20px;
        }

        .feature-icon.blue { color: #3b82f6; }
        .feature-icon.purple { color: #a855f7; }
        .feature-icon.green { color: #22c55e; }

        .feature-card h3 {
          font-size: 18px;
          font-weight: 600;
          margin-bottom: 12px;
        }

        .feature-card p {
          color: var(--muted);
          font-size: 14px;
          line-height: 1.6;
        }

        @keyframes pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.5; transform: scale(0.9); }
        }
      `}</style>
    </main>
  );
}
