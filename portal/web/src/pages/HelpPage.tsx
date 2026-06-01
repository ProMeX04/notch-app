import { useState } from 'react'
import { HelpCircle, Mail, MessageSquare, ChevronDown } from 'lucide-react'
import { PageShell } from '@/components/ui/PageShell'

export function HelpPage() {
  const faqs = [
    {
      q: 'Làm sao để kết nối Chrome Focus Blocker?',
      a: 'Hãy bật cổng WebSocket Bridge trong Notch App Settings. Sau đó mở Chrome extensions, bật Developer mode, chọn "Load unpacked" và chọn thư mục chrome-extension/notch-focus-blocker có sẵn trong repo.'
    },
    {
      q: 'Làm sao để nâng cấp tài khoản Pro?',
      a: 'Sau khi đăng nhập bằng Google trên trang chủ Portal, bạn sẽ được tự động đưa đến trang cá nhân. Nhấn nút "Nâng cấp Pro ngay" để chuyển tiếp qua cổng VNPAY thực hiện giao dịch.'
    },
    {
      q: 'Tại sao app không thể mở sau khi tải về?',
      a: 'Do cơ chế bảo mật Gatekeeper của macOS chặn phần mềm ngoài App Store. Bạn hãy vào System Settings > Privacy & Security, kéo xuống dưới cùng mục Security và chọn "Open Anyway" là xong.'
    }
  ]

  // Track which FAQ index is expanded
  const [expandedIndex, setExpandedIndex] = useState<number | null>(null)

  const toggleAccordion = (index: number) => {
    setExpandedIndex(expandedIndex === index ? null : index)
  }

  return (
    <PageShell>
      <main style={{ minHeight: '80vh', display: 'flex', flexDirection: 'column', padding: '40px 20px' }}>
        <header style={{ textAlign: 'center', marginBottom: '60px' }}>
          <span className="portal-badge" style={{ marginBottom: '16px', display: 'inline-block' }}>Hỗ trợ</span>
          <h1 style={{ fontSize: 'clamp(2.5rem, 6vw, 4rem)', fontWeight: 800, margin: '0 0 16px 0', letterSpacing: '-0.03em' }}>Trợ giúp & FAQ</h1>
          <p style={{ color: 'var(--muted)', maxWidth: '600px', margin: '0 auto', fontSize: '1.1rem', lineHeight: '1.5' }}>
            Tìm câu trả lời cho các vấn đề thường gặp hoặc liên hệ trực tiếp với bộ phận hỗ trợ kỹ thuật của chúng tôi.
          </p>
        </header>

        {/* FAQs Accordion */}
        <div style={{ maxWidth: '800px', width: '100%', margin: '0 auto 48px' }}>
          <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '24px', textAlign: 'center' }}>Câu hỏi thường gặp</h2>
          <div style={{ display: 'grid', gap: '16px' }}>
            {faqs.map((faq, index) => {
              const isExpanded = expandedIndex === index
              return (
                <div 
                  key={index} 
                  className="portal-card" 
                  style={{ 
                    background: 'var(--card)', 
                    border: '1px solid var(--border)', 
                    padding: '24px', 
                    borderRadius: '16px',
                    cursor: 'pointer',
                    transition: 'all 0.2s ease-in-out'
                  }}
                  onClick={() => toggleAccordion(index)}
                >
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
                    <h3 style={{ fontSize: '1.1rem', fontWeight: 700, margin: 0, display: 'flex', alignItems: 'center', gap: '10px', color: 'var(--foreground)' }}>
                      <HelpCircle size={18} style={{ color: 'var(--accent)', flexShrink: 0 }} />
                      {faq.q}
                    </h3>
                    <ChevronDown 
                      size={18} 
                      style={{ 
                        transform: isExpanded ? 'rotate(180deg)' : 'rotate(0deg)', 
                        transition: 'transform 0.2s ease',
                        color: 'var(--muted)' 
                      }} 
                    />
                  </div>
                  <div 
                    style={{ 
                      maxHeight: isExpanded ? '200px' : '0px', 
                      overflow: 'hidden', 
                      transition: 'all 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
                      opacity: isExpanded ? 1 : 0
                    }}
                  >
                    <p style={{ color: 'var(--muted)', fontSize: '0.95rem', lineHeight: 1.6, marginTop: '16px', marginBottom: 0 }}>
                      {faq.a}
                    </p>
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* Contact Info */}
        <div className="portal-card" style={{ background: 'linear-gradient(180deg, rgba(255,255,255,0.03) 0%, transparent 100%)', border: '1px solid var(--border)', padding: '40px', borderRadius: '24px', maxWidth: '800px', width: '100%', margin: '0 auto', textAlign: 'center' }}>
          <h2 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: '12px', margin: '0 0 12px 0' }}>Không tìm thấy câu trả lời?</h2>
          <p style={{ color: 'var(--muted)', marginBottom: '28px', margin: '0 0 28px 0' }}>Liên hệ trực tiếp với chúng tôi qua các kênh hỗ trợ kỹ thuật bên dưới.</p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '24px', flexWrap: 'wrap' }}>
            <a href="mailto:support@notch.app" className="portal-button-ghost" style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '12px 24px', borderRadius: '999px', textDecoration: 'none', border: '1px solid var(--border)' }}>
              <Mail size={16} />
              <span>support@notch.app</span>
            </a>
            <a href="https://github.com/ProMeX04/notch-app/issues" target="_blank" rel="noopener noreferrer" className="portal-button-ghost" style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '12px 24px', borderRadius: '999px', textDecoration: 'none', border: '1px solid var(--border)' }}>
              <MessageSquare size={16} />
              <span>Báo lỗi trên GitHub</span>
            </a>
          </div>
        </div>
      </main>
    </PageShell>
  )
}
