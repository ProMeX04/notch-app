// v1.0.2
import { useEffect, useState } from 'react'
import { Link } from '@tanstack/react-router'
import { PageShell } from '@/components/ui/PageShell'
import { usePortalAuth } from '@/auth/usePortalAuth'
import { apiClient } from '@/api/client'
import { HelpCircle, Mail, MessageSquare, ChevronDown } from 'lucide-react'

// ─── Types ───────────────────────────────────────────────────────────────────

export type FocusWindow = 'week' | 'all'

export type LeaderboardEntry = {
  rank: number
  user_id: string
  display_name: string
  avatar_url?: string | null
  focus_seconds: number
  session_count: number
}

type PortalCapability = {
  key: string
  name: string
  description: string
  isProOnly: boolean
  isEnabled: boolean
}

// ─── Constants & Fallbacks ───────────────────────────────────────────────────

const defaultCapabilities: PortalCapability[] = [
  { key: 'talk_connection', name: 'Gemini Live', description: 'Trò chuyện với AI trực tiếp từ Notch', isProOnly: true, isEnabled: true },
  { key: 'focus_pomodoro', name: 'Focus Pomodoro', description: 'Hỗ trợ tập trung và quản lý phiên làm việc', isProOnly: false, isEnabled: true },
  { key: 'focus_website_blocklist', name: 'Chặn website', description: 'Chặn trang web gây xao nhãng', isProOnly: false, isEnabled: true },
  { key: 'media_controls', name: 'Điều khiển nhạc', description: 'Điều khiển nhạc trên Notch', isProOnly: false, isEnabled: true },
  { key: 'browser_bridge', name: 'Kết nối trình duyệt', description: 'Kết nối ứng dụng với trình duyệt', isProOnly: false, isEnabled: true },
  { key: 'panel_shelf', name: 'Shelf', description: 'Lưu tạm tệp tin, văn bản và đường dẫn trong Notch', isProOnly: true, isEnabled: true }
]

const occupations = [
  'Software Engineer',
  'Product Designer',
  'Writer',
  'Data Analyst',
  'Researcher',
  'Developer',
  'Student'
]

const mockAvatars = [
  'https://lh3.googleusercontent.com/aida/ADBb0ui7Xhfsf25eJzaf-xF8q2wpsit3mUqDdyDdsy6pTeLKcyDQlBokzo7ZmGb5pqdmMMWcA-5Uo-6KCIG7K-tm1iE3FptrPyKhnNibvqC55dSe1WXh-Ra-MUaQrzhqaiFEqg9mbMyNLEBk_Nuj4TqwvK3iyA1kmngN9vZxHr2h6JtLkz80ml0U7uFy81O0kF28maiRKe9a4qjdUB91AwEIVFtXQa8LZcL8As3rObYwbrgKrDwjvJLCImE2rbpQ', // Hoàng N.
  'https://lh3.googleusercontent.com/aida/AP1WRLuXQui_38q17EIC-WVd8MqmtjVfLpovbm0BXktZ64OAB4CIDcamhqfgWOljqsaNjQbg-XP0Vr-4RJfL4-8Mt3vp9lknecxgdMG01gzAIpzkgQkU9RW5ncoKyPOFJsXgiEQvXdNOf6o3yz5VA8iOz2W7SbpLvtSa6kc1-jJ-XKgWEsCcmj1MoqN60n11xjGx76DurgNSsjxIZ7kjKZgyVTvEv93S0Ox6nI8FAxCmihdQc1_5Wotd1c30E-69', // Minh T.
  'https://lh3.googleusercontent.com/aida/AP1WRLvf2IjK744W_3cLxgPjj5agdpiaRysl8d1KTB2GpSkE0eAYaYVc3dtMF9gOvtHxwgPRqwTzIFiPdhWvoaejcvVL9fUqOPf0DLXb2LmF8n8EPcktxclMgUJRBNOqjFLf53jinjTmQ7nPF9GaqwkwgdCHlucPV-me6qjBrCNXZejnA6lN9epRa0dQJVhwcSoy3WL-rccZ-cBfwCQ7xNfSOKkH28fl6EKSPXjjoCACpRS4nb-RmJYj3d7K891l', // Linh V.
  'https://lh3.googleusercontent.com/aida/ADBb0uiTkqZ4mB1gGn-wmYdUkqDCRajoOKgrRzsUN5_volRvOqUj-OsXHHqgUYc53hbNWsVpC-0ZpRwzLRsVeg8UQ__CZYIjdcMfrq4GiiacWjNR311zWcVGlXibEiCBAE4OuBBJu5ZYfN6J7c1CcWAh2oum43It0Jn3R6uPQFRkaXFGvkJTiQjazc_w3k7EZAXgxro5Ows-U2bZYL5QiVY7X5A9VbDvqATVewQ_kYRX71Mz_fNfWVI6J0Rm4-dA', // Tuấn A.
  'https://lh3.googleusercontent.com/aida/AP1WRLtJBOnKQotX-g_21ANxY0jM8it_hNKg7xQxLnIdhcB2Awpznv-0KoASinpx8KHGU2Vz1a97Ho0-p-EOLTp-GCLO9ve9g5a2xncjxHp7vbsBzkgZ4CS-vaCoHEErD9MVFAyHiM24TCqVbbgrx0f04hIFKADZ_G-_Pmqi-_aZjw4JE4H8GDkKwYOLO7-xguGxgU4Dh53oyw92sQI0ngUI7q71NOwE3p2pCix9hD8nbEV0WW0matw9SlPFcmE5' // Hương M.
]

const defaultLeaderboardWeek: LeaderboardEntry[] = [
  { rank: 1, user_id: 'mock-1', display_name: 'Hoàng N.', focus_seconds: 142 * 3600 + 15 * 60, session_count: 98, avatar_url: mockAvatars[0] },
  { rank: 2, user_id: 'mock-2', display_name: 'Minh T.', focus_seconds: 128 * 3600 + 45 * 60, session_count: 84, avatar_url: mockAvatars[1] },
  { rank: 3, user_id: 'mock-3', display_name: 'Linh V.', focus_seconds: 115 * 3600 + 30 * 60, session_count: 72, avatar_url: mockAvatars[2] },
  { rank: 4, user_id: 'mock-4', display_name: 'Tuấn A.', focus_seconds: 110 * 3600 + 5 * 60, session_count: 92, avatar_url: mockAvatars[3] },
  { rank: 5, user_id: 'mock-5', display_name: 'Hương M.', focus_seconds: 102 * 3600 + 40 * 60, session_count: 85, avatar_url: mockAvatars[4] },
  { rank: 6, user_id: 'mock-6', display_name: 'Duy K.', focus_seconds: 95 * 3600 + 15 * 60, session_count: 78 }
]

