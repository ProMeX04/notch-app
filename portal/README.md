## Portal

Next.js account portal for Notch.

## Getting Started

1. Copy `.env.example` to `.env`.
2. Create a Neon Postgres database.
3. Put the pooled Neon URL in `DATABASE_URL` and the direct Neon URL in `DIRECT_URL`.
4. If you want to use VNPAY checkout, also fill:
   - `VNPAY_TMN_CODE`
   - `VNPAY_HASH_SECRET`
   - `VNPAY_PAYMENT_URL`
   - optional: `VNPAY_PRO_AMOUNT`
5. Run Prisma against the database, then start the app:

```bash
npx prisma db push
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

## Deploy on Vercel

Set the same `DATABASE_URL` and `DIRECT_URL` env vars in Vercel before deploying.

For VNPAY, set:
- `VNPAY_TMN_CODE`
- `VNPAY_HASH_SECRET`
- `VNPAY_PAYMENT_URL`
- optional: `VNPAY_PRO_AMOUNT`

The current VNPAY flow uses:
- `POST /api/payments/vnpay/create` to build the redirect URL
- `GET /api/payments/vnpay/ipn` for VNPAY server notification
- `/billing/vnpay/return` for the user redirect page after payment

The project is already linked to Vercel through `.vercel/project.json`.
