import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import { HelpPage } from '@/pages/HelpPage'

// Mock dependencies
vi.mock('@/components/ui/PageShell', () => ({
  PageShell: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}))

describe('HelpPage', () => {
  it('renders FAQ questions and support contact details', () => {
    render(<HelpPage />)

    expect(screen.getByText('Trợ giúp & FAQ')).toBeInTheDocument()
    expect(screen.getByText('Làm sao để kết nối Chrome Focus Blocker?')).toBeInTheDocument()
    expect(screen.getByText('Làm sao để nâng cấp tài khoản Pro?')).toBeInTheDocument()
    expect(screen.getByText('support@notch.app')).toBeInTheDocument()
    expect(screen.getByText('Báo lỗi trên GitHub')).toBeInTheDocument()
  })

  it('toggles FAQ accordion expansion when clicked', () => {
    render(<HelpPage />)

    const questionElement = screen.getByText('Làm sao để nâng cấp tài khoản Pro?')
    const answerContainer = questionElement.closest('.portal-card')?.querySelector('div[style*="max-height"]')

    expect(answerContainer).toHaveStyle('max-height: 0px')
    expect(answerContainer).toHaveStyle('opacity: 0')

    // Click to expand
    fireEvent.click(questionElement)

    expect(answerContainer).toHaveStyle('max-height: 200px')
    expect(answerContainer).toHaveStyle('opacity: 1')

    // Click again to collapse
    fireEvent.click(questionElement)

    expect(answerContainer).toHaveStyle('max-height: 0px')
    expect(answerContainer).toHaveStyle('opacity: 0')
  })
})