const defaultLeaderboardAll: LeaderboardEntry[] = [
  { rank: 1, user_id: 'mock-all-1', display_name: 'Minh T.', focus_seconds: 840 * 3600 + 20 * 60, session_count: 512, avatar_url: mockAvatars[1] },
  { rank: 2, user_id: 'mock-all-2', display_name: 'Hoàng N.', focus_seconds: 792 * 3600 + 15 * 60, session_count: 480, avatar_url: mockAvatars[0] },
  { rank: 3, user_id: 'mock-all-3', display_name: 'Tuấn A.', focus_seconds: 680 * 3600 + 45 * 60, session_count: 420, avatar_url: mockAvatars[3] },
  { rank: 4, user_id: 'mock-all-4', display_name: 'Linh V.', focus_seconds: 610 * 3600 + 10 * 60, session_count: 390, avatar_url: mockAvatars[2] },
  { rank: 5, user_id: 'mock-all-5', display_name: 'Hương M.', focus_seconds: 580 * 3600 + 55 * 60, session_count: 365, avatar_url: mockAvatars[4] },
  { rank: 6, user_id: 'mock-all-6', display_name: 'Khánh L.', focus_seconds: 520 * 3600 + 30 * 60, session_count: 310 }
]

// ─── Helpers ─────────────────────────────────────────────────────────────────

function getOccupation(userId: string, rank: number): string {
  if (rank === 1) return 'Software Engineer'
  if (rank === 2) return 'Product Designer'
  if (rank === 3) return 'Writer'
  if (rank === 4) return 'Data Analyst'
  if (rank === 5) return 'Researcher'
  if (rank === 6) return 'Developer'
  
  let hash = 0
  for (let i = 0; i < userId.length; i++) {
    hash = userId.charCodeAt(i) + ((hash << 5) - hash)
  }
  const index = Math.abs(hash) % occupations.length
  return occupations[index]
}

const TOTAL_SECONDS = 25 * 60

function formatFocusTime(seconds: number): string {
  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  return `${hrs}h ${String(mins).padStart(2, '0')}m`
}

function initials(displayName: string): string {
  const words = displayName.trim().split(/\s+/).filter(Boolean)
  if (!words.length) return 'N'
  return words
    .slice(-2)
    .map((word) => word.charAt(0).toUpperCase())
    .join('')
}

// ─── Main Component ───────────────────────────────────────────────────────────

