import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { VNPayReturnPage } from '@/pages/VNPayReturnPage'
import { apiClient } from '@/api/client'
import { launchPortalOAuthAppRedirect } from '@/auth/portal-oauth-client'

// Mock dependencies
vi.mock('@/api/client', () => ({
  apiClient: {
    get: vi.fn(),
  },
}))

vi.mock('@/auth/portal-oauth-client', () => ({
  launchPortalOAuthAppRedirect: vi.fn(),
}))

// Mock @tanstack/react-router
vi.mock('@tanstack/react-router', () => ({
  Link: ({ children, to }: { children: React.ReactNode; to: string }) => <a href={to}>{children}</a>,
}))

describe('VNPayReturnPage', () => {
  let queryClient: QueryClient

  beforeEach(() => {
    vi.clearAllMocks()
    queryClient = new QueryClient({
      defaultOptions: {
        queries: {
          retry: false,
        },
      },
    })
    // Mock window.location
    Object.defineProperty(window, 'location', {
      writable: true,
      value: {
        search: '?vnp_TxnRef=notchpro_1234&vnp_ResponseCode=00&vnp_SecureHash=hash',
      },
    })
  })

  it('renders loading state initially', async () => {
    vi.mocked(apiClient.get).mockReturnValue(new Promise(() => {})) // Never resolves to keep loading state

    render(
      <QueryClientProvider client={queryClient}>
        <VNPayReturnPage />
      </QueryClientProvider>
    )

    expect(screen.getByText('Xác thực thanh toán...')).toBeInTheDocument()
    expect(screen.getByText('Vui lòng chờ trong giây lát khi chúng tôi xác minh giao dịch của bạn.')).toBeInTheDocument()
  })

  it('renders success state when backend returns success', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({
      data: {
        verified: true,
        success: true,
        needs_signup: false,
      },
    })

    render(
      <QueryClientProvider client={queryClient}>
        <VNPayReturnPage />
      </QueryClientProvider>
    )

    await waitFor(() => {
      expect(screen.getByText('Thanh toán thành công!')).toBeInTheDocument()
    })

    expect(screen.getByText('Thanh toán đã được xác nhận. Hãy quay lại tài khoản của bạn để sử dụng Notch Pro.')).toBeInTheDocument()
    expect(screen.getByText('Mở lại ứng dụng Notch')).toBeInTheDocument()
    expect(screen.getByText('Về Trang cá nhân')).toBeInTheDocument()

    // Assert redirect is called
    await waitFor(() => {
      expect(launchPortalOAuthAppRedirect).toHaveBeenCalledWith('notch://visibility/show', expect.any(Object))
    })
  })

  it('renders failure state when backend returns failure', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({
      data: {
        verified: true,
        success: false,
        needs_signup: false,
      },
    })

    render(
      <QueryClientProvider client={queryClient}>
        <VNPayReturnPage />
      </QueryClientProvider>
    )

    await waitFor(() => {
      expect(screen.getByText('Thanh toán thất bại')).toBeInTheDocument()
    })

    expect(screen.getByText('Giao dịch không thành công hoặc đã bị hủy. Vui lòng thử lại.')).toBeInTheDocument()
    expect(screen.getByText('Thử thanh toán lại')).toBeInTheDocument()
  })

  it('renders error state when backend fetch fails', async () => {
    vi.mocked(apiClient.get).mockRejectedValue(new Error('Network Error'))

    render(
      <QueryClientProvider client={queryClient}>
        <VNPayReturnPage />
      </QueryClientProvider>
    )

    await waitFor(() => {
      expect(screen.getByText('Thanh toán thất bại')).toBeInTheDocument()
    })

    expect(screen.getByText('Lỗi: Network Error')).toBeInTheDocument()
  })
})
