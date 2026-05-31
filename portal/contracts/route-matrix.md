# Portal API Route Matrix

This matrix freezes the current Next.js Portal API surface before the Vite React + Go migration. Preserve paths and response semantics during the first Go implementation unless a later versioned contract explicitly changes them.

| Path | Methods | Auth | Source/Consumer | Domain | Notes |
| --- | --- | --- | --- | --- | --- |
| `/api/capabilities` | `GET` | Public | Web, app | Capabilities | Public capability policy/manifest projection. |
| `/api/admin/capabilities` | `GET`, `PATCH`/mutation | Admin | Web admin | Capabilities | Admin-only capability configuration. |
| `/api/admin/gemini-live/models` | `GET`, mutation | Admin | Web admin | Gemini | Admin-only Gemini Live model config. |
| `/api/admin/stats` | `GET` | Admin | Web admin | Admin | Dashboard stats. |
| `/api/admin/users` | `GET` | Admin | Web admin | Admin | User list; explicit privacy projection. |
| `/api/admin/users/{id}` | `GET`, mutation | Admin | Web admin | Admin | User detail/actions; never expose password/token fields. |
| `/api/auth/google` | `GET` | Public | Browser | Auth/OAuth | Starts Google web login. |
| `/api/auth/google/callback` | `GET` | Public callback | Google OAuth | Auth/OAuth | Completes Google login or Drive handoff; sets auth cookies for web login. |
| `/api/auth/google-drive` | `GET` | Public/auth flow | Browser/app | Google Drive | Starts Google Drive authorization. |
| `/api/auth/google-drive/exchange` | `POST` | App handoff | macOS app | Google Drive | Exchanges handoff token/challenge; token-sensitive. |
| `/api/auth/google-drive/refresh` | `POST` | App/client | macOS app | Google Drive | Refreshes Google Drive tokens; token-sensitive. |
| `/api/auth/login` | `POST` | Public | Web | Auth | Email/password login; issues cookies and auth payload. |
| `/api/auth/logout` | `POST` | Session/bearer optional | Web/app | Auth | Revokes session tokens and clears cookies. |
| `/api/auth/me` | `GET` | Cookie/bearer or refresh cookie | Web | Auth | Returns current user; may refresh from refresh cookie. |
| `/api/auth/refresh` | `POST` | Refresh token/cookie | Web/app | Auth | Rotates refresh/access tokens; clears cookies on failure. |
| `/api/auth/register` | `POST` | Public | Web | Auth | Creates account and session; may link guest payment. |
| `/api/auth/sessions` | `GET`, `PATCH` | Authenticated | Web account | Auth/device | Lists and mutates device/session trust/revoke state. |
| `/api/focus/leaderboard` | `GET` | Public | Web/app | Focus | Public allowlisted leaderboard; no private identity exposure. |
| `/api/focus/me` | `GET` | Authenticated | Web/app | Focus | Current user's focus summary/profile. |
| `/api/focus/profile` | `GET`, `PATCH` | Authenticated | Web/app | Focus | Leaderboard display/opt-in profile. |
| `/api/focus/sync` | `POST` | Authenticated device-bound | macOS app | Focus | Schema v2 cumulative sync; rejects client `device_id`. |
| `/api/gemini-live/health` | `GET` | Public or authenticated depending current route | Web/app | Gemini | Gemini service/config health. |
| `/api/gemini-live/models` | `GET` | Authenticated/feature-gated | Web/app | Gemini | Enabled model list under policy. |
| `/api/gemini-live/session-token` | `POST` | Authenticated/feature-gated | Web/app | Gemini | Issues Gemini Live session token; never log token payloads. |
| `/api/oauth/authorize` | `GET` | Authenticated web session | Browser/native app | Native OAuth | Creates PKCE authorization code and redirects to native URI. |
| `/api/oauth/token` | `POST` | OAuth client grant | macOS app | Native OAuth | Supports authorization code and refresh grants. |
| `/api/payments/vnpay/create` | `POST` | Authenticated | Web | Payments | Creates authenticated Pro upgrade order. |
| `/api/payments/vnpay/create-guest` | `POST` | Public with guest email | Web | Payments | Creates guest Pro order. |
| `/api/payments/vnpay/ipn` | `GET` | VNPay signed callback | VNPay | Payments | Verifies signature, amount, idempotency, grants entitlement. |

## Cross-cutting constraints

- Routes parse/auth/respond only; services own business rules.
- Identity, device ownership, admin status, entitlements, and public exposure are server-derived.
- Mutation routes log privacy-safe `AppEvent` rows.
- Do not log tokens, raw private payloads, emails/display names, task/message content, OAuth codes/verifiers, or payment signatures in event metadata.
- Preserve cookie names `notch_access_token` and `notch_refresh_token` for initial compatibility.
