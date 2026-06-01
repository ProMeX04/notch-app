<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

# Portal Architecture Rule

Applies to `src/**`, `prisma/**`, and portal tests.

- Read `../docs/engineering/api-data-privacy.md` for API or data work and
  `../docs/engineering/portal-ui-patterns.md` for presentation work.
- Before changing or reviewing an HTTP/API contract, load the native
  `notch-portal-api-conventions` skill. Load `notch-swift-cloud-api-conventions`
  too when the macOS client contract changes.
- Before changing Portal pages/components/styles, load the native
  `notch-portal-ui-conventions` skill.
- Routes parse input, authenticate, invoke feature services, and return responses; business queries and mutations live in feature `lib`/service modules.
- Resolve identity, device ownership, authorization, and public privacy on the server. Never trust client ownership fields for ranking or user-visible identity.
- Important mutations log `AppEvent` with minimal privacy-safe metadata and ship tests for auth, validation, idempotency, and sensitive-field exclusion.
- UI pages consume service/API contracts; they do not duplicate ranking calculations or auth rules.
- Use `notch-verification-release` for schema resets, Vercel deployment, or
  production acceptance work.