export function HomePage() {
  const { isAuthenticated, user } = usePortalAuth()
  const [capabilities, setCapabilities] = useState<PortalCapability[]>(defaultCapabilities)
  const [windowState, setWindowState] = useState<FocusWindow>('week')
  const [limit, setLimit] = useState(6)
  const [isCheckoutLoading, setIsCheckoutLoading] = useState(false)
  const [checkoutError, setCheckoutError] = useState<string | null>(null)
  
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

  const [expandedFaqIndex, setExpandedFaqIndex] = useState<number | null>(null)

  const handleUpgrade = async () => {
    if (!isAuthenticated) {
      window.location.href = '/api/auth/google'
      return
    }
    setIsCheckoutLoading(true)
    setCheckoutError(null)
    try {
      const response = await apiClient.post<{ pay_url: string }>('/api/payments/vnpay/create')
      window.location.href = response.data.pay_url
    } catch (err) {
      setCheckoutError(err instanceof Error ? err.message : 'Không thể tạo phiên thanh toán VNPAY.')
      setIsCheckoutLoading(false)
    }
  }

  useEffect(() => {
    document.documentElement.classList.add('homepage-snap')

    const sections = ['hero', 'features', 'leaderboard', 'download', 'pricing', 'help']

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const id = entry.target.id
            window.history.replaceState(null, '', `#${id}`)
            window.dispatchEvent(new Event('activesectionchange'))
          }
        })
      },
      { threshold: 0.4, rootMargin: '-90px 0px 0px 0px' }
    )

    sections.forEach((id) => {
      const el = document.getElementById(id)
      if (el) observer.observe(el)
    })

    const handleWindowClick = (e: MouseEvent) => {
      const target = e.target as HTMLElement
      const anchor = target.closest('a')
      if (anchor) {
        const href = anchor.getAttribute('href')
        if (href?.startsWith('/#') || href?.startsWith('#')) {
          const hash = href.split('#')[1]
          if (hash && sections.includes(hash)) {
            const el = document.getElementById(hash)
            if (el) {
              el.scrollIntoView({ behavior: 'smooth', block: 'start' })
            }
          }
        } else if (href === '/') {
          const el = document.getElementById('hero')
          if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'start' })
          }
        }
      }
    }

    window.addEventListener('click', handleWindowClick, { capture: true })

    // Handle initial hash scrolling smoothly on load
    const hash = window.location.hash.replace('#', '')
    if (hash) {
      setTimeout(() => {
        const el = document.getElementById(hash)
        if (el) {
          el.scrollIntoView({ behavior: 'smooth', block: 'start' })
        }
      }, 100)
    }

    return () => {
      document.documentElement.classList.remove('homepage-snap')
      observer.disconnect()
      window.removeEventListener('click', handleWindowClick, { capture: true })
    }
  }, [])

  // Pomodoro Timer Logic
  const [time, setTime] = useState(23 * 60 + 21) // Matches mockup 23:21
  const [active, setActive] = useState(true)

  useEffect(() => {
    if (!active) return
    const id = setInterval(() => {
      setTime(t => (t > 0 ? t - 1 : TOTAL_SECONDS))
    }, 1000)
    return () => clearInterval(id)
  }, [active])

  const minutes = Math.floor(time / 60)
  const seconds = time % 60
  const formattedTime = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  const circleCircumference = 2 * Math.PI * 22
  const strokeDashoffset = circleCircumference - (time / TOTAL_SECONDS) * circleCircumference

  // Load Capabilities
  useEffect(() => {
    apiClient.get<{ version: number; features: Record<string, string> }>('/api/capabilities')
      .then(res => {
        const features = res.data?.features
        if (features) {
          setCapabilities(prev => prev.map(c => {
            const req = features[c.key]
            if (!req) return c
            return {
              ...c,
              isProOnly: req === 'pro',
              isEnabled: req !== 'disabled'
            }
          }))
        }
      })
      .catch(() => {})
  }, [])

  // Use static datasets for the homepage leaderboard
  const displayedLeaderboard = windowState === 'week' ? defaultLeaderboardWeek : defaultLeaderboardAll

  // Separate Podium (Top 3) and List (4 onwards)
  const top1 = displayedLeaderboard.find(e => e.rank === 1)
  const top2 = displayedLeaderboard.find(e => e.rank === 2)
  const top3 = displayedLeaderboard.find(e => e.rank === 3)
  const restList = displayedLeaderboard.filter(e => e.rank > 3).slice(0, limit)

  // Current User row helper
  const meEntry = user ? (displayedLeaderboard.find(e => e.user_id === user.id) ?? {
    rank: 42,
    user_id: user.id,
    display_name: user.name ?? 'Bạn',
    avatar_url: user.avatar_url,
    focus_seconds: 45 * 3600 + 20 * 60,
    session_count: 38
  }) : null

  const freeFeatures = capabilities.filter(c => c.isEnabled && !c.isProOnly)
  const proFeatures = capabilities.filter(c => c.isEnabled && c.isProOnly)

  const scrollToSection = (id: string) => {
    const el = document.getElementById(id)
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' })
    }
  }

  return (
    <PageShell noShell={true} noHeader={false}>
      <style>{`
        body {
          background-color: #f9f9ff;
          color: #141b2b;
        }
        .material-symbols-outlined {
          font-variation-settings: 'FILL' 0, 'wght' 300, 'GRAD' 0, 'opsz' 24;
        }
        .material-symbols-outlined.fill {
          font-variation-settings: 'FILL' 1, 'wght' 300, 'GRAD' 0, 'opsz' 24;
        }
        .glass-panel {
          background-color: rgba(255, 255, 255, 0.8);
          backdrop-filter: blur(20px);
          -webkit-backdrop-filter: blur(20px);
          border: 1px solid rgba(0, 0, 0, 0.05);
          box-shadow: 0 4px 20px 0 rgba(0, 0, 0, 0.04);
        }
        .ambient-bg {
          background: radial-gradient(circle at 50% -20%, rgba(26, 86, 219, 0.05) 0%, transparent 70%);
        }
        .progress-ring__circle {
          transition: stroke-dashoffset 1s linear;
          transform: rotate(-90deg);
          transform-origin: 50% 50%;
        }
        @keyframes pulse-soft {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.8; transform: scale(0.95); }
        }
        .pulse-btn {
          animation: pulse-soft 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
        }
        .timer-glow {
          text-shadow: 0 0 10px rgba(0, 84, 56, 0.15);
        }
        @keyframes bobbing {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-4px); }
        }
        .animate-bobbing {
          animation: bobbing 2s ease-in-out infinite;
        }
        @keyframes bar-wave {
          0%, 100% { transform: scaleY(0.5); }
          50% { transform: scaleY(1); }
        }
        .sound-bar {
          width: 4px;
          height: 24px;
          background-color: currentColor;
          border-radius: 99px;
          animation: bar-wave 1s ease-in-out infinite;
        }
        .bar-2 { animation-delay: 0.1s; }
        .bar-3 { animation-delay: 0.2s; }
        .bar-4 { animation-delay: 0.3s; }
        @keyframes shimmer-rotate {
          0% { transform: rotate(0deg) scale(1); opacity: 1; }
          50% { transform: rotate(15deg) scale(1.1); opacity: 0.8; }
          100% { transform: rotate(0deg) scale(1); opacity: 1; }
        }
        .animate-shimmer {
          animation: shimmer-rotate 3s ease-in-out infinite;
        }
        .leaderboard-grid-container {
          display: grid;
          grid-template-columns: 1fr;
          gap: 24px;
        }
        @media (min-width: 768px) {
          .leaderboard-grid-container {
            grid-template-columns: 5fr 7fr !important;
            align-items: start;
          }
        }
      `}</style>

      {/* Ambient background layout wrapper */}
      <div className="min-h-screen flex flex-col relative overflow-x-hidden ambient-bg">
        
        <main className="flex-grow pt-24 lg:pt-0 pb-16 lg:pb-0 px-6 max-w-[1440px] mx-auto w-full z-10 space-y-32 lg:space-y-0">
          
          {/* Hero Section */}
          <section id="hero" className="snap-section flex flex-col items-center text-center justify-center space-y-10 pt-10">
            <div className="space-y-6 max-w-5xl">
              <h1 className="text-5xl md:text-8xl font-black text-[#141b2b] tracking-tight leading-tight">
                Notch: Trợ lý tập trung trên Mac OS
              </h1>
              <p className="text-xl md:text-2xl text-[#434654] max-w-4xl mx-auto leading-relaxed">
                Biến khoảng trống trên màn hình thành trung tâm điều khiển mạnh mẽ. Quản lý thời gian, tệp tin và tương tác với AI mà không cần rời khỏi luồng công việc.
              </p>
            </div>
            <div className="flex items-center gap-6 pt-4">
              <button 
                onClick={() => scrollToSection('features')}
                className="font-semibold text-base md:text-lg px-8 py-4 rounded-full flex items-center gap-3 hover:opacity-90 active:scale-95 transition-all bg-[#003fb1] text-white" 
                style={{ boxShadow: 'rgba(0, 63, 177, 0.2) 0px 4px 12px 0px' }}
              >
                <span className="material-symbols-outlined" style={{ fontVariationSettings: '"FILL" 1', fontSize: '22px' }}>download</span> 
                Tải xuống cho macOS
              </button>
            </div>
          </section>

          {/* Feature Showcase Bento Grid */}
          <section id="features" className="snap-section flex flex-col justify-center">
            <div className="w-full grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
              {/* Shelf */}
              <div className="glass-panel rounded-2xl p-8 flex flex-col items-start gap-6 hover:-translate-y-1 transition-transform duration-300">
                <div className="h-14 w-14 rounded-full bg-blue-50 flex items-center justify-center text-blue-600 border border-blue-100 shrink-0">
                  <span className="material-symbols-outlined animate-bobbing" style={{ fontSize: '28px' }}>folder_open</span>
                </div>
                <div className="text-left">
                  <h3 className="font-semibold text-xl text-gray-900">Shelf</h3>
                  <p className="text-sm text-gray-600 mt-2 leading-relaxed">Kéo thả tệp tin tạm thời, truy cập nhanh mọi lúc.</p>
                </div>
              </div>

              {/* Focus Pomodoro */}
              <div className="glass-panel rounded-2xl p-8 flex flex-col items-start gap-6 hover:-translate-y-1 transition-transform duration-300">
                <div className="relative w-full flex items-center gap-4">
                  <div className="relative h-16 w-16 flex items-center justify-center shrink-0">
                    <svg className="absolute inset-0 w-full h-full" viewBox="0 0 48 48">
                      <circle className="text-gray-200" cx="24" cy="24" fill="transparent" r="22" stroke="currentColor" strokeWidth="4"></circle>
                      <circle 
                        className="text-green-500 progress-ring__circle" 
                        cx="24" 
                        cy="24" 
                        fill="transparent" 
                        r="22" 
                        stroke="currentColor" 
                        strokeWidth="4"
                        style={{
                          strokeDasharray: `${circleCircumference} ${circleCircumference}`,
                          strokeDashoffset: strokeDashoffset
                        }}
                      ></circle>
                    </svg>
                    <button 
                      type="button"
                      className="h-10 w-10 rounded-full bg-white flex items-center justify-center text-green-600 border border-gray-100 z-10 pulse-btn hover:bg-gray-50 transition-colors shadow-sm"
                      onClick={() => setActive(!active)}
                      title="Pause/Resume"
                    >
                      <span className="material-symbols-outlined" style={{ fontSize: '20px' }}>
                        {active ? 'pause' : 'play_arrow'}
                      </span>
                    </button>
                  </div>
                  <div className="text-green-600 font-bold text-2xl timer-glow" style={{ fontVariantNumeric: 'tabular-nums' }}>
                    {formattedTime}
                  </div>
                </div>
                <div className="text-left">
                  <h3 className="font-semibold text-xl text-gray-900">Focus</h3>
                  <p className="text-sm text-gray-600 mt-2 leading-relaxed">Bộ đếm ngược Pomodoro ngay trên thanh menu.</p>
                </div>
              </div>

              {/* Media Control */}
              <div className="glass-panel rounded-2xl p-8 flex flex-col items-start gap-6 hover:-translate-y-1 transition-transform duration-300">
                <div className="h-14 w-14 rounded-full bg-yellow-50 flex items-center justify-center text-yellow-600 border border-yellow-100 shrink-0">
                  <div className="flex items-end gap-[3px] h-6">
                    <div className="sound-bar bar-1"></div>
                    <div className="sound-bar bar-2"></div>
                    <div className="sound-bar bar-3"></div>
                    <div className="sound-bar bar-4"></div>
                  </div>
                </div>
                <div className="text-left">
                  <h3 className="font-semibold text-xl text-gray-900">Media</h3>
                  <p className="text-sm text-gray-600 mt-2 leading-relaxed">Điều khiển nhạc với sóng âm trực quan.</p>
                </div>
              </div>

              {/* Gemini AI */}
              <div className="glass-panel rounded-2xl p-8 flex flex-col items-start gap-6 hover:-translate-y-1 transition-transform duration-300 relative overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-br from-blue-50 to-transparent z-0"></div>
                <div className="h-14 w-14 rounded-full bg-blue-100 flex items-center justify-center text-blue-700 border border-blue-200 z-10 shrink-0">
                  <span className="material-symbols-outlined animate-shimmer" style={{ fontSize: '28px' }}>auto_awesome</span>
                </div>
                <div className="text-left z-10">
                  <h3 className="font-semibold text-xl text-gray-900">Gemini AI</h3>
                  <p className="text-sm text-gray-600 mt-2 leading-relaxed">Trợ lý AI đồng hành cùng bạn mọi lúc.</p>
                </div>
              </div>
            </div>
          </section>

          {/* Leaderboard Section */}
          <section id="leaderboard" className="snap-section pt-8 flex flex-col justify-center">
            
            {/* Header / Intro */}
            <div className="text-center mb-8">
              <div className="flex flex-col md:flex-row items-center md:justify-between gap-6 max-w-[1440px] mx-auto px-6 text-center md:text-left">
                <div>
                  <h2 className="text-3xl md:text-5xl font-extrabold text-[#141b2b] tracking-tight">
                    Bảng xếp hạng Tập trung
                  </h2>
                  <p className="text-sm md:text-base text-[#434654] max-w-xl mt-2 leading-relaxed">
                    Vinh danh những người dùng kiên trì nhất trong cộng đồng Notch.
                  </p>
                </div>
 
                {/* Window Tabs Filter */}
                <div className="glass-panel p-1 rounded-full inline-flex gap-1 shrink-0 mt-3 md:mt-0">
                  <button 
                    onClick={() => setWindowState('week')} 
                    className={`font-semibold text-[13px] px-6 py-2.5 rounded-full transition-all duration-300 ${windowState === 'week' ? 'bg-[#dce2f7] text-[#141b2b] shadow-sm' : 'text-[#434654] hover:text-[#141b2b]'}`}
                  >
                    Tuần này
                  </button>
                  <button 
                    onClick={() => setWindowState('all')} 
                    className={`font-semibold text-[13px] px-6 py-2.5 rounded-full transition-all duration-300 ${windowState === 'all' ? 'bg-[#dce2f7] text-[#141b2b] shadow-sm' : 'text-[#434654] hover:text-[#141b2b]'}`}
                  >
                    Tất cả thời gian
                  </button>
                </div>
              </div>
            </div>
 
            {/* Content Grid */}
            <div className="leaderboard-grid-container max-w-[1440px] mx-auto w-full px-6 mt-6">
              
              {/* Left Column: Podium (Top 3 Users) */}
              <div className="flex flex-col justify-center h-full">
                <div className="grid grid-cols-3 gap-6 items-end w-full">
                  
                  {/* Rank 2 (Silver) */}
                  {top2 && (
                    <div className="glass-panel rounded-2xl p-6 text-center flex flex-col items-center relative hover:-translate-y-1 transition-all duration-300 shadow-[0_4px_20px_0_rgba(0,0,0,0.02)] justify-between min-h-[310px] border-t-2 border-slate-300/30 bg-gradient-to-b from-slate-100/20 to-white/80 pb-6">
                      <div className="absolute -top-4 left-1/2 -translate-x-1/2 bg-gradient-to-r from-slate-300 to-slate-400 text-white font-extrabold text-[13px] w-10 h-10 rounded-full flex items-center justify-center border-2 border-white shadow-md">
                        2
                      </div>
                      <div className="relative mt-2">
                        <div className="w-24 h-24 rounded-full overflow-hidden border-2 border-slate-200 p-0.5 bg-white shadow-inner">
                          {top2.avatar_url ? (
                            <img src={top2.avatar_url} alt={top2.display_name} className="w-full h-full rounded-full object-cover" />
                          ) : (
                            <div className="w-full h-full rounded-full bg-slate-100 text-[#141b2b] flex items-center justify-center font-bold text-base">
                              {initials(top2.display_name)}
                            </div>
                          )}
                        </div>
                      </div>
                      <div className="mt-2">
                        <h3 className="font-bold text-base text-[#141b2b] truncate max-w-[140px]">{top2.display_name}</h3>
                        <p className="text-xs text-gray-500 truncate max-w-[140px]">{getOccupation(top2.user_id, 2)}</p>
                      </div>
                      <div className="mt-2 text-center w-full">
                        <div className="text-base font-extrabold text-[#003fb1]">{formatFocusTime(top2.focus_seconds)}</div>
                        <div className="text-[11px] text-gray-400 uppercase tracking-wider font-semibold">Thời gian</div>
                      </div>
                    </div>
                  )}
 
                  {/* Rank 1 (Gold) */}
                  {top1 && (
                    <div className="glass-panel rounded-2xl p-7 text-center flex flex-col items-center relative hover:-translate-y-1.5 transition-all duration-300 shadow-[0_12px_30px_0_rgba(250,204,21,0.08)] border-t-4 border-amber-400/50 bg-gradient-to-b from-amber-50/30 to-white/90 z-10 min-h-[350px] pb-7">
                      <div className="absolute -top-5 left-1/2 -translate-x-1/2 bg-gradient-to-r from-amber-400 to-yellow-500 text-white font-extrabold w-11 h-11 rounded-full flex items-center justify-center border-2 border-white shadow-lg">
                        <span className="material-symbols-outlined fill text-[22px]">trophy</span>
                      </div>
                      <div className="relative mt-2">
                        <div className="w-28 h-28 rounded-full overflow-hidden border-2 border-amber-300 p-0.5 bg-white shadow-md ring-4 ring-amber-400/20">
                          {top1.avatar_url ? (
                            <img src={top1.avatar_url} alt={top1.display_name} className="w-full h-full rounded-full object-cover" />
                          ) : (
                            <div className="w-full h-full rounded-full bg-[#dce2f7] text-[#141b2b] flex items-center justify-center font-bold text-lg">
                              {initials(top1.display_name)}
                            </div>
                          )}
                        </div>
                      </div>
                      <div className="mt-2">
                        <h3 className="font-bold text-lg text-[#141b2b] truncate max-w-[150px]">{top1.display_name}</h3>
                        <p className="text-xs text-amber-700 font-semibold truncate max-w-[150px]">{getOccupation(top1.user_id, 1)}</p>
                      </div>
                      <div className="mt-2 text-center w-full">
                        <div className="text-lg font-black text-amber-600">{formatFocusTime(top1.focus_seconds)}</div>
                        <div className="text-[11px] text-amber-500 uppercase tracking-wider font-bold">Tổng tập trung</div>
                      </div>
                    </div>
                  )}
 
                  {/* Rank 3 (Bronze) */}
                  {top3 && (
                    <div className="glass-panel rounded-2xl p-6 text-center flex flex-col items-center relative hover:-translate-y-1 transition-all duration-300 shadow-[0_4px_20px_0_rgba(0,0,0,0.02)] justify-between min-h-[295px] border-t-2 border-orange-400/30 bg-gradient-to-b from-orange-100/20 to-white/80 pb-6">
                      <div className="absolute -top-4 left-1/2 -translate-x-1/2 bg-gradient-to-r from-orange-400 to-orange-500 text-white font-extrabold text-[13px] w-10 h-10 rounded-full flex items-center justify-center border-2 border-white shadow-md">
                        3
                      </div>
                      <div className="relative mt-2">
                        <div className="w-24 h-24 rounded-full overflow-hidden border-2 border-orange-200 p-0.5 bg-white shadow-inner">
                          {top3.avatar_url ? (
                            <img src={top3.avatar_url} alt={top3.display_name} className="w-full h-full rounded-full object-cover" />
                          ) : (
                            <div className="w-full h-full rounded-full bg-orange-50 text-[#141b2b] flex items-center justify-center font-bold text-base">
                              {initials(top3.display_name)}
                            </div>
                          )}
                        </div>
                      </div>
                      <div className="mt-2">
                        <h3 className="font-bold text-base text-[#141b2b] truncate max-w-[140px]">{top3.display_name}</h3>
                        <p className="text-xs text-gray-500 truncate max-w-[140px]">{getOccupation(top3.user_id, 3)}</p>
                      </div>
                      <div className="mt-2 text-center w-full">
                        <div className="text-base font-extrabold text-orange-700">{formatFocusTime(top3.focus_seconds)}</div>
                        <div className="text-[11px] text-gray-400 uppercase tracking-wider font-semibold">Thời gian</div>
                      </div>
                    </div>
                  )}
 
                </div>
              </div>
 
              {/* Right Column: Rankings Table Dashboard */}
              <div>
                <div className="glass-panel rounded-2xl overflow-hidden shadow-sm">
                  
                  {/* Dashboard Table Header */}
                  <div className="grid grid-cols-12 gap-2 p-5 border-b border-black/5 bg-white/50 text-[13px] font-semibold tracking-wider text-[#434654] uppercase">
                    <div className="col-span-2 text-center">Hạng</div>
                    <div className="col-span-6">Thành viên</div>
                    <div className="col-span-4 text-right">Tập trung</div>
                  </div>
 
                  <div className="flex flex-col">
                    {/* Logged in User Row (Highlight) */}
                    {meEntry && (
                      <div className="grid grid-cols-12 gap-2 p-5 items-center border-b border-[#003fb1]/20 bg-[#003fb1]/5 hover:bg-[#003fb1]/10 transition-colors">
                        <div className="col-span-2 text-center font-black text-lg text-[#003fb1]">
                          {meEntry.rank}
                        </div>
                        <div className="col-span-6 flex items-center gap-4">
                          <div className="w-14 h-14 rounded-full overflow-hidden bg-[#e9edff] border border-[#003fb1]/20 flex items-center justify-center font-bold text-sm text-[#003fb1] shrink-0">
                            {meEntry.avatar_url ? (
                              <img src={meEntry.avatar_url} alt={meEntry.display_name} className="h-full w-full object-cover" />
                            ) : (
                              initials(meEntry.display_name)
                            )}
                          </div>
                          <div className="min-w-0">
                            <div className="font-semibold text-base text-gray-900 flex items-center gap-2">
                              Bạn <span className="bg-[#003fb1]/10 text-[#003fb1] px-2 py-0.5 rounded text-[11px] font-bold border border-[#003fb1]/20 shrink-0">Current</span>
                            </div>
                            <div className="text-xs text-gray-500 truncate">{getOccupation(meEntry.user_id, meEntry.rank)}</div>
                          </div>
                        </div>
                        <div className="col-span-4 text-right flex flex-col justify-center items-end">
                          <div className="text-base font-black text-[#003fb1]">{formatFocusTime(meEntry.focus_seconds)}</div>
                          <div className="text-xs text-gray-500 mt-0.5">{meEntry.session_count} phiên</div>
                        </div>
                      </div>
                    )}
 
                    {/* Standard rankings list items */}
                    {restList.map((entry) => (
                      <div 
                        key={entry.user_id} 
                        className="grid grid-cols-12 gap-2 p-5 items-center border-b border-black/5 hover:bg-white/40 transition-colors"
                      >
                        <div className="col-span-2 text-center text-base font-semibold text-[#434654]">
                          {entry.rank}
                        </div>
                        <div className="col-span-6 flex items-center gap-4">
                          <div className="w-14 h-14 rounded-full overflow-hidden bg-[#e9edff] flex items-center justify-center font-bold text-sm text-gray-700 shrink-0">
                            {entry.avatar_url ? (
                              <img src={entry.avatar_url} alt={entry.display_name} className="h-full w-full object-cover" />
                            ) : (
                              initials(entry.display_name)
                            )}
                          </div>
                          <div className="min-w-0">
                            <div className="font-semibold text-base text-gray-900 truncate">{entry.display_name}</div>
                            <div className="text-xs text-gray-500 truncate">{getOccupation(entry.user_id, entry.rank)}</div>
                          </div>
                        </div>
                        <div className="col-span-4 text-right flex flex-col justify-center items-end">
                          <div className="text-base font-semibold text-gray-900">{formatFocusTime(entry.focus_seconds)}</div>
                          <div className="text-xs text-gray-500 mt-0.5">{entry.session_count} phiên</div>
                        </div>
                      </div>
                    ))}
                  </div>
 
                  {/* Load More Button */}
                  {displayedLeaderboard.filter(e => e.rank > 3).length > limit && (
                    <div className="p-4 text-center bg-white/30 border-t border-black/5">
                      <button 
                        onClick={() => setLimit(l => l + 5)}
                        className="font-semibold text-sm text-[#003fb1] hover:text-[#002870] transition-colors flex items-center justify-center gap-0.5 mx-auto"
                      >
                        Tải thêm <span className="material-symbols-outlined text-[18px]">expand_more</span>
                      </button>
                    </div>
                  )}
 
                </div>
              </div>
 
            </div>

          </section>

          {/* Downloads Section */}
          <section id="download" className="snap-section space-y-12 pt-8">
            <div className="text-center space-y-4">
              <span className="bg-[#003fb1]/10 text-[#003fb1] rounded-full px-4 py-1.5 text-xs font-semibold border border-[#003fb1]/20 inline-block">
                Cài đặt
              </span>
              <h2 className="text-3xl md:text-5xl font-bold text-[#141b2b] tracking-tight">Tải ứng dụng Notch</h2>
              <p className="text-base text-[#434654] max-w-xl mx-auto leading-relaxed">
                Hỗ trợ đầy đủ macOS Sonoma (14.0) trở lên. Trải nghiệm tập trung Pomodoro và điều khiển media đỉnh cao.
              </p>
            </div>

            {/* Downloads Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-5xl mx-auto">
              
              {/* macOS App Card */}
              <div className="glass-panel rounded-3xl p-10 flex flex-col justify-between border border-black/5 hover:-translate-y-1 transition-all duration-300">
                <div className="space-y-4">
                  <div className="text-[#003fb1] flex items-center gap-3">
                    <span className="material-symbols-outlined text-3xl">download</span>
                    <span className="bg-[#003fb1]/10 text-[#003fb1] border border-[#003fb1]/20 text-[10px] font-bold px-2 py-0.5 rounded-full">Khuyên dùng</span>
                  </div>
                  <h3 className="text-xl font-bold text-gray-900">Notch cho macOS</h3>
                  <p className="text-sm text-[#434654] leading-relaxed">
                    Bản cài đặt Universal chính thức hỗ trợ kiến trúc Apple Silicon (M1/M2/M3/M4) và chip Intel. Đóng gói bảo mật dưới dạng tệp tin DMG tiêu chuẩn.
                  </p>
                </div>
                
                <a 
                  href="/dist/Notch.dmg" 
                  download 
                  className="mt-8 w-full py-3.5 rounded-xl bg-[#003fb1] font-semibold text-xs text-white hover:bg-opacity-90 active:scale-95 transition-all text-center flex items-center justify-center gap-2 shadow-md"
                >
                  <span className="material-symbols-outlined text-sm">download</span>
                  Tải xuống .DMG (Universal)
                </a>
              </div>

              {/* Chrome Extension Card */}
              <div className="glass-panel rounded-3xl p-10 flex flex-col justify-between border border-black/5 hover:-translate-y-1 transition-all duration-300">
                <div className="space-y-4">
                  <div className="text-purple-600 flex items-center gap-3">
                    <span className="material-symbols-outlined text-3xl">language</span>
                    <span className="bg-purple-100 text-purple-700 border border-purple-200 text-[10px] font-bold px-2 py-0.5 rounded-full">Bổ trợ</span>
                  </div>
                  <h3 className="text-xl font-bold text-gray-900">Chrome Focus Blocker</h3>
                  <p className="text-sm text-[#434654] leading-relaxed">
                    Tiện ích mở rộng giúp theo dõi và chặn các trang web gây xao nhãng tự động, đồng bộ trực tiếp khi bật Pomodoro trên Notch app.
                  </p>
                </div>
                
                <Link 
                  to="/"
                  hash="help"
                  className="mt-8 w-full py-3.5 rounded-xl border border-gray-300 font-semibold text-xs text-gray-900 hover:bg-gray-50 active:scale-95 transition-all text-center block"
                >
                  Xem hướng dẫn cài đặt
                </Link>
              </div>

            </div>

            {/* Security / Gatekeeper Note */}
            <div className="glass-panel rounded-3xl p-10 max-w-5xl mx-auto border border-orange-200/50 bg-orange-50/10">
              <h3 className="text-base font-bold text-gray-900 flex items-center gap-2 mb-3">
                <span className="material-symbols-outlined text-orange-500">security_update_warning</span>
                Lưu ý Gatekeeper
              </h3>
              <p className="text-xs text-[#434654] leading-relaxed">
                Do Notch cần tương tác trực tiếp với menu bar và các luồng âm thanh hệ thống để điều khiển media, nếu hệ điều hành hiển thị cảnh báo "nhà phát triển không xác định" khi mở file DMG:
                <br /><br />
                1. Mở cài đặt hệ thống: <strong>System Settings</strong> &gt; <strong>Privacy & Security</strong>.
                <br />
                2. Cuộn xuống phần Security, chọn <strong>Open Anyway</strong> để cấp phép và khởi chạy Notch bình thường.
              </p>
            </div>
          </section>

          {/* Pricing Section */}
          <section id="pricing" className="snap-section space-y-16">
            <div className="text-center space-y-6">
              <h2 className="text-4xl md:text-6xl font-extrabold text-[#141b2b]">Đầu tư cho sự tập trung</h2>
              <p className="text-lg text-[#434654] leading-relaxed">Chọn gói phù hợp với nhu cầu công việc của bạn.</p>
            </div>
            
            <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-6xl mx-auto">
              
              {/* Free Tier */}
              <div className="glass-panel rounded-3xl p-12 flex flex-col justify-between border border-black/5">
                <div>
                  <h3 className="font-bold text-2xl text-gray-900">Free</h3>
                  <div className="mt-6 flex items-baseline gap-1.5">
                    <span className="text-5xl font-black text-gray-900">0đ</span>
                    <span className="text-sm text-gray-600">/ mãi mãi</span>
                  </div>
                  <p className="text-sm text-gray-600 mt-2">Dành cho nhu cầu cơ bản</p>
                  
                  <ul className="mt-10 space-y-5">
                    {freeFeatures.length > 0 ? freeFeatures.map(f => (
                      <li key={f.key} className="flex items-center gap-4 text-sm font-medium text-gray-700">
                        <span className="material-symbols-outlined text-blue-600 text-sm animate-bobbing" style={{ fontSize: '18px' }}>check_circle</span>
                        {f.name}
                      </li>
                    )) : (
                      <>
                        <li className="flex items-center gap-4 text-sm font-medium text-gray-700">
                          <span className="material-symbols-outlined text-blue-600 text-sm animate-bobbing" style={{ fontSize: '18px' }}>check_circle</span>
                          Quản lý tệp tin cơ bản
                        </li>
                        <li className="flex items-center gap-4 text-sm font-medium text-gray-700">
                          <span className="material-symbols-outlined text-blue-600 text-sm animate-bobbing" style={{ fontSize: '18px' }}>check_circle</span>
                          Bộ đếm Pomodoro
                        </li>
                        <li className="flex items-center gap-4 text-sm font-medium text-gray-700">
                          <span className="material-symbols-outlined text-blue-600 text-sm animate-bobbing" style={{ fontSize: '18px' }}>check_circle</span>
                          Điều khiển Media
                        </li>
                      </>
                    )}
                  </ul>
                </div>
                <button 
                  type="button" 
                  className="mt-12 w-full py-4 rounded-xl border border-gray-300 font-bold text-sm text-gray-900 hover:bg-gray-50 transition-colors"
                >
                  Đang sử dụng
                </button>
              </div>

              {/* Pro Tier */}
              <div className="glass-panel rounded-3xl p-12 flex flex-col justify-between relative overflow-hidden ring-1 ring-yellow-400/50">
                <div className="absolute top-0 right-0 bg-[#facc15] text-[#241a00] font-bold text-xs px-4 py-1.5 rounded-bl-lg">
                  PHỔ BIẾN
                </div>
                <div className="absolute inset-0 bg-gradient-to-b from-yellow-50/20 to-transparent z-0 pointer-events-none"></div>
                
                <div className="z-10">
                  <h3 className="font-bold text-2xl text-yellow-600">Pro</h3>
                  <div className="mt-6 flex items-baseline gap-1.5">
                    <span className="text-5xl font-black text-gray-900">99.000đ</span>
                    <span className="text-sm text-gray-600">/ trọn đời</span>
                  </div>
                  <p className="text-sm text-gray-600 mt-2">Mở khóa toàn bộ sức mạnh</p>
                  
                  <ul className="mt-10 space-y-5">
                    <li className="flex items-center gap-4 text-sm font-medium text-gray-700">
                      <span className="material-symbols-outlined text-yellow-500 text-sm" style={{ fontSize: '18px' }}>check_circle</span>
                      Tất cả tính năng Free
                    </li>
                    {proFeatures.length > 0 ? proFeatures.map(f => (
                      <li key={f.key} className="flex items-center gap-4 text-sm font-medium text-gray-700">
                        <span className="material-symbols-outlined text-yellow-500 text-sm" style={{ fontSize: '18px' }}>check_circle</span>
                        {f.name}
                      </li>
                    )) : (
                      <>
                        <li className="flex items-center gap-4 text-sm font-medium text-gray-700">
                          <span className="material-symbols-outlined text-yellow-500 text-sm" style={{ fontSize: '18px' }}>check_circle</span>
                          Tích hợp Gemini AI
                        </li>
                        <li className="flex items-center gap-4 text-sm font-medium text-gray-700">
                          <span className="material-symbols-outlined text-yellow-500 text-sm" style={{ fontSize: '18px' }}>check_circle</span>
                          Đồng bộ thiết bị vô hạn
                        </li>
                        <li className="flex items-center gap-4 text-sm font-medium text-gray-700">
                          <span className="material-symbols-outlined text-yellow-500 text-sm" style={{ fontSize: '18px' }}>check_circle</span>
                          Tùy chỉnh giao diện nâng cao
                        </li>
                      </>
                    )}
                  </ul>
                </div>
                
                <button
                  type="button"
                  onClick={handleUpgrade}
                  disabled={isCheckoutLoading}
                  className="mt-12 w-full py-4 rounded-xl bg-[#facc15] font-bold text-sm text-[#241a00] hover:bg-yellow-500 active:scale-95 transition-all shadow-sm z-10 text-center flex items-center justify-center gap-2"
                >
                  {isCheckoutLoading ? (
                    <>
                      <svg className="animate-spin h-4 w-4 text-[#241a00]" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Đang kết nối VNPAY...
                    </>
                  ) : (
                    'Nâng cấp lên Pro'
                  )}
                </button>
                {checkoutError && (
                  <div className="mt-4 text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg p-3 text-left">
                    {checkoutError}
                  </div>
                )}
              </div>

            </div>
          </section>

          {/* Support / FAQ Section */}
          <section id="help" className="snap-section space-y-16 pt-8">
            <div className="text-center space-y-6 max-w-4xl mx-auto">
              <h2 className="text-4xl md:text-6xl font-black text-[#141b2b] tracking-tight leading-tight">
                Hỗ trợ & Trợ giúp
              </h2>
              <p className="text-base md:text-lg text-[#434654] font-medium leading-relaxed">
                Tìm câu trả lời cho các vấn đề thường gặp hoặc liên hệ trực tiếp với bộ phận hỗ trợ kỹ thuật của chúng tôi.
              </p>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-10 items-start max-w-[1440px] mx-auto">
              {/* FAQs Accordion */}
              <div className="lg:col-span-2 space-y-5">
                {faqs.map((faq, index) => {
                  const isExpanded = expandedFaqIndex === index
                  return (
                    <div 
                      key={index} 
                      className={`glass-panel p-8 rounded-2xl cursor-pointer transition-all duration-300 border ${
                        isExpanded 
                          ? 'bg-[#003fb1]/5 border-[#003fb1]/20 shadow-sm' 
                          : 'bg-white/60 border-black/5 hover:-translate-y-0.5'
                      }`}
                      onClick={() => setExpandedFaqIndex(isExpanded ? null : index)}
                    >
                      <div className="flex items-center justify-between gap-4 w-100">
                        <h3 className="font-bold text-base md:text-lg text-gray-900 flex items-center gap-3">
                          <HelpCircle size={22} className="text-[#003fb1] flex-shrink-0" />
                          {faq.q}
                        </h3>
                        <ChevronDown 
                          size={22} 
                          className={`text-[#434654] transition-transform duration-300 ${
                            isExpanded ? 'rotate-180' : ''
                          }`}
                        />
                      </div>
                      <div 
                        style={{ 
                          maxHeight: isExpanded ? '200px' : '0px', 
                          overflow: 'hidden', 
                          transition: 'all 0.25s cubic-bezier(0.4, 0, 0.2, 1)',
                          opacity: isExpanded ? 1 : 0
                        }}
                      >
                        <p className="text-sm md:text-base text-[#434654] leading-relaxed pt-4 font-medium border-t border-black/5 mt-4">
                          {faq.a}
                        </p>
                      </div>
                    </div>
                  )
                })}
              </div>

              {/* Contact Card */}
              <div className="lg:col-span-1 glass-panel p-10 rounded-3xl text-center space-y-6">
                <div className="space-y-3">
                  <h3 className="font-bold text-gray-900 text-xl">
                    Không tìm thấy câu trả lời?
                  </h3>
                  <p className="text-sm text-[#434654] font-medium leading-relaxed">
                    Liên hệ trực tiếp với chúng tôi qua các kênh hỗ trợ kỹ thuật chính thức.
                  </p>
                </div>
                
                <div className="flex flex-col gap-4">
                  <a 
                    href="mailto:support@notch.app" 
                    className="bg-white hover:bg-gray-50 border border-black/5 shadow-sm text-[#434654] font-semibold text-sm py-4 rounded-xl flex items-center justify-center gap-2 transition-all active:scale-95 text-decoration-none"
                  >
                    <Mail size={18} className="text-[#003fb1]" />
                    <span>support@notch.app</span>
                  </a>
                  <a 
                    href="https://github.com/ProMeX04/notch-app/issues" 
                    target="_blank" 
                    rel="noopener noreferrer" 
                    className="bg-white hover:bg-gray-50 border border-black/5 shadow-sm text-[#434654] font-semibold text-sm py-4 rounded-xl flex items-center justify-center gap-2 transition-all active:scale-95 text-decoration-none"
                  >
                    <MessageSquare size={18} className="text-[#003fb1]" />
                    <span>Báo lỗi trên GitHub</span>
                  </a>
                </div>
              </div>
            </div>

            {/* Footer */}
            <footer className="w-full py-10 px-6 flex flex-col md:flex-row justify-between items-center max-w-[1440px] mx-auto border-t border-black/5 mt-20 z-10">
              <div className="font-bold text-xl text-gray-900 mb-4 md:mb-0">
                Notch
              </div>
              <div className="text-sm text-gray-400 order-3 md:order-2 mt-4 md:mt-0 text-center md:text-left">
                © 2024 Notch Productivity. Built for focus.
              </div>
              <nav className="flex gap-6 order-2 md:order-3">
                <a className="text-sm text-gray-500 hover:text-[#003fb1] transition-all" href="#">Privacy</a>
                <a className="text-sm text-gray-500 hover:text-[#003fb1] transition-all" href="#">Terms</a>
                <a className="text-sm text-gray-500 hover:text-[#003fb1] transition-all" href="#">Twitter</a>
                <a className="text-sm text-gray-500 hover:text-[#003fb1] transition-all" href="#">GitHub</a>
              </nav>
            </footer>
          </section>

        </main>
      </div>
    </PageShell>
  )
}
