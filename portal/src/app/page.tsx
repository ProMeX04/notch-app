'use client';

import Link from 'next/link';
import {
  ArrowRight,
  BrainCircuit,
  Clock3,
  FolderKanban,
  PlayCircle,
  Radio,
  Sparkles,
  Waves,
  Zap,
  BookOpen,
  MousePointer2,
  Music,
} from 'lucide-react';
import { PortalLogo } from '@/components/portal/PortalLogo';

const featureCards = [
  {
    icon: Clock3,
    title: 'Pomodoro focus ngay trong notch',
    description:
      'Chạy preset focus, break và nhịp làm việc sâu mà không phải mở thêm một cửa sổ lớn chiếm màn hình.',
  },
  {
    icon: FolderKanban,
    title: 'Drag & drop shelf cho file và link',
    description:
      'Kéo thả nhanh tài liệu, liên kết hoặc nội dung vào shelf để gom mọi thứ cho phiên làm việc hiện tại.',
  },
  {
    icon: Waves,
    title: 'Media controls gọn và tiện',
    description:
      'Đổi bài, xem trạng thái phát và thao tác media trực tiếp trong vùng notch thay vì chuyển app liên tục.',
  },
  {
    icon: BrainCircuit,
    title: 'Gemini Live khi bạn cần trợ lực',
    description:
      'Mở trợ lý AI theo ngữ cảnh, nói chuyện nhanh hơn và giữ workflow liền mạch trong khi vẫn tập trung.',
  },
];

const storyCards = [
  {
    icon: BookOpen,
    title: 'Cho học tập và deep work',
    points: [
      'Bật focus timer, giữ nhịp học rõ ràng và không phá vỡ trạng thái tập trung.',
      'Nhắc nghỉ ngắn đúng lúc thay vì để mọi việc kéo dài quá đà.',
      'Tất cả diễn ra ở một vùng nhỏ, quen mắt và ít gây xao nhãng.',
    ],
  },
  {
    icon: MousePointer2,
    title: 'Cho lưu nhanh và kéo thả',
    points: [
      'Thả file, URL hoặc nội dung vào shelf rồi quay lại việc chính ngay.',
      'Giảm số lượng cửa sổ phụ và những lần mò lại tài liệu vừa dùng.',
      'Phù hợp với người hay research, viết nội dung hoặc làm việc đa nguồn.',
    ],
  },
  {
    icon: Music,
    title: 'Cho media và điều hướng ngữ cảnh',
    points: [
      'Kiểm soát nhạc và phát lại nội dung mà không rời ứng dụng hiện tại.',
      'Giữ trạng thái làm việc liền mạch hơn khi đang code, viết hoặc thuyết trình.',
      'Tận dụng vùng notch như một lớp điều khiển tự nhiên trên macOS.',
    ],
  },
];

const lightReasons = [
  {
    icon: Zap,
    title: 'Lightweight menu bar app',
    points: [
      'Thiết kế theo hướng utility nhỏ gọn thay vì dashboard nhiều lớp.',
      'Tập trung vào thao tác nhanh, ít bước và ít gây nặng cảm giác sử dụng.',
    ],
  },
  {
    icon: Radio,
    title: 'Tối ưu hiển thị và cache hợp lý',
    points: [
      'Các phần như shelf và thumbnail được tổ chức để giảm lãng phí tài nguyên không cần thiết.',
      'Ưu tiên cảm giác phản hồi mượt trước khi thêm hiệu ứng nặng.',
    ],
  },
  {
    icon: Sparkles,
    title: 'Đủ đẹp nhưng vẫn tiết chế',
    points: [
      'Animation dùng để dẫn mắt và tăng cảm giác cao cấp, không biến web thành phần trình diễn nặng.',
      'Thông điệp về RAM và hiệu năng được giữ trung thực, không dùng benchmark chưa xác nhận.',
    ],
  },
];

const marqueeItems = [
  'Pomodoro focus',
  'Drag & drop shelf',
  'Media controls',
  'Gemini Live',
  'Menu bar utility',
  'Tối ưu bộ nhớ',
  'macOS notch workflow',
];

