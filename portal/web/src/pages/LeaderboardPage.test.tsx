import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

import { LeaderboardPage, formatFocusTime, type LeaderboardEntry } from '@/pages/LeaderboardPage'
import { apiClient } from '@/api/client'

// ─── Mocks ───────────────────────────────────────────────────────────────────

vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn(),
  },
}))

vi.mock('@/components/ui/PageShell', () => ({
  PageShell: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}))

vi.mock('lucide-react', () => ({
  Trophy: () => <span data-testid="trophy-icon" />,
  Crown: () => <span data-testid="crown-icon" />,
}))

// ─── Test helpers ─────────────────────────────────────────────────────────────

function makeEntry(rank: number): LeaderboardEntry {
  return {
    rank,
    user_id: `user-${rank}`,
    display_name: `User ${rank}`,
    focus_seconds: (10 - rank) * 3600,
    session_count: 10 - rank,
  }
}

function makeClient() {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false },
    },
  })
}

function renderWithClient(ui: React.ReactElement) {
  const client = makeClient()
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>)
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('formatFocusTime', () => {
  it('formats hours, minutes, and seconds', () => {
    expect(formatFocusTime(3600)).toBe('01:00:00')
    expect(formatFocusTime(5400)).toBe('01:30:00')
    expect(formatFocusTime(90)).toBe('00:01:30')
    expect(formatFocusTime(10)).toBe('00:00:10')
  })
})

describe('LeaderboardPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders heading and window switcher buttons', () => {
    // Never resolves to keep in loading state while we check static content
    vi.mocked(apiClient.get).mockReturnValue(new Promise(() => {}))

    renderWithClient(<LeaderboardPage />)

    expect(screen.getByRole('heading', { name: 'Bảng xếp hạng Focus' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Tuần này' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Tất cả thời gian' })).toBeInTheDocument()
  })

  it('shows loading state while fetching', () => {
    vi.mocked(apiClient.get).mockReturnValue(new Promise(() => {}))

    renderWithClient(<LeaderboardPage />)

    expect(screen.getByText('Đang tải...')).toBeInTheDocument()
  })

  it('renders podium and rank table when data has 5+ entries', async () => {
    const entries = [1, 2, 3, 4, 5].map(makeEntry)

    vi.mocked(apiClient.get).mockResolvedValue({
      data: { window: 'week', leaderboard: entries },
    })

    renderWithClient(<LeaderboardPage />)

    // Crown for 1st place in podium
    await waitFor(() => {
      expect(screen.getByTestId('crown-icon')).toBeInTheDocument()
    })

    // Podium shows top 3 display names
    expect(screen.getByText('User 1')).toBeInTheDocument()
    expect(screen.getByText('User 2')).toBeInTheDocument()
    expect(screen.getByText('User 3')).toBeInTheDocument()

    // Rank table shows entries 4+
    expect(screen.getByText('User 4')).toBeInTheDocument()
    expect(screen.getByText('User 5')).toBeInTheDocument()
  })

  it('renders empty state when leaderboard is empty', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({
      data: { window: 'week', leaderboard: [] },
    })

    renderWithClient(<LeaderboardPage />)

    await waitFor(() => {
      expect(screen.getByTestId('trophy-icon')).toBeInTheDocument()
    })

    expect(screen.getByText('Chưa có thứ hạng')).toBeInTheDocument()
  })

  it('renders error state when fetch fails', async () => {
    vi.mocked(apiClient.get).mockRejectedValue(new Error('Network error'))

    renderWithClient(<LeaderboardPage />)

    await waitFor(() => {
      expect(
        screen.getByText('Không thể tải bảng xếp hạng. Vui lòng thử lại.'),
      ).toBeInTheDocument()
    })
  })

  it('switching window tab re-fetches with correct param', async () => {
    const entries = [1, 2, 3].map(makeEntry)

    vi.mocked(apiClient.get).mockResolvedValue({
      data: { window: 'week', leaderboard: entries },
    })

    renderWithClient(<LeaderboardPage />)

    // Wait for initial week load
    await waitFor(() => {
      expect(screen.getByTestId('crown-icon')).toBeInTheDocument()
    })

    // Switch to all-time
    fireEvent.click(screen.getByRole('button', { name: 'Tất cả thời gian' }))

    await waitFor(() => {
      expect(vi.mocked(apiClient.get)).toHaveBeenCalledWith(
        expect.stringContaining('window=all'),
      )
    })
  })
})
