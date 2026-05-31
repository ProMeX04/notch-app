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
import { NotFoundPage } from '@/pages/NotFoundPage'
import { AdminLayout } from '@/pages/Admin/AdminLayout'
import { AdminDashboardPage } from '@/pages/Admin/AdminDashboardPage'
import { AdminUsersPage } from '@/pages/Admin/AdminUsersPage'
import { AdminCapabilitiesPage } from '@/pages/Admin/AdminCapabilitiesPage'
import { AdminGeminiLivePage } from '@/pages/Admin/AdminGeminiLivePage'
import { AdminSettingsPage } from '@/pages/Admin/AdminSettingsPage'

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

const adminRoute = createRoute({ getParentRoute: () => rootRoute, path: '/admin', component: AdminLayout })
const adminIndexRoute = createRoute({ getParentRoute: () => adminRoute, path: '/', component: AdminDashboardPage })
const adminUsersRoute = createRoute({ getParentRoute: () => adminRoute, path: '/users', component: AdminUsersPage })
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
  adminRoute.addChildren([
    adminIndexRoute,
    adminUsersRoute,
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
