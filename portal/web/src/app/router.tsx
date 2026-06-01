import {
  Outlet,
  createRootRoute,
  createRoute,
  createRouter,
} from '@tanstack/react-router'

import { HomePage } from '@/pages/HomePage'
import { LoginPage } from '@/pages/LoginPage'
import { AccountPage } from '@/pages/AccountPage'
import { LeaderboardPage } from '@/pages/LeaderboardPage'
import { UpgradePage } from '@/pages/UpgradePage'
import { OAuthAuthorizePage } from '@/pages/OAuthAuthorizePage'
import { VNPayReturnPage } from '@/pages/VNPayReturnPage'
import { DownloadsPage } from '@/pages/DownloadsPage'
import { HelpPage } from '@/pages/HelpPage'
import { NotFoundPage } from '@/pages/NotFoundPage'
import { AdminLayout } from '@/pages/Admin/AdminLayout'
import { AdminDashboardPage } from '@/pages/Admin/AdminDashboardPage'
import { AdminUsersPage } from '@/pages/Admin/AdminUsersPage'
import { AdminUserDetailPage } from '@/pages/Admin/AdminUserDetailPage'
import { AdminCapabilitiesPage } from '@/pages/Admin/AdminCapabilitiesPage'
import { AdminGeminiLivePage } from '@/pages/Admin/AdminGeminiLivePage'
import { AdminSettingsPage } from '@/pages/Admin/AdminSettingsPage'
import '@/styles/admin.css'

const rootRoute = createRootRoute({
  component: Outlet,
  notFoundComponent: NotFoundPage,
})

const indexRoute = createRoute({ getParentRoute: () => rootRoute, path: '/', component: HomePage })
const loginRoute = createRoute({ getParentRoute: () => rootRoute, path: '/login', component: LoginPage })
const accountRoute = createRoute({ getParentRoute: () => rootRoute, path: '/account', component: AccountPage })
const leaderboardRoute = createRoute({ getParentRoute: () => rootRoute, path: '/leaderboard', component: LeaderboardPage })
const upgradeRoute = createRoute({ getParentRoute: () => rootRoute, path: '/upgrade', component: UpgradePage })
const oauthAuthorizeRoute = createRoute({ getParentRoute: () => rootRoute, path: '/oauth/authorize', component: OAuthAuthorizePage })
const billingVNPayReturnRoute = createRoute({ getParentRoute: () => rootRoute, path: '/billing/vnpay/return', component: VNPayReturnPage })
const downloadsRoute = createRoute({ getParentRoute: () => rootRoute, path: '/downloads', component: DownloadsPage })
const helpRoute = createRoute({ getParentRoute: () => rootRoute, path: '/help', component: HelpPage })

const adminRoute = createRoute({ getParentRoute: () => rootRoute, path: '/admin', component: AdminLayout })
const adminIndexRoute = createRoute({ getParentRoute: () => adminRoute, path: '/', component: AdminDashboardPage })
const adminUsersRoute = createRoute({ getParentRoute: () => adminRoute, path: '/users', component: AdminUsersPage })
const adminUserDetailRoute = createRoute({ getParentRoute: () => adminRoute, path: '/users/$id', component: AdminUserDetailPage })
const adminCapabilitiesRoute = createRoute({ getParentRoute: () => adminRoute, path: '/capabilities', component: AdminCapabilitiesPage })
const adminGeminiRoute = createRoute({ getParentRoute: () => adminRoute, path: '/gemini-live', component: AdminGeminiLivePage })
const adminSettingsRoute = createRoute({ getParentRoute: () => adminRoute, path: '/settings', component: AdminSettingsPage })

const routeTree = rootRoute.addChildren([
  indexRoute,
  loginRoute,
  accountRoute,
  leaderboardRoute,
  upgradeRoute,
  oauthAuthorizeRoute,
  billingVNPayReturnRoute,
  downloadsRoute,
  helpRoute,
  adminRoute.addChildren([
    adminIndexRoute,
    adminUsersRoute,
    adminUserDetailRoute,
    adminCapabilitiesRoute,
    adminGeminiRoute,
    adminSettingsRoute,
  ]),
])

export const router = createRouter({ routeTree })

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}