export default function Home() {
  return (
    <main className="landing-page">
      <nav className="landing-nav">
        <div className="landing-nav-inner portal-card">
          <PortalLogo caption="Productivity companion cho macOS" />
          <div className="landing-nav-links">
            <Link href="#tinh-nang">Tính năng</Link>
            <Link href="/pricing">Bảng giá</Link>
            <Link href="/pro">Tài khoản</Link>
          </div>
          <div className="landing-nav-actions">
            <Link href="/login" className="portal-button-ghost">
              Đăng nhập
            </Link>
            <Link href="/signup" className="portal-button-secondary">
              Tạo tài khoản
            </Link>
          </div>
        </div>
      </nav>

      <div className="portal-shell">
        <section className="landing-hero">
          <div className="landing-hero-copy">
            <span className="portal-badge">
              <Sparkles size={14} />
              Thiết kế tối giản cho năng suất tối đa
            </span>
            <h1>Làm việc gọn, nhanh và cuốn hút trên macOS.</h1>
            <p>
              Notch mang các công cụ Pomodoro, Shelf kéo thả, Media controls và Gemini Live vào một lớp giao diện duy nhất ngay tại vùng notch của bạn.
            </p>

            <div className="landing-hero-actions">
              <Link href="/pricing" className="portal-button-secondary">
                Xem bảng giá
              </Link>
              <Link href="/signup" className="portal-button">
                Bắt đầu miễn phí
              </Link>
            </div>
          </div>

          <div id="demo" className="landing-hero-demo">
            <div className="portal-preview-window">
              <div className="portal-preview-video">
                <div className="portal-preview-play">
                  <PlayCircle size={32} />
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="tinh-nang" className="portal-section">
          <div className="portal-section-head">
            <span className="portal-badge">Tính năng nổi bật</span>
            <h2>Mọi công cụ bạn cần, ngay trong tầm mắt.</h2>
            <p>
              Tận dụng vùng notch để quản lý thời gian, tài liệu và phương tiện truyền thông mà không
              làm gián đoạn dòng chảy công việc của bạn.
            </p>
          </div>

          <div className="landing-feature-grid">
            {featureCards.map(({ icon: Icon, title, description }) => (
              <article key={title} className="landing-feature-card portal-card">
                <div className="landing-icon-wrap">
                  <Icon size={20} />
                </div>
                <h3>{title}</h3>
                <p>{description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="portal-section">
          <div className="portal-section-head">
            <span className="portal-badge portal-badge-warm">Theo ngữ cảnh sử dụng</span>
            <h2>Giải pháp linh hoạt cho mọi nhu cầu làm việc.</h2>
            <p>
              Dù bạn là học sinh, lập trình viên hay nhà sáng tạo nội dung, Notch giúp bạn duy trì
              sự tập trung và tối ưu hóa thao tác hàng ngày.
            </p>
          </div>

          <div className="landing-story-grid">
            {storyCards.map((card) => (
              <article key={card.title} className="landing-story-card portal-card">
                <div className="landing-icon-wrap">
                  <card.icon size={20} />
                </div>
                <h3>{card.title}</h3>
                <ul>
                  {card.points.map((point) => (
                    <li key={point}>{point}</li>
                  ))}
                </ul>
              </article>
            ))}
          </div>
        </section>

        <section id="toi-uu" className="portal-section">
          <div className="portal-section-head">
            <span className="portal-badge">Vì sao Notch vẫn nhẹ</span>
            <h2>Nhẹ nhàng, mượt mà và hoàn toàn tin cậy.</h2>
            <p>
              Notch được xây dựng với sự ưu tiên tuyệt đối cho hiệu năng. Không tiêu tốn tài nguyên,
              không làm chậm hệ thống, chỉ đơn giản là giúp bạn làm việc hiệu quả hơn.
            </p>
          </div>

          <div className="landing-light-grid">
            {lightReasons.map(({ icon: Icon, title, points }) => (
              <article key={title} className="landing-light-card portal-card">
                <div className="landing-icon-wrap">
                  <Icon size={20} />
                </div>
                <h3>{title}</h3>
                <ul>
                  {points.map((point) => (
                    <li key={point}>{point}</li>
                  ))}
                </ul>
              </article>
            ))}
          </div>
        </section>

        <section className="portal-section">
          <div className="landing-cta-card portal-card">
            <div>
              <span className="portal-badge">Sẵn sàng dùng thử</span>
              <h3>Nâng tầm trải nghiệm macOS của bạn ngay hôm nay.</h3>
              <p>
                Tham gia cùng hàng nghìn người đang sử dụng Notch để làm việc thông minh hơn.
                Bắt đầu hoàn toàn miễn phí và cảm nhận sự khác biệt.
              </p>
            </div>
            <div className="landing-cta-actions">
              <Link href="/signup" className="portal-button">
                Tạo tài khoản
              </Link>
              <Link href="/pro" className="portal-button-secondary">
                Xem trang tài khoản
              </Link>
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
