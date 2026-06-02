import {
  Outlet,
  createRootRoute,
  createRoute,
  createRouter,
} from '@tanstack/react-router'

import { HomePage } from '@/pages/HomePage'
import { AccountPage } from '@/pages/AccountPage'
import { OAuthAuthorizePage } from '@/pages/OAuthAuthorizePage'
import { VNPayReturnPage } from '@/pages/VNPayReturnPage'
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
const accountRoute = createRoute({ getParentRoute: () => rootRoute, path: '/account', component: AccountPage })
const oauthAuthorizeRoute = createRoute({ getParentRoute: () => rootRoute, path: '/oauth/authorize', component: OAuthAuthorizePage })
const billingVNPayReturnRoute = createRoute({ getParentRoute: () => rootRoute, path: '/billing/vnpay/return', component: VNPayReturnPage })

const adminRoute = createRoute({ getParentRoute: () => rootRoute, path: '/admin', component: AdminLayout })
const adminIndexRoute = createRoute({ getParentRoute: () => adminRoute, path: '/', component: AdminDashboardPage })
const adminUsersRoute = createRoute({ getParentRoute: () => adminRoute, path: '/users', component: AdminUsersPage })
const adminUserDetailRoute = createRoute({ getParentRoute: () => adminRoute, path: '/users/$id', component: AdminUserDetailPage })
const adminCapabilitiesRoute = createRoute({ getParentRoute: () => adminRoute, path: '/capabilities', component: AdminCapabilitiesPage })
const adminGeminiRoute = createRoute({ getParentRoute: () => adminRoute, path: '/gemini-live', component: AdminGeminiLivePage })
const adminSettingsRoute = createRoute({ getParentRoute: () => adminRoute, path: '/settings', component: AdminSettingsPage })

const routeTree = rootRoute.addChildren([
  indexRoute,
  accountRoute,
  oauthAuthorizeRoute,
  billingVNPayReturnRoute,
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
