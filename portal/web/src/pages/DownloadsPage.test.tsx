import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { DownloadsPage } from '@/pages/DownloadsPage'

// Mock dependencies
vi.mock('@/components/ui/PageShell', () => ({
  PageShell: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}))

describe('DownloadsPage', () => {
  it('renders macOS download information and client card', () => {
    render(<DownloadsPage />)

    expect(screen.getByText('Tải ứng dụng Notch')).toBeInTheDocument()
    expect(screen.getByText('Notch cho macOS')).toBeInTheDocument()
    expect(screen.getByText('Tải xuống .DMG (Universal)')).toBeInTheDocument()
  })

  it('renders Chrome Focus Blocker extension info', () => {
    render(<DownloadsPage />)

    expect(screen.getByText('Chrome Focus Blocker')).toBeInTheDocument()
    expect(screen.getByText('Xem hướng dẫn cài đặt')).toBeInTheDocument()
  })

  it('renders security and Gatekeeper instructions', () => {
    render(<DownloadsPage />)

    expect(screen.getByText('Lưu ý bảo mật Gatekeeper')).toBeInTheDocument()
  })
})
