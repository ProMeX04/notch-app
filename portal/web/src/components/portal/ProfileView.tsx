import { useState } from 'react'
import { Link } from '@tanstack/react-router'
import { LogOut, Loader2, Save, User, ShieldCheck } from 'lucide-react'
import { apiClient } from '@/api/client'
import { usePortalAuth } from '@/auth/usePortalAuth'

export function ProfileView() {
  const { status, user, signOut, refreshAuthState } = usePortalAuth()
  
  const [name, setName] = useState(user?.name || '')
  const [avatarUrl, setAvatarUrl] = useState(user?.avatar_url || '')
  const [isSaving, setIsSaving] = useState(false)
  const [msg, setMsg] = useState<{ type: 'ok' | 'err'; text: string } | null>(null)

  if (status === 'booting') {
    return (
      <div
        style={{
          minHeight: '60vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <div style={{ textAlign: 'center' }}>
          <Loader2
            size={32}
            className="portal-spinner animate-spin"
            style={{ margin: '0 auto 16px', color: '#003fb1' }}
          />
          <p style={{ color: '#434654' }}>Đang đồng bộ dữ liệu tài khoản...</p>
        </div>
      </div>
    )
  }

  if (status === 'guest' || !user) {
    return null
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setIsSaving(true)
    setMsg(null)

    try {
      await apiClient.patch('/api/auth/profile', {
        name: name.trim() || null,
        avatar_url: avatarUrl.trim() || null,
      })
      await refreshAuthState()
      setMsg({ type: 'ok', text: 'Cập nhật tài khoản thành công!' })
    } catch (error) {
      setMsg({
        type: 'err',
        text: error instanceof Error ? error.message : 'Không thể cập nhật tài khoản.',
      })
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <>
      <style>{`
        body {
          background-color: #f9f9ff !important;
          color: #141b2b !important;
        }
        .profile-input {
          width: 100%;
          height: 46px;
          padding: 0 16px;
          border-radius: 12px;
          background: #ffffff;
          border: 1px solid rgba(0, 0, 0, 0.12);
          color: #141b2b;
          font-size: 0.95rem;
          transition: all 150ms ease;
        }
        .profile-input:focus {
          outline: none;
          border-color: #003fb1;
          box-shadow: 0 0 0 4px rgba(0, 63, 177, 0.1);
        }
      `}</style>

      <div 
        style={{
          maxWidth: '480px',
          width: '100%',
          margin: '0 auto',
          padding: '6rem 1rem 4rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '32px',
          animation: 'portalRise 0.6s cubic-bezier(0.16, 1, 0.3, 1) both',
        }}
      >
        {/* Header Section */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <h1 style={{ fontSize: '1.75rem', fontWeight: 850, letterSpacing: '-0.04em', margin: 0 }}>
              Hồ sơ cá nhân
            </h1>
            <p style={{ fontSize: '0.88rem', color: '#434654', margin: '4px 0 0' }}>
              {user.email}
            </p>
          </div>
          
          <button
            type="button"
            onClick={() => void signOut()}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '6px',
              height: '38px',
              padding: '0 16px',
              borderRadius: '999px',
              background: 'rgba(239, 68, 68, 0.08)',
              color: '#ef4444',
              fontWeight: 600,
              fontSize: '0.85rem',
              border: '1px solid rgba(239, 68, 68, 0.12)',
              cursor: 'pointer',
              transition: 'all 0.2s ease',
            }}
          >
            <LogOut size={14} />
            Đăng xuất
          </button>
        </div>

        {msg && (
          <div
            style={{
              padding: '14px 18px',
              borderRadius: '12px',
              fontSize: '0.9rem',
              fontWeight: 600,
              border: '1px solid',
              background: msg.type === 'ok' ? 'rgba(16, 185, 129, 0.08)' : 'rgba(239, 68, 68, 0.08)',
              borderColor: msg.type === 'ok' ? 'rgba(16, 185, 129, 0.16)' : 'rgba(239, 68, 68, 0.16)',
              color: msg.type === 'ok' ? '#10b981' : '#ef4444',
            }}
          >
            {msg.text}
          </div>
        )}

        {/* Profile Update Form */}
        <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          
          {/* Avatar Preview & URL Input */}
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '16px' }}>
            <div 
              style={{
                width: '100px',
                height: '100px',
                borderRadius: '50%',
                overflow: 'hidden',
                background: '#e9edff',
                border: '2px solid rgba(0, 63, 177, 0.12)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: '0 8px 24px rgba(0, 0, 0, 0.05)',
              }}
            >
              {avatarUrl.trim() ? (
                <img 
                  src={avatarUrl} 
                  alt="Avatar" 
                  style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                  onError={(e) => {
                    e.currentTarget.style.display = 'none'
                  }}
                />
              ) : (
                <User size={40} style={{ color: '#003fb1' }} />
              )}
            </div>
            
            <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <label style={{ fontSize: '0.88rem', fontWeight: 700, color: '#141b2b' }}>
                Ảnh đại diện (URL)
              </label>
              <input
                type="url"
                value={avatarUrl}
                onChange={(e) => setAvatarUrl(e.target.value)}
                placeholder="Nhập đường dẫn URL ảnh của bạn"
                className="profile-input"
              />
            </div>
          </div>

          {/* Name Input */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            <label style={{ fontSize: '0.88rem', fontWeight: 700, color: '#141b2b' }}>
              Tên hiển thị
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Nhập tên hiển thị"
              required
              className="profile-input"
            />
          </div>

          {/* Plan Info Status */}
          <div 
            style={{ 
              display: 'flex', 
              justifyContent: 'space-between', 
              alignItems: 'center', 
              padding: '16px 4px',
              borderTop: '1px solid rgba(0, 0, 0, 0.06)',
              borderBottom: '1px solid rgba(0, 0, 0, 0.06)',
              marginTop: '8px'
            }}
          >
            <span style={{ fontSize: '0.9rem', fontWeight: 600, color: '#434654' }}>Gói tài khoản</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              {user.is_pro ? (
                <>
                  <ShieldCheck size={16} style={{ color: '#f97316' }} />
                  <span style={{ fontSize: '0.9rem', fontWeight: 750, color: '#f97316' }}>Notch Pro</span>
                </>
              ) : (
                <span style={{ fontSize: '0.9rem', fontWeight: 750, color: '#434654' }}>Miễn phí</span>
              )}
            </div>
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={isSaving}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px',
              minHeight: '3rem',
              padding: '0 2rem',
              borderRadius: '999px',
              background: '#003fb1',
              color: '#ffffff',
              fontWeight: 700,
              fontSize: '0.95rem',
              boxShadow: 'rgba(0, 63, 177, 0.15) 0px 4px 12px 0px',
              border: 'none',
              transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
              cursor: 'pointer',
              marginTop: '12px',
            }}
            onMouseEnter={(e) => {
              if (!isSaving) {
                e.currentTarget.style.transform = 'translateY(-2px)'
                e.currentTarget.style.boxShadow = 'rgba(0, 63, 177, 0.25) 0px 8px 20px 0px'
              }
            }}
            onMouseLeave={(e) => {
              if (!isSaving) {
                e.currentTarget.style.transform = 'translateY(0)'
                e.currentTarget.style.boxShadow = 'rgba(0, 63, 177, 0.15) 0px 4px 12px 0px'
              }
            }}
          >
            {isSaving ? (
              <Loader2 size={18} className="animate-spin" />
            ) : (
              <Save size={18} />
            )}
            Lưu thay đổi
          </button>
        </form>
        
        {/* Back Link */}
        <div style={{ textAlign: 'center', marginTop: '-8px' }}>
          <Link
            to="/"
            style={{
              fontSize: '0.88rem',
              fontWeight: 600,
              color: '#434654',
              transition: 'color 0.2s ease',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.color = '#003fb1'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.color = '#434654'
            }}
          >
            Quay lại trang chủ
          </Link>
        </div>
      </div>
    </>
  )
}

