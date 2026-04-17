import {
  BrainCircuit,
  Clock3,
  FolderKanban,
  PlayCircle,
  Sparkles,
} from 'lucide-react';

type PortalAuthShowcaseProps = {
  eyebrow: string;
  title: string;
  description: string;
};

const showcasePoints = [
  {
    icon: Clock3,
    title: 'Focus gọn trong notch',
    description: 'Bắt đầu Pomodoro, đổi preset và giữ nhịp làm việc mà không che kín màn hình.',
  },
  {
    icon: FolderKanban,
    title: 'Drag & drop cực nhanh',
    description: 'Kéo file, link và nội dung vào shelf để giữ mọi thứ trong tầm tay.',
  },
  {
    icon: BrainCircuit,
    title: 'Gemini Live khi cần',
    description: 'Trao đổi nhanh, hỗ trợ thao tác và gọi AI theo ngữ cảnh làm việc.',
  },
];

export function PortalAuthShowcase({
  eyebrow,
  title,
  description,
}: PortalAuthShowcaseProps) {
  return (
    <aside className="portal-showcase portal-card">
      <div className="portal-showcase-copy">
        <span className="portal-badge portal-badge-warm">
          <Sparkles size={14} />
          {eyebrow}
        </span>
        <h2>{title}</h2>
        <p>{description}</p>
      </div>

      <div className="portal-preview-window portal-preview-window-auth">
        <div className="portal-preview-topbar">
          <span />
          <span />
          <span />
        </div>
        <div className="portal-preview-body">
          <div className="portal-preview-video">
            <div className="portal-preview-glow" />
            <button type="button" className="portal-preview-play" aria-label="Xem demo Notch">
              <PlayCircle size={20} />
            </button>
            <div className="portal-preview-caption">
              <strong>Demo workflow</strong>
              <small>Focus, shelf và media controls trong một nhịp làm việc.</small>
            </div>
          </div>
        </div>
      </div>

      <div className="portal-showcase-list">
        {showcasePoints.map(({ icon: Icon, title: itemTitle, description: itemDescription }) => (
          <div key={itemTitle} className="portal-showcase-item">
            <div className="portal-icon-pill">
              <Icon size={18} />
            </div>
            <div>
              <strong>{itemTitle}</strong>
              <p>{itemDescription}</p>
            </div>
          </div>
        ))}
      </div>
    </aside>
  );
}
